import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8000/api/v1';
  late final Dio dio;

  ApiService() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  // Authentication
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    final data = response.data;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', data['access_token']);
    await prefs.setString('current_user', jsonEncode(data['user']));
    return data;
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> details) async {
    final response = await dio.post('/auth/register', data: details);
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> sendRegistrationOtp(String email) async {
    await dio.post('/auth/registration-otp', data: {'email': email});
  }

  Future<void> verifyRegistrationOtp(String email, String code) async {
    await dio.post('/auth/verify-registration-otp', data: {
      'email': email,
      'code': code,
    });
  }

  Future<List<dynamic>> getPendingUsers() async {
    final response = await dio.get('/auth/pending-users');
    return response.data;
  }

  Future<void> approveUser(String userId) async {
    await dio.post('/auth/users/$userId/approve');
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('current_user');
    if (value == null) return null;
    return Map<String, dynamic>.from(jsonDecode(value));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('current_user');
  }

  // Verification
  Future<Map<String, dynamic>> verifyPackage(String rawData) async {
    final response = await dio.post('/verify', data: {'raw_data': rawData});
    return response.data;
  }

  // Products & Batches
  Future<List<dynamic>> getProducts() async {
    final response = await dio.get('/products');
    return response.data;
  }

  Future<List<dynamic>> getBatches() async {
    final response = await dio.get('/batches');
    return response.data;
  }

  Future<List<dynamic>> getPackages({String? batchId}) async {
    final response = await dio.get(
      '/packages',
      queryParameters: batchId == null ? null : {'batch_id': batchId},
    );
    return response.data;
  }

  Future<Map<String, dynamic>> getManufacturerDashboard() async {
    final response = await dio.get('/manufacturer/dashboard');
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> initiateRecall({
    required String batchId,
    required String reason,
    required String severity,
  }) async {
    final response = await dio.post('/manufacturer/recalls', data: {
      'batch_id': batchId,
      'recall_reason': reason,
      'severity': severity,
    });
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> uploadBatchDocument(
    String batchId,
    PlatformFile file,
  ) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      throw StateError('Documents must be 10 MB or smaller.');
    }
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: file.name,
        contentType: MultipartFile.lookupMediaType(file.name),
      ),
    });
    final response = await dio.post(
      '/manufacturer/batches/$batchId/documents',
      data: form,
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<int>> downloadBatchDocument(String documentId) async {
    final response = await dio.get<List<int>>(
      '/manufacturer/documents/$documentId/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? <int>[];
  }

  Future<Map<String, dynamic>> createProduct(
      Map<String, dynamic> product) async {
    final response = await dio.post('/products', data: product);
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> createBatch(Map<String, dynamic> batch) async {
    final response = await dio.post('/batches', data: batch);
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<dynamic>> generatePackages(String batchId, int count) async {
    final response = await dio.post(
      '/batches/$batchId/generate-packages',
      data: {'batch_id': batchId, 'count': count},
    );
    return response.data;
  }

  // Shipments & Two-Party Custody
  Future<List<dynamic>> getShipments() async {
    final response = await dio.get('/shipments');
    return response.data;
  }

  Future<List<dynamic>> getTransferInventory() async {
    final response = await dio.get('/shipments/inventory');
    return response.data;
  }

  Future<Map<String, dynamic>> getDistributorDashboard() async {
    final response = await dio.get('/shipments/distributor-dashboard');
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<dynamic>> getPharmacyDirectory() async {
    final response = await dio.get('/organizations/pharmacies');
    return response.data;
  }

  Future<List<dynamic>> getWholesalerPartners() async {
    final response = await dio.get('/organizations/partners');
    return response.data;
  }

  Future<Map<String, dynamic>> createShipment(
    String receiverOrganizationId,
    List<String> packageSerialIds, {
    String? notes,
  }) async {
    final response = await dio.post('/shipments', data: {
      'receiver_org_id': receiverOrganizationId,
      'package_serial_ids': packageSerialIds,
      'notes': notes,
    });
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getShipmentDetails(String shipmentId) async {
    final response = await dio.get('/shipments/$shipmentId');
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> receiveShipment(
    String shipmentId,
    int actualQuantity,
    String? notes, {
    List<String>? scannedPackageSerialIds,
  }) async {
    final response = await dio.post('/shipments/$shipmentId/receive', data: {
      'actual_quantity_received': actualQuantity,
      'notes': notes,
      'scanned_package_serial_ids': scannedPackageSerialIds,
    });
    return Map<String, dynamic>.from(response.data);
  }

  // Disputes & Alerts
  Future<List<dynamic>> getDisputes() async {
    final response = await dio.get('/disputes');
    return response.data;
  }

  Future<List<dynamic>> getAlerts() async {
    final response = await dio.get('/alerts');
    return response.data;
  }

  Future<Map<String, dynamic>> updateAlert(
    String alertId, {
    required String reviewStatus,
    String? investigatorNotes,
    String? resolutionOutcome,
  }) async {
    final response = await dio.put('/alerts/$alertId', data: {
      'review_status': reviewStatus,
      'investigator_notes': investigatorNotes,
      'resolution_outcome': resolutionOutcome,
    });
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> resolveDispute(
    String disputeId, {
    required String resolutionNotes,
    String? correctionJustification,
  }) async {
    final response = await dio.post('/disputes/$disputeId/resolve', data: {
      'resolution_notes': resolutionNotes,
      'status': 'resolved',
      'correction_justification': correctionJustification,
    });
    return Map<String, dynamic>.from(response.data);
  }

  // Analytics
  Future<Map<String, dynamic>> getDashboardMetrics() async {
    final response = await dio.get('/analytics/dashboard');
    return response.data;
  }

  // Pharmacy
  Future<Map<String, dynamic>> getPharmacyDashboard() async {
    final response = await dio.get('/shipments/distributor-dashboard');
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> dispensePackage({
    required String packageSerialId,
    String? patientReference,
    String? notes,
  }) async {
    final response = await dio.post('/shipments/dispense', data: {
      'package_serial_id': packageSerialId,
      'patient_reference': patientReference,
      'notes': notes,
    });
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> reportSuspiciousProduct({
    required String packageSerialId,
    required String reason,
    String severity = 'high',
  }) async {
    final response = await dio.post('/alerts/report', data: {
      'package_serial_id': packageSerialId,
      'reason': reason,
      'severity': severity,
    });
    return Map<String, dynamic>.from(response.data);
  }
}

final apiService = ApiService();
