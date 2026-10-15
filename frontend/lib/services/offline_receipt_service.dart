import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class OfflineReceiptService {
  static const String _storageKey = 'pharmatrace_pending_offline_receipts';
  static final Random _random = Random.secure();

  static String _generateHex(int length) {
    const chars = '0123456789abcdef';
    return List.generate(length, (_) => chars[_random.nextInt(16)]).join();
  }

  // Save an offline receipt locally with idempotency key
  static Future<Map<String, dynamic>> saveOfflineReceipt({
    required String shipmentId,
    required String shipmentReference,
    required int actualQuantityReceived,
    required int declaredQuantity,
    List<String>? scannedPackageSerialIds,
    String? notes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ?? [];

    final eventId = 'OFFLINE-${_generateHex(8).toUpperCase()}';
    final idempotencyKey = 'IDEMP-${_generateHex(16)}';
    final record = {
      'event_id': eventId,
      'idempotency_key': idempotencyKey,
      'shipment_id': shipmentId,
      'shipment_reference': shipmentReference,
      'actual_quantity_received': actualQuantityReceived,
      'declared_quantity': declaredQuantity,
      'scanned_package_serial_ids': scannedPackageSerialIds ?? [],
      'notes': notes,
      'device_timestamp': DateTime.now().toUtc().toIso8601String(),
      'status': 'PENDING_SYNC', // PENDING_SYNC, SYNCED, CONFLICT, FAILED
    };

    rawList.add(jsonEncode(record));
    await prefs.setStringList(_storageKey, rawList);
    return record;
  }

  // Retrieve all locally stored receipts
  static Future<List<Map<String, dynamic>>> getPendingReceipts() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ?? [];
    return rawList
        .map((item) => jsonDecode(item))
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  // Clear specific synced receipt
  static Future<void> removeReceipt(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ?? [];
    final updated = rawList.where((item) {
      final decoded = jsonDecode(item) as Map<String, dynamic>;
      return decoded['event_id'] != eventId;
    }).toList();
    await prefs.setStringList(_storageKey, updated);
  }

  // Synchronize all pending receipts with backend
  static Future<Map<String, dynamic>> syncPendingReceipts() async {
    final receipts = await getPendingReceipts();
    final pending =
        receipts.where((r) => r['status'] == 'PENDING_SYNC').toList();
    if (pending.isEmpty) {
      return {'synced_count': 0, 'results': []};
    }

    try {
      final syncResult = await apiService.syncOfflineReceipts(pending);
      final results = (syncResult['results'] as List<dynamic>?) ?? [];

      for (final res in results) {
        final eventId = res['event_id']?.toString();
        if (eventId != null && res['status'] == 'SYNCHRONIZED') {
          await removeReceipt(eventId);
        }
      }

      return syncResult;
    } catch (e) {
      if (kDebugMode) {
        print('Offline sync error: $e');
      }
      rethrow;
    }
  }
}
