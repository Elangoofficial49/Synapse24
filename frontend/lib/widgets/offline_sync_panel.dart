import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/offline_receipt_service.dart';

class OfflineSyncPanel extends StatefulWidget {
  final VoidCallback onSyncComplete;

  const OfflineSyncPanel({super.key, required this.onSyncComplete});

  static Future<void> show(BuildContext context, VoidCallback onSyncComplete) {
    return showDialog(
      context: context,
      builder: (ctx) => OfflineSyncPanel(onSyncComplete: onSyncComplete),
    );
  }

  @override
  State<OfflineSyncPanel> createState() => _OfflineSyncPanelState();
}

class _OfflineSyncPanelState extends State<OfflineSyncPanel> {
  bool _loading = true;
  bool _syncing = false;
  List<Map<String, dynamic>> _pendingReceipts = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    setState(() => _loading = true);
    try {
      final list = await OfflineReceiptService.getPendingReceipts();
      if (mounted) setState(() => _pendingReceipts = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerSync() async {
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final res = await OfflineReceiptService.syncPendingReceipts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Synchronized ${res['synced_count']} receipts with blockchain ledger.'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        await _loadQueue();
        widget.onSyncComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Synchronization failed: $e'),
              backgroundColor: AppTheme.errorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.sync, color: AppTheme.deepTeal),
          SizedBox(width: 8),
          Text('Offline Receipt Capture & Sync Panel'),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 440,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.navy.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.navy.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_pendingReceipts.length} Local Receipts In Queue',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Text(
                              'Stored offline with unique idempotency keys. Never commits before ledger verification.',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _syncing || _pendingReceipts.isEmpty
                              ? null
                              : _triggerSync,
                          icon: _syncing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Sync Now'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Sync Error: $_error',
                          style: const TextStyle(
                              color: AppTheme.errorRed, fontSize: 13)),
                    ),
                  const Text('Pending Offline Receipts:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _pendingReceipts.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline,
                                    color: AppTheme.successGreen, size: 40),
                                SizedBox(height: 8),
                                Text(
                                    'All receipts are fully synchronized with the blockchain ledger!'),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _pendingReceipts.length,
                            itemBuilder: (ctx, i) {
                              final item = _pendingReceipts[i];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.cloud_off,
                                      color: AppTheme.warningAmber),
                                  title: Text(
                                      '${item['shipment_reference']} · ${item['event_id']}'),
                                  subtitle: Text(
                                    'Received: ${item['actual_quantity_received']}/${item['declared_quantity']} pkgs\n'
                                    'Captured: ${item['device_timestamp']}\n'
                                    'STATUS: OFFLINE — NOT YET BLOCKCHAIN-VERIFIED',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: AppTheme.errorRed),
                                    tooltip: 'Discard pending receipt',
                                    onPressed: () async {
                                      await OfflineReceiptService.removeReceipt(
                                          item['event_id']);
                                      await _loadQueue();
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}
