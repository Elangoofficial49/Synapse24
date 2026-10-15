import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/offline_receipt_service.dart';
import '../widgets/dispute_investigation_dialog.dart';
import '../widgets/offline_sync_panel.dart';
import '../widgets/package_verification_card.dart';
import '../widgets/qr_scanner_dialog.dart';
import '../widgets/recall_impact_simulator_view.dart';

class DistributorTools extends StatefulWidget {
  final int initialTabIndex;

  const DistributorTools({super.key, this.initialTabIndex = 0});

  @override
  State<DistributorTools> createState() => _DistributorToolsState();
}

class _DistributorToolsState extends State<DistributorTools>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  Map<String, dynamic> _summary = {};
  String? _organizationId;
  List<dynamic> _shipments = [];
  List<dynamic> _incomingShipments = [];
  List<dynamic> _outgoingShipments = [];
  List<dynamic> _inventory = [];
  List<dynamic> _pharmacies = [];
  List<dynamic> _recalls = [];
  List<dynamic> _alerts = [];
  List<dynamic> _disputes = [];
  List<dynamic> _notifications = [];
  Map<String, dynamic>? _verificationResult;
  final TextEditingController _verificationController = TextEditingController();
  final TextEditingController _scanReceiveController = TextEditingController();
  Map<String, dynamic>? _scanReceiveResult;
  bool _isScanningOrReceiving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 14,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 13),
    );
    _load();
  }

  @override
  void didUpdateWidget(DistributorTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      final target = widget.initialTabIndex.clamp(0, 13);
      if (_tabController.index != target) {
        _tabController.animateTo(target);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _verificationController.dispose();
    _scanReceiveController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        apiService.getDistributorDashboard(),
        apiService.getPharmacyDirectory(),
      ]);
      if (!mounted) return;
      final dashboard = results[0] as Map<String, dynamic>;
      final rawShipments =
          List<dynamic>.from(dashboard['shipments'] as List? ?? []);
      final rawIncoming =
          List<dynamic>.from(dashboard['incoming_shipments'] as List? ?? []);
      final rawOutgoing =
          List<dynamic>.from(dashboard['outgoing_shipments'] as List? ?? []);
      final rawInventory =
          List<dynamic>.from(dashboard['inventory'] as List? ?? []);
      final rawRecalls =
          List<dynamic>.from(dashboard['recalls'] as List? ?? []);
      final rawAlerts = List<dynamic>.from(dashboard['alerts'] as List? ?? []);
      final rawDisputes =
          List<dynamic>.from(dashboard['disputes'] as List? ?? []);
      final rawNotifications =
          List<dynamic>.from(dashboard['notifications'] as List? ?? []);

      int compareDesc(dynamic a, dynamic b) {
        final aTime = (a['created_at'] ??
                a['dispatch_timestamp'] ??
                a['manufacturing_date'] ??
                '')
            .toString();
        final bTime = (b['created_at'] ??
                b['dispatch_timestamp'] ??
                b['manufacturing_date'] ??
                '')
            .toString();
        return bTime.compareTo(aTime);
      }

      rawShipments.sort(compareDesc);
      rawIncoming.sort(compareDesc);
      rawOutgoing.sort(compareDesc);
      rawInventory.sort(compareDesc);
      rawRecalls.sort(compareDesc);
      rawAlerts.sort(compareDesc);
      rawDisputes.sort(compareDesc);
      rawNotifications.sort(compareDesc);

      setState(() {
        _organizationId = dashboard['organization_id']?.toString();
        _summary = Map<String, dynamic>.from(dashboard['summary'] as Map);
        _shipments = rawShipments;
        _incomingShipments = rawIncoming;
        _outgoingShipments = rawOutgoing;
        _inventory = rawInventory;
        _recalls = rawRecalls;
        _alerts = rawAlerts;
        _disputes = rawDisputes;
        _notifications = rawNotifications;
        _pharmacies = results[1] as List<dynamic>;
      });
    } catch (error) {
      if (mounted) _showError('Unable to load distributor dashboard: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorRed),
    );
  }

  Future<void> _verifyPackage(String rawData) async {
    final raw = rawData.trim();
    if (raw.isEmpty) return;
    try {
      final result = await apiService.verifyPackage(raw);
      if (!mounted) return;
      setState(() {
        _verificationController.text = raw;
        _verificationResult = result;
      });
    } catch (error) {
      if (mounted) _showError('Package verification failed: $error');
    }
  }

  Future<void> _scanForVerification() async {
    await QrScannerDialog.show(
      context,
      onScanned: (value) => _verifyPackage(value),
    );
  }

  Future<void> _scanReceiptPackage(
    String raw,
    Set<String> expectedSerials,
    Set<String> scannedSerials,
    StateSetter setDialogState,
  ) async {
    try {
      final result = await apiService.verifyPackage(raw);
      if (result['is_valid'] != true) {
        _showError(
            'This QR code is not registered. It was not added to receipt.');
        return;
      }
      final serial = result['package_serial_id']?.toString();
      if (serial == null || !expectedSerials.contains(serial)) {
        _showError(
            'This verified package is not part of the selected shipment.');
        return;
      }
      if (result['is_recalled'] == true ||
          result['is_expired'] == true ||
          result['status'] == 'quarantined') {
        _showError(
          'This package is expired, recalled, or quarantined and cannot be accepted.',
        );
        return;
      }
      if (scannedSerials.contains(serial)) {
        _showError('Package $serial was already scanned for this receipt.');
        return;
      }
      setDialogState(() => scannedSerials.add(serial));
    } catch (error) {
      if (mounted) _showError('Could not verify scanned package: $error');
    }
  }

  Future<void> _confirmScannedReceipt(dynamic shipment) async {
    final items = shipment['items'] as List<dynamic>? ?? [];
    final expectedSerials =
        items.map((item) => item['package_serial_id'].toString()).toSet();
    final scannedSerials = <String>{};
    final serialController = TextEditingController();
    final reasonController = TextEditingController();
    var noPackagesReceived = false;
    final receipt = await showDialog<(List<String>, String?)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Scan & receive · ${shipment['shipment_reference']}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scan each manufacturer QR code. Only verified packages listed on this shipment can be accepted. '
                  '${scannedSerials.length} of ${shipment['declared_quantity']} verified.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: noPackagesReceived
                            ? null
                            : () => QrScannerDialog.show(
                                  dialogContext,
                                  onScanned: (value) => _scanReceiptPackage(
                                    value,
                                    expectedSerials,
                                    scannedSerials,
                                    setDialogState,
                                  ),
                                ),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Scan package QR'),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: serialController,
                        enabled: !noPackagesReceived,
                        decoration: const InputDecoration(
                          labelText: 'Or enter scanned QR / serial',
                        ),
                        onSubmitted: (value) {
                          if (value.trim().isEmpty) return;
                          _scanReceiptPackage(
                            value,
                            expectedSerials,
                            scannedSerials,
                            setDialogState,
                          );
                          serialController.clear();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Verify package',
                      onPressed: noPackagesReceived
                          ? null
                          : () {
                              final value = serialController.text.trim();
                              if (value.isEmpty) return;
                              _scanReceiptPackage(
                                value,
                                expectedSerials,
                                scannedSerials,
                                setDialogState,
                              );
                              serialController.clear();
                            },
                      icon: const Icon(Icons.check_circle_outline),
                    ),
                  ],
                ),
                if (scannedSerials.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView(
                      shrinkWrap: true,
                      children: scannedSerials
                          .map((serial) => ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.verified,
                                  color: AppTheme.successGreen,
                                ),
                                title: Text(serial),
                                trailing: IconButton(
                                  tooltip: 'Remove scan',
                                  onPressed: () => setDialogState(
                                      () => scannedSerials.remove(serial)),
                                  icon: const Icon(Icons.close),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: noPackagesReceived,
                  title: const Text('No packages were received'),
                  onChanged: (value) => setDialogState(() {
                    noPackagesReceived = value == true;
                    if (noPackagesReceived) scannedSerials.clear();
                  }),
                ),
                if (scannedSerials.length !=
                        (shipment['declared_quantity'] as num).toInt() ||
                    noPackagesReceived)
                  TextField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Discrepancy reason (required)',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: scannedSerials.isEmpty && !noPackagesReceived
                  ? null
                  : () async {
                      final quantity =
                          noPackagesReceived ? 0 : scannedSerials.length;
                      final declared =
                          (shipment['declared_quantity'] as num).toInt();
                      final reason = reasonController.text.trim();
                      if (quantity != declared && reason.isEmpty) {
                        _showError('A reason is required for a discrepancy.');
                        return;
                      }
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(dialogContext);
                      final receiptRecord =
                          await OfflineReceiptService.saveOfflineReceipt(
                        shipmentId: shipment['id'].toString(),
                        shipmentReference:
                            shipment['shipment_reference'].toString(),
                        actualQuantityReceived: quantity,
                        declaredQuantity: declared,
                        notes: reason.isEmpty ? null : reason,
                        scannedPackageSerialIds: scannedSerials.toList(),
                      );
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Receipt queued offline [Key: ${receiptRecord['idempotency_key'].toString().substring(0, 8)}...]. Sync when online.',
                          ),
                          backgroundColor: AppTheme.deepTeal,
                        ),
                      );
                    },
              icon: const Icon(Icons.cloud_off_outlined),
              label: const Text('Save Offline'),
            ),
            ElevatedButton(
              onPressed: scannedSerials.isEmpty && !noPackagesReceived
                  ? null
                  : () {
                      final quantity =
                          noPackagesReceived ? 0 : scannedSerials.length;
                      final declared =
                          (shipment['declared_quantity'] as num).toInt();
                      final reason = reasonController.text.trim();
                      if (quantity != declared && reason.isEmpty) {
                        _showError('A reason is required for a discrepancy.');
                        return;
                      }
                      Navigator.pop(
                        dialogContext,
                        (
                          scannedSerials.toList(growable: false),
                          reason.isEmpty ? null : reason,
                        ),
                      );
                    },
              child: const Text('Confirm receipt'),
            ),
          ],
        ),
      ),
    );
    serialController.dispose();
    reasonController.dispose();
    if (receipt == null) return;
    final scanned = receipt.$1;
    final declared = (shipment['declared_quantity'] as num).toInt();
    final reason = receipt.$2;
    try {
      final result = await apiService.receiveShipment(
        shipment['id'].toString(),
        scanned.length,
        reason,
        scannedPackageSerialIds: scanned,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scanned.length == declared
                ? 'Receipt recorded on the ledger (${result['tx_reference'] ?? 'transaction reference pending'}).'
                : 'Receipt discrepancy recorded and sent to the manufacturer (${result['tx_reference'] ?? 'transaction reference pending'}).',
          ),
          backgroundColor: scanned.length == declared
              ? AppTheme.successGreen
              : AppTheme.warningAmber,
        ),
      );
      await _load();
      if (mounted) {
        _tabController.animateTo(4);
      }
    } catch (error) {
      if (mounted) _showError('Could not confirm shipment receipt: $error');
    }
  }

  List<Map<String, dynamic>> get _availablePackages => _inventory
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .where(
        (package) =>
            ['received', 'manufactured'].contains(package['status']) &&
            package['batch_status'] != 'recalled' &&
            DateTime.parse(package['expiry_date'].toString())
                .isAfter(DateTime.now()),
      )
      .toList();

  Future<void> _createPharmacyOrder() async {
    if (_pharmacies.isEmpty) {
      _showError(
          'No verified pharmacies are currently available. Please onboard a pharmacy first.');
      return;
    }
    final available = _availablePackages;
    final selectedPackages = <String>{};
    final notesController = TextEditingController();
    var selectedPharmacyId = _pharmacies.first['id'].toString();
    final packageSerials = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: AppTheme.deepTeal),
              SizedBox(width: 8),
              Text('Create Pharmacy Order & Dispatch'),
            ],
          ),
          content: SizedBox(
            width: 580,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedPharmacyId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select Verified Recipient Pharmacy',
                    prefixIcon: Icon(Icons.local_pharmacy_outlined),
                  ),
                  items: _pharmacies
                      .map((pharmacy) => DropdownMenuItem<String>(
                            value: pharmacy['id'].toString(),
                            child: Text(
                              '${pharmacy['name']} (${pharmacy['license_number'] ?? 'Verified'})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedPharmacyId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (available.isEmpty) ...[
                  Expanded(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  AppTheme.warningAmber.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inventory_2_outlined,
                                size: 48, color: AppTheme.warningAmber),
                            const SizedBox(height: 12),
                            const Text(
                              'No stock available in inventory',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.navy),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'There are no received, active medicine packages in storage to dispatch. '
                              'Please scan & receive incoming manufacturer deliveries first to replenish stock.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                _tabController
                                    .animateTo(2); // Go to Scan & Receive
                              },
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Go to Scan & Receive'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  Builder(
                    builder: (ctx) {
                      final allSerials = available
                          .map((p) => p['package_serial_id'].toString())
                          .toSet();
                      final isAllSelected =
                          selectedPackages.length == allSerials.length &&
                              allSerials.isNotEmpty;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select packages (${selectedPackages.length}/${available.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                if (isAllSelected) {
                                  selectedPackages.clear();
                                } else {
                                  selectedPackages.addAll(allSerials);
                                }
                              });
                            },
                            icon: Icon(
                              isAllSelected
                                  ? Icons.deselect_outlined
                                  : Icons.select_all_outlined,
                              size: 18,
                            ),
                            label: Text(
                                isAllSelected ? 'Deselect All' : 'Select All'),
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Builder(
                      builder: (ctx) {
                        final Map<String, List<Map<String, dynamic>>>
                            packagesByBatch = {};
                        for (final pkg in available) {
                          final key =
                              '${pkg['product_name']} · Batch ${pkg['batch_number']}';
                          packagesByBatch.putIfAbsent(key, () => []).add(pkg);
                        }

                        return ListView(
                          children: packagesByBatch.entries.map((entry) {
                            final batchTitle = entry.key;
                            final batchItems = entry.value;
                            final batchSerials = batchItems
                                .map((p) => p['package_serial_id'].toString())
                                .toSet();
                            final isBatchAllSelected = batchSerials.every(
                              (s) => selectedPackages.contains(s),
                            );

                            return Container(
                              margin: const EdgeInsets.only(top: 8, bottom: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.border),
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.grey.withValues(alpha: 0.03),
                              ),
                              child: ExpansionTile(
                                initiallyExpanded: true,
                                dense: true,
                                title: Text(
                                  batchTitle,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppTheme.navy,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          if (isBatchAllSelected) {
                                            selectedPackages
                                                .removeAll(batchSerials);
                                          } else {
                                            selectedPackages
                                                .addAll(batchSerials);
                                          }
                                        });
                                      },
                                      child: Text(
                                        isBatchAllSelected
                                            ? 'Deselect Batch'
                                            : 'Select Batch (${batchItems.length})',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    const Icon(Icons.expand_more, size: 20),
                                  ],
                                ),
                                children: batchItems.map((package) {
                                  final serial =
                                      package['package_serial_id'].toString();
                                  return CheckboxListTile(
                                    dense: true,
                                    value: selectedPackages.contains(serial),
                                    onChanged: (selected) => setDialogState(() {
                                      if (selected == true) {
                                        selectedPackages.add(serial);
                                      } else {
                                        selectedPackages.remove(serial);
                                      }
                                    }),
                                    title: Text(serial,
                                        style: const TextStyle(fontSize: 13)),
                                    subtitle: Text(
                                      'Expires ${package['expiry_date']}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                }).toList(),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Order / delivery notes (optional)',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            if (available.isNotEmpty)
              ElevatedButton(
                onPressed: selectedPackages.isEmpty
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          selectedPackages.toList(growable: false),
                        ),
                child: Text('Dispatch ${selectedPackages.length} packages'),
              ),
          ],
        ),
      ),
    );
    final notes = notesController.text.trim();
    notesController.dispose();
    if (packageSerials == null || packageSerials.isEmpty) return;
    try {
      final shipment = await apiService.createShipment(
        selectedPharmacyId,
        packageSerials,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order ${shipment['shipment_reference']} dispatched to the pharmacy and recorded on the ledger.',
          ),
          backgroundColor: AppTheme.successGreen,
        ),
      );
      await _load();
      if (mounted) {
        _tabController.animateTo(8);
      }
    } catch (error) {
      if (mounted) _showError('Could not dispatch pharmacy order: $error');
    }
  }

  Widget _buildOverviewTab() {
    final metrics = [
      ('Incoming shipments', 'incoming_shipments', Icons.move_to_inbox),
      ('Received batches', 'received_batches', Icons.inventory),
      ('Batches in storage', 'batches_in_storage', Icons.warehouse_outlined),
      ('Outgoing shipments', 'outgoing_shipments', Icons.outbox_outlined),
      ('Open alerts', 'open_alerts', Icons.warning_amber_outlined),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Distributor overview',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map((metric) => SizedBox(
                    width: 205,
                    child: Card(
                      child: ListTile(
                        leading: Icon(metric.$3, color: AppTheme.deepTeal),
                        title: Text(
                          '${_summary[metric.$2] ?? 0}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(metric.$1),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 20),
        const Text(
          'Recent notifications',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (_notifications.isEmpty)
          const Card(
            child:
                ListTile(title: Text('No current distributor notifications.')),
          )
        else
          ..._notifications.take(5).map(_notificationTile),
      ],
    );
  }

  Widget _buildIncomingTab() {
    if (_incomingShipments.isEmpty) {
      return const Center(
          child: Text('No incoming shipments awaiting receipt.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _incomingShipments
          .map((shipment) => _shipmentCard(
                shipment,
                showItems: true,
                action: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        _tabController.animateTo(2); // Go to Scan & Receive
                      },
                      icon: const Icon(Icons.qr_code_scanner, size: 16),
                      label: const Text('Quick Scan'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _confirmScannedReceipt(shipment),
                      icon: const Icon(Icons.checklist, size: 16),
                      label: const Text('Verify & Receive All'),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Future<void> _handleDirectScanAndReceive(String rawData) async {
    final raw = rawData.trim();
    if (raw.isEmpty) return;
    setState(() {
      _isScanningOrReceiving = true;
      _scanReceiveResult = null;
    });

    try {
      final verifyRes = await apiService.verifyPackage(raw);
      if (!mounted) return;
      setState(() {
        _scanReceiveController.text = raw;
        _scanReceiveResult = verifyRes;
      });

      if (verifyRes['is_valid'] != true) {
        _showError('This QR code is invalid or unregistered.');
        return;
      }
      if (verifyRes['is_recalled'] == true ||
          verifyRes['is_expired'] == true ||
          verifyRes['status'] == 'quarantined') {
        _showError(
            'Package is restricted (${verifyRes['status'] ?? 'recalled/expired'}) and cannot be received into active stock.');
        return;
      }

      final serial = verifyRes['package_serial_id']?.toString();
      if (serial == null) return;

      // Check if package belongs to any pending incoming shipment
      dynamic targetShipment;
      for (final shipment in _incomingShipments) {
        final items = shipment['items'] as List<dynamic>? ?? [];
        if (items
            .any((item) => item['package_serial_id']?.toString() == serial)) {
          targetShipment = shipment;
          break;
        }
      }

      if (targetShipment != null) {
        final shipmentId = targetShipment['id'].toString();
        // Confirm receipt of this package on the shipment
        final receiveRes = await apiService.receiveShipment(
          shipmentId,
          1,
          'Scanned and received batch package $serial via QR Scanner',
          scannedPackageSerialIds: [serial],
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Package $serial verified & marked as RECEIVED on shipment ${targetShipment['shipment_reference']} (Ledger tx: ${receiveRes['tx_reference'] ?? 'confirmed'}).',
            ),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        await _load();
      } else {
        // If not in a pending incoming shipment, check if already in inventory or custody
        final inInventory = _inventory
            .any((pkg) => pkg['package_serial_id']?.toString() == serial);
        if (inInventory) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Package $serial is already in distributor inventory and marked as Received.'),
              backgroundColor: AppTheme.deepTeal,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Package $serial verified on ledger! Identity and authenticity confirmed.'),
              backgroundColor: AppTheme.navy,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) _showError('Scan & verification error: $e');
    } finally {
      if (mounted) setState(() => _isScanningOrReceiving = false);
    }
  }

  Widget _buildScanAndReceiveTab() {
    // Received items list from inventory and received shipments
    final receivedInventory = _inventory
        .where((pkg) => ['received', 'manufactured'].contains(pkg['status']))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: AppTheme.navy, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan & Receive Verification',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.navy),
                          ),
                          Text(
                            'Scan incoming batch QR codes to verify authenticity, blockchain provenance, and mark packages as received.',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _scanReceiveController,
                        enabled: !_isScanningOrReceiving,
                        decoration: const InputDecoration(
                          labelText: 'Scan QR code or enter package serial ID',
                          hintText:
                              'e.g. PT-BATCH-2024-001-XXXX or raw QR code URL',
                          prefixIcon: Icon(Icons.qr_code_2),
                        ),
                        onSubmitted: (val) => _handleDirectScanAndReceive(val),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 16),
                      ),
                      onPressed: _isScanningOrReceiving
                          ? null
                          : () => QrScannerDialog.show(
                                context,
                                onScanned: (val) =>
                                    _handleDirectScanAndReceive(val),
                              ),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera Scan'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 16),
                        backgroundColor: AppTheme.deepTeal,
                      ),
                      onPressed: _isScanningOrReceiving
                          ? null
                          : () => _handleDirectScanAndReceive(
                              _scanReceiveController.text),
                      icon: _isScanningOrReceiving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.verified),
                      label: const Text('Verify & Receive'),
                    ),
                  ],
                ),
                if (_scanReceiveResult != null) ...[
                  const SizedBox(height: 16),
                  PackageVerificationCard(result: _scanReceiveResult!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppTheme.successGreen, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Received',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navy,
                  ),
                ),
                const SizedBox(width: 10),
                Chip(
                  label: Text(
                    '${receivedInventory.length} packages',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.successGreen,
                        fontSize: 12),
                  ),
                  backgroundColor: const Color(0xFFE8F5E9),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (receivedInventory.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No received batches yet. Scan a batch QR code above or confirm incoming shipments to record received stock.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ),
          )
        else
          ...receivedInventory.map((pkg) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.inventory_2,
                        color: AppTheme.successGreen, size: 20),
                  ),
                  title: Text(
                    '${pkg['product_name'] ?? 'Product'} · Batch ${pkg['batch_number'] ?? 'N/A'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Serial: ${pkg['package_serial_id']}\n'
                    'Expires: ${pkg['expiry_date']} · Manufacturer: ${pkg['manufacturer_name'] ?? 'Authorized Manufacturer'}',
                  ),
                  isThreeLine: true,
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.successGreen.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified,
                            size: 14, color: AppTheme.successGreen),
                        SizedBox(width: 4),
                        Text(
                          'Received',
                          style: TextStyle(
                            color: AppTheme.successGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildReceiptConfirmationTab() {
    final received = _shipments.where((shipment) =>
        shipment['receiver_org_id'] == _organizationId &&
        ['received', 'partially_received', 'rejected', 'disputed']
            .contains(shipment['status']));
    final records = received.toList();
    if (records.isEmpty && _disputes.isEmpty) {
      return const Center(
          child: Text('No receipt confirmations recorded yet.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...records.map((shipment) => _shipmentCard(shipment, showItems: true)),
        if (_disputes.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Receipt disputes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ..._disputes.map((dispute) => Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.gavel_outlined,
                    color: AppTheme.warningAmber,
                  ),
                  title: Text(dispute['shipment_reference'].toString()),
                  subtitle: Text(
                    '${dispute['dispute_reason']}\n'
                    'Expected ${dispute['expected_quantity']} · '
                    'Received ${dispute['actual_quantity']} · '
                    '${dispute['status']}',
                  ),
                  isThreeLine: true,
                  trailing: ElevatedButton.icon(
                    onPressed: () => DisputeInvestigationDialog.show(
                      context,
                      dispute: Map<String, dynamic>.from(dispute as Map),
                      onUpdated: _load,
                    ),
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Investigate'),
                  ),
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildInventoryTab() {
    if (_inventory.isEmpty) {
      return const Center(
          child: Text('There are no packages in your custody.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _inventory.length,
      itemBuilder: (context, index) {
        final item = _inventory[index];
        final quarantined =
            ['recalled', 'quarantined'].contains(item['status']) ||
                item['batch_status'] == 'recalled';
        return Card(
          child: ListTile(
            leading: Icon(
              quarantined ? Icons.gpp_bad_outlined : Icons.inventory_2_outlined,
              color: quarantined ? AppTheme.errorRed : AppTheme.deepTeal,
            ),
            title: Text('${item['product_name']} · ${item['batch_number']}'),
            subtitle: Text(
              '${item['package_serial_id']} · ${item['manufacturer_name']}\n'
              'Expires ${item['expiry_date']} · Status ${item['status']}',
            ),
            isThreeLine: true,
            trailing: quarantined
                ? const Chip(label: Text('Do not transfer'))
                : const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Future<void> _onboardPharmacyDialog() async {
    final nameController = TextEditingController();
    final licenseController = TextEditingController();
    final addressController = TextEditingController();
    final emailController = TextEditingController();
    final otpController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool otpSent = false;
    bool otpSending = false;
    String? otpFeedback;
    String? demoOtpCode;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> sendOtp() async {
            final email = emailController.text.trim().toLowerCase();
            if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
              setDialogState(() {
                otpFeedback = 'Enter a valid authorized contact email first.';
              });
              return;
            }
            setDialogState(() {
              otpSending = true;
              otpFeedback = null;
            });
            try {
              final res = await apiService.sendPharmacyOtp(email);
              setDialogState(() {
                otpSent = true;
                demoOtpCode = res['demo_code']?.toString();
                if (res['email_delivered'] == true) {
                  otpFeedback = '6-digit OTP code sent to $email.';
                } else if (demoOtpCode != null) {
                  otpFeedback =
                      'Verification OTP: $demoOtpCode (Test Demo Mode)';
                } else {
                  otpFeedback = 'Verification code dispatched to $email.';
                }
              });
            } catch (err) {
              setDialogState(() {
                otpFeedback = 'Failed to dispatch OTP: $err';
              });
            } finally {
              setDialogState(() {
                otpSending = false;
              });
            }
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.verified_user_outlined, color: AppTheme.deepTeal),
                SizedBox(width: 8),
                Text('Verify & Onboard New Pharmacy'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Verify a registered pharmacy profile by sending an OTP to their registered authorized contact email. Once verified, the pharmacy account is linked and orders dispatched to them will appear on their dashboard.',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Pharmacy Name',
                          hintText: 'e.g. CityRx Community Pharmacy',
                          prefixIcon: Icon(Icons.local_pharmacy_outlined),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Enter pharmacy name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: licenseController,
                        decoration: const InputDecoration(
                          labelText: 'Regulatory Drug License Number',
                          hintText: 'e.g. RX-2024-9981 or PHARM-DL-4482',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Enter regulatory license number';
                          }
                          if (val.trim().length < 5) {
                            return 'License number must be at least 5 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'Official Delivery Address',
                          hintText:
                              'e.g. 742 Evergreen Terrace, Medical District',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Enter verified physical address'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Authorized Contact Email',
                                hintText: 'e.g. pharmacy@pharmatrace.dev',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter authorized contact email';
                                }
                                if (!val.contains('@') || !val.contains('.')) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                              ),
                              onPressed: otpSending ? null : sendOtp,
                              icon: otpSending
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Icon(otpSent ? Icons.refresh : Icons.send,
                                      size: 16),
                              label: Text(otpSent ? 'Resend' : 'Send OTP'),
                            ),
                          ),
                        ],
                      ),
                      if (otpFeedback != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 16, color: AppTheme.navy),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  otpFeedback!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.navy),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (otpSent) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Enter 6-Digit Email OTP',
                            hintText: 'e.g. 123456',
                            prefixIcon: Icon(Icons.security),
                            helperText:
                                'Verification code sent to pharmacy registered email',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().length != 6) {
                              return 'Enter 6-digit verification code';
                            }
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, true);
                  }
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Verify & Confirm Pharmacy'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      try {
        final newPharmacy = await apiService.onboardPharmacy(
          name: nameController.text.trim(),
          licenseNumber: licenseController.text.trim().toUpperCase(),
          address: addressController.text.trim(),
          contactEmail: emailController.text.trim().toLowerCase(),
          otpCode: otpController.text.trim().isNotEmpty
              ? otpController.text.trim()
              : null,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pharmacy "${newPharmacy['name']}" verified successfully via OTP. Account linked and ready for delivery updates!',
            ),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        await _load();
      } catch (e) {
        String errDetail =
            'Verification failed. Please check the entered details or OTP code.';
        if (e is DioException) {
          if (e.response?.data is Map && e.response?.data['detail'] != null) {
            errDetail = e.response!.data['detail'].toString();
          } else if (e.type == DioExceptionType.connectionError) {
            errDetail =
                'Network connection failed. Verify server connectivity.';
          }
        }
        if (mounted) _showError('Pharmacy verification: $errDetail');
      }
    }
    nameController.dispose();
    licenseController.dispose();
    addressController.dispose();
    emailController.dispose();
    otpController.dispose();
  }

  Widget _buildPharmacyDirectoryTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verified Pharmacy Directory',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.navy),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_pharmacies.length} licensed pharmacies authorized for medicine supply and transfer.',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _onboardPharmacyDialog,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Verify New Pharmacy'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_pharmacies.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                    'No verified pharmacies registered. Click "Verify New Pharmacy" above to add one.'),
              ),
            ),
          )
        else
          ..._pharmacies.map((pharmacy) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2F1),
                    child: Icon(Icons.local_pharmacy_outlined,
                        color: AppTheme.deepTeal),
                  ),
                  title: Text(
                    pharmacy['name'].toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Contact: ${pharmacy['contact_email']}\n'
                    'Delivery address: ${pharmacy['address']}\n'
                    'License: ${pharmacy['license_number']} · State Board Verified',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Chip(
                        label: Text('Verified Partner',
                            style: TextStyle(color: AppTheme.successGreen)),
                        avatar: Icon(Icons.verified,
                            size: 18, color: AppTheme.successGreen),
                        backgroundColor: Color(0xFFE8F5E9),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Dispatch order to this pharmacy',
                        icon: const Icon(Icons.send_outlined,
                            color: AppTheme.deepTeal),
                        onPressed: () {
                          _tabController.animateTo(
                              6); // Navigate to Create Pharmacy Order
                        },
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildPharmacyOrderTab() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_shopping_cart_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Create pharmacy order',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${_pharmacies.length} verified pharmacies · '
                '${_availablePackages.length} available serialized packages',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _createPharmacyOrder,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Select pharmacy, batch and quantity'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDispatchTab() {
    final outgoingPending = _outgoingShipments.where((shipment) =>
        shipment['receiver_org_type'] == 'pharmacy' &&
        ['dispatched', 'in_transit'].contains(shipment['status']));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Dispatch to Pharmacy',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _createPharmacyOrder,
              icon: const Icon(Icons.add),
              label: const Text('New pharmacy dispatch'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (outgoingPending.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No pharmacy shipments are currently in transit.'),
            ),
          )
        else
          ...outgoingPending.map((shipment) => _shipmentCard(shipment)),
      ],
    );
  }

  Widget _buildPendingPharmacyReceiptsTab() {
    final pending = _outgoingShipments.where((shipment) =>
        shipment['receiver_org_type'] == 'pharmacy' &&
        ['dispatched', 'in_transit'].contains(shipment['status']));
    final records = pending.toList();
    if (records.isEmpty) {
      return const Center(
        child: Text('No pharmacy shipments are awaiting confirmation.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: records.map((shipment) => _shipmentCard(shipment)).toList(),
    );
  }

  Widget _buildTransferHistoryTab() {
    if (_shipments.isEmpty) {
      return const Center(child: Text('No custody transfers are recorded.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _shipments
          .map((shipment) => _shipmentCard(shipment, showItems: true))
          .toList(),
    );
  }

  Widget _buildRecallTab() {
    final affectedPackages = _inventory.where((item) =>
        ['recalled', 'quarantined'].contains(item['status']) ||
        item['batch_status'] == 'recalled');
    final packages = affectedPackages.toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Affected packages stay blocked from further transfer. Follow the manufacturer recall instructions.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        if (packages.isEmpty && _recalls.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_outlined),
              title:
                  Text('No recalled or quarantined stock is in your custody.'),
            ),
          ),
        ...packages.map((item) => Card(
              color: AppTheme.errorRed.withValues(alpha: 0.06),
              child: ListTile(
                leading: const Icon(Icons.gpp_bad, color: AppTheme.errorRed),
                title:
                    Text('${item['product_name']} · ${item['batch_number']}'),
                subtitle: Text(
                  '${item['package_serial_id']} · Current status ${item['status']}',
                ),
                trailing: const Chip(label: Text('Transfer blocked')),
              ),
            )),
        ..._recalls.map((recall) => Card(
              child: ListTile(
                leading:
                    const Icon(Icons.warning_amber, color: AppTheme.errorRed),
                title: Text(
                  '${recall['product_name']} · Batch ${recall['batch_number']}',
                ),
                subtitle: Text(
                  '${recall['severity']} · ${recall['recall_reason']}',
                ),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => RecallImpactSimulatorView.show(
                        context,
                        batchId: recall['batch_id'].toString(),
                      ),
                      icon: const Icon(Icons.account_tree_outlined, size: 16),
                      label: const Text('Simulator'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showQuarantineAcknowledgeDialog(recall),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorRed,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.gpp_bad, size: 16),
                      label: const Text('Quarantine'),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Future<void> _showQuarantineAcknowledgeDialog(dynamic recall) async {
    final qtyController = TextEditingController(text: '0');
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text('Acknowledge & Quarantine · Batch ${recall['batch_number']}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Product: ${recall['product_name']}'),
              Text('Reason: ${recall['recall_reason']}'),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quarantined Quantity (units in custody)',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Quarantine / response notes',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Quarantine'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final qty = int.tryParse(qtyController.text.trim()) ?? 0;
      final notes = notesController.text.trim();
      try {
        await apiService.acknowledgeRecall(
          recall['id'].toString(),
          quarantinedQuantity: qty,
          responseNotes:
              notes.isEmpty ? 'Stock quarantined in distributor vault' : notes,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Recall quarantine acknowledgement recorded on blockchain.'),
              backgroundColor: AppTheme.successGreen,
            ),
          );
          await _load();
        }
      } catch (e) {
        if (mounted) _showError('Failed to acknowledge recall: $e');
      }
    }
    qtyController.dispose();
    notesController.dispose();
  }

  Widget _buildSuspiciousReportsTab() {
    if (_alerts.isEmpty) {
      return const Center(
          child: Text(
              'No suspicious scan reports are linked to your organization.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _alerts
          .map((alert) => Card(
                child: ListTile(
                  leading: Icon(
                    Icons.security,
                    color: alert['severity'] == 'critical' ||
                            alert['severity'] == 'high'
                        ? AppTheme.errorRed
                        : AppTheme.warningAmber,
                  ),
                  title: Text(
                    '${alert['alert_type']} · ${alert['severity']}',
                  ),
                  subtitle: Text(
                    '${alert['reason']}\nReview status: ${alert['review_status']} · ${alert['created_at']}',
                  ),
                  isThreeLine: true,
                ),
              ))
          .toList(),
    );
  }

  Widget _buildNotificationsTab() {
    if (_notifications.isEmpty) {
      return const Center(
          child:
              Text('No shipment, dispute, expiry, or recall notifications.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _notifications.map(_notificationTile).toList(),
    );
  }

  Widget _notificationTile(dynamic notification) {
    final icon = switch (notification['type']) {
      'incoming_shipment' => Icons.move_to_inbox,
      'dispute' => Icons.gavel_outlined,
      'suspicious_scan' => Icons.security,
      'expiry' => Icons.event_busy,
      'recall' => Icons.warning_amber,
      _ => Icons.notifications_outlined,
    };
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(notification['title'].toString()),
        subtitle: Text(
          '${notification['message']}\n${notification['created_at'] ?? ''}',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildBatchVerificationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Scan or enter a package code to verify registered identity, custody and status.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: _scanForVerification,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Scan QR code'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _verificationController,
          decoration: const InputDecoration(
            labelText: 'Package QR URL or serial ID',
            prefixIcon: Icon(Icons.qr_code),
          ),
          onSubmitted: _verifyPackage,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _verifyPackage(_verificationController.text),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Verify batch package'),
          ),
        ),
        if (_verificationResult != null) ...[
          const SizedBox(height: 16),
          PackageVerificationCard(result: _verificationResult!),
        ],
      ],
    );
  }

  Widget _shipmentCard(
    dynamic shipment, {
    Widget? action,
    bool showItems = false,
  }) {
    final receiverName =
        shipment['receiver_organization_name'] ?? 'Receiving organization';
    final senderName =
        shipment['sender_organization_name'] ?? 'Sending organization';
    final items = shipment['items'] as List<dynamic>? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.local_shipping_outlined),
        title: Text(
          shipment['shipment_reference'].toString(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '$senderName → $receiverName · '
          '${shipment['declared_quantity']} units · ${shipment['status']}',
        ),
        trailing: Chip(label: Text(shipment['status'].toString())),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Dispatched: ${shipment['dispatch_timestamp'] ?? 'Not recorded'} · '
              'Received: ${shipment['receipt_timestamp'] ?? 'Pending'} · '
              'Quantity accepted: ${shipment['received_quantity'] ?? 'Pending'}',
            ),
          ),
          if (shipment['notes'] != null &&
              shipment['notes'].toString().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Notes: ${shipment['notes']}'),
            ),
          if (showItems)
            ...items.map((item) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(
                    '${item['product_name']} · Batch ${item['batch_number']}',
                  ),
                  subtitle: Text(
                    '${item['package_serial_id']} · ${item['status']}',
                  ),
                )),
          if (shipment['blockchain_tx_ref'] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                'Ledger transaction: ${shipment['blockchain_tx_ref']}',
              ),
            ),
          if (action != null) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    const tabs = [
      Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
      Tab(text: 'Incoming Shipments', icon: Icon(Icons.move_to_inbox)),
      Tab(text: 'Scan & Receive', icon: Icon(Icons.qr_code_scanner)),
      Tab(text: 'Receipt Confirmation', icon: Icon(Icons.fact_check_outlined)),
      Tab(text: 'My Inventory', icon: Icon(Icons.inventory_2_outlined)),
      Tab(
          text: 'Pharmacy Directory',
          icon: Icon(Icons.local_pharmacy_outlined)),
      Tab(text: 'Create Pharmacy Order', icon: Icon(Icons.add_shopping_cart)),
      Tab(text: 'Dispatch to Pharmacy', icon: Icon(Icons.outbox_outlined)),
      Tab(text: 'Pending Pharmacy Receipts', icon: Icon(Icons.hourglass_top)),
      Tab(text: 'Transfer History', icon: Icon(Icons.history)),
      Tab(text: 'Batch Verification', icon: Icon(Icons.verified_outlined)),
      Tab(text: 'Recall & Quarantine', icon: Icon(Icons.gpp_bad_outlined)),
      Tab(text: 'Suspicious Scan Reports', icon: Icon(Icons.security_outlined)),
      Tab(text: 'Notifications', icon: Icon(Icons.notifications_outlined)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Distributor dashboard',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navy,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => OfflineSyncPanel.show(context, _load),
                icon: const Icon(Icons.sync_problem_outlined),
                label: const Text('Offline Sync'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: tabs,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildIncomingTab(),
              _buildScanAndReceiveTab(),
              _buildReceiptConfirmationTab(),
              _buildInventoryTab(),
              _buildPharmacyDirectoryTab(),
              _buildPharmacyOrderTab(),
              _buildDispatchTab(),
              _buildPendingPharmacyReceiptsTab(),
              _buildTransferHistoryTab(),
              _buildBatchVerificationTab(),
              _buildRecallTab(),
              _buildSuspiciousReportsTab(),
              _buildNotificationsTab(),
            ],
          ),
        ),
      ],
    );
  }
}
