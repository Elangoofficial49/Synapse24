import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/api_service.dart';
import '../services/offline_receipt_service.dart';
import '../widgets/dispute_investigation_dialog.dart';
import '../widgets/offline_sync_panel.dart';
import '../widgets/package_verification_card.dart';
import '../widgets/qr_scanner_dialog.dart';
import '../widgets/recall_impact_simulator_view.dart';

class PharmacyTools extends StatefulWidget {
  final int initialTabIndex;

  const PharmacyTools({super.key, this.initialTabIndex = 0});

  @override
  State<PharmacyTools> createState() => _PharmacyToolsState();
}

class _PharmacyToolsState extends State<PharmacyTools>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _organizationId;
  List<dynamic> _shipments = [];
  List<dynamic> _incomingShipments = [];
  List<dynamic> _inventory = [];
  List<dynamic> _recalls = [];
  List<dynamic> _alerts = [];
  List<dynamic> _disputes = [];
  List<dynamic> _notifications = [];
  final List<Map<String, dynamic>> _dispensingLogs = [];
  Map<String, dynamic>? _verificationResult;
  final TextEditingController _verificationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 13,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 12),
    );
    _load();
  }

  @override
  void didUpdateWidget(PharmacyTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      final target = widget.initialTabIndex.clamp(0, 12);
      if (_tabController.index != target) {
        _tabController.animateTo(target);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _verificationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dashboard = await apiService.getPharmacyDashboard();
      if (!mounted) return;
      final rawShipments =
          List<dynamic>.from(dashboard['shipments'] as List? ?? []);
      final rawIncoming =
          List<dynamic>.from(dashboard['incoming_shipments'] as List? ?? []);
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
      rawInventory.sort(compareDesc);
      rawRecalls.sort(compareDesc);
      rawAlerts.sort(compareDesc);
      rawDisputes.sort(compareDesc);
      rawNotifications.sort(compareDesc);

      setState(() {
        _organizationId = dashboard['organization_id']?.toString();
        _shipments = rawShipments;
        _incomingShipments = rawIncoming;
        _inventory = rawInventory;
        _recalls = rawRecalls;
        _alerts = rawAlerts;
        _disputes = rawDisputes;
        _notifications = rawNotifications;
      });
    } catch (error) {
      if (mounted) _showError('Unable to load pharmacy dashboard: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorRed),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.successGreen),
    );
  }

  Future<void> _verifyPackage(String rawData) async {
    final serial = rawData.trim();
    if (serial.isEmpty) return;
    setState(() {
      _loading = true;
      _verificationController.text = serial;
    });
    try {
      final result = await apiService.verifyPackage(serial);
      if (!mounted) return;
      setState(() => _verificationResult = result);
    } catch (error) {
      if (mounted) _showError('Verification failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Confirm Receipt Dialog ---
  Future<void> _scanReceiptPackage(
    String rawData,
    Set<String> expectedSerials,
    Set<String> scannedSerials,
    void Function(void Function()) setDialogState,
  ) async {
    final serial = rawData.trim();
    if (serial.isEmpty) return;
    if (!expectedSerials.contains(serial)) {
      _showError('Package $serial does not belong to this incoming delivery.');
      return;
    }
    try {
      final result = await apiService.verifyPackage(serial);
      if (!mounted) return;
      if (result['is_valid'] != true) {
        _showError('Invalid package signature or unregistered serial code.');
        return;
      }
      if (result['is_recalled'] == true ||
          result['is_expired'] == true ||
          result['status'] == 'quarantined') {
        _showError(
            'This package is expired, recalled, or quarantined and cannot be accepted.');
        return;
      }
      if (scannedSerials.contains(serial)) {
        _showError('Package $serial was already scanned.');
        return;
      }
      setDialogState(() => scannedSerials.add(serial));
    } catch (error) {
      if (mounted) _showError('Could not verify package: $error');
    }
  }

  Future<void> _confirmDeliveryReceipt(dynamic shipment) async {
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
          title: Text('Confirm Receipt · ${shipment['shipment_reference']}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scan manufacturer QR codes for packages delivered by ${shipment['sender_organization_name'] ?? 'distributor'}. '
                  '${scannedSerials.length} of ${shipment['declared_quantity']} verified.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
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
                  label: const Text('Scan Package QR'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: serialController,
                        enabled: !noPackagesReceived,
                        decoration: const InputDecoration(
                            labelText: 'Or enter serial ID'),
                        onSubmitted: (value) {
                          if (value.trim().isEmpty) return;
                          _scanReceiptPackage(value, expectedSerials,
                              scannedSerials, setDialogState);
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
                              _scanReceiptPackage(value, expectedSerials,
                                  scannedSerials, setDialogState);
                              serialController.clear();
                            },
                      icon: const Icon(Icons.check_circle_outline),
                    ),
                  ],
                ),
                if (scannedSerials.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: ListView(
                      shrinkWrap: true,
                      children: scannedSerials
                          .map((serial) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.verified,
                                    color: AppTheme.successGreen),
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
                  title: const Text(
                      'No packages were received / shipment rejected'),
                  onChanged: (checked) => setDialogState(() {
                    noPackagesReceived = checked ?? false;
                    if (noPackagesReceived) scannedSerials.clear();
                  }),
                ),
                if (noPackagesReceived ||
                    scannedSerials.length !=
                        (shipment['declared_quantity'] as num).toInt())
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                        labelText: 'Discrepancy / rejection justification'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: scannedSerials.isEmpty && !noPackagesReceived
                  ? null
                  : () async {
                      final qty =
                          noPackagesReceived ? 0 : scannedSerials.length;
                      final declared =
                          (shipment['declared_quantity'] as num).toInt();
                      final reason = reasonController.text.trim();
                      if (qty != declared && reason.isEmpty) {
                        _showError('A reason is required for any discrepancy.');
                        return;
                      }
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(dialogContext);
                      final receiptRecord =
                          await OfflineReceiptService.saveOfflineReceipt(
                        shipmentId: shipment['id'].toString(),
                        shipmentReference:
                            shipment['shipment_reference'].toString(),
                        actualQuantityReceived: qty,
                        declaredQuantity: declared,
                        notes: reason.isEmpty ? null : reason,
                        scannedPackageSerialIds: scannedSerials.toList(),
                      );
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Receipt queued offline [Key: ${receiptRecord['idempotency_key'].toString().substring(0, 8)}...]. Sync when reconnected.',
                          ),
                          backgroundColor: AppTheme.deepTeal,
                        ),
                      );
                    },
              icon: const Icon(Icons.cloud_off_outlined),
              label: const Text('Save Offline'),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = noPackagesReceived ? 0 : scannedSerials.length;
                final declared = (shipment['declared_quantity'] as num).toInt();
                final reason = reasonController.text.trim();
                if (qty != declared && reason.isEmpty) {
                  _showError('A reason is required for any discrepancy.');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  (
                    scannedSerials.toList(growable: false),
                    reason.isEmpty ? null : reason
                  ),
                );
              },
              child: const Text('Submit Confirmation'),
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
      _showSuccess(
        scanned.length == declared
            ? 'Receipt confirmed on the blockchain ledger (${result['tx_reference'] ?? 'confirmed'}).'
            : 'Discrepancy recorded and flagged on ledger (${result['tx_reference'] ?? 'logged'}).',
      );
      await _load();
      if (mounted) {
        _tabController.animateTo(4);
      }
    } catch (error) {
      if (mounted) _showError('Could not confirm delivery: $error');
    }
  }

  // --- Dispense to Patient Dialog ---
  Future<void> _recordDispenseDialog(Map<String, dynamic> package) async {
    final patientController = TextEditingController();
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dispense · ${package['product_name']}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Serial: ${package['package_serial_id']}'),
              Text('Batch: ${package['batch_number']}'),
              Text('Expiry: ${package['expiry_date']}'),
              const SizedBox(height: 16),
              TextField(
                controller: patientController,
                decoration: const InputDecoration(
                  labelText: 'Patient Reference / Prescription ID',
                  hintText: 'e.g. RX-2024-8842',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                    labelText: 'Dispensing Notes (Optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Dispensing'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      final res = await apiService.dispensePackage(
        packageSerialId: package['package_serial_id'].toString(),
        patientReference: patientController.text.trim().isEmpty
            ? null
            : patientController.text.trim(),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );
      if (!mounted) return;
      _showSuccess(
          'Dispensing recorded. Package marked as dispensed on the ledger.');
      setState(() {
        _dispensingLogs.insert(0, {
          'package_serial_id': package['package_serial_id'],
          'product_name': package['product_name'],
          'batch_number': package['batch_number'],
          'dispensed_at':
              res['dispensed_at'] ?? DateTime.now().toIso8601String(),
          'notes': res['notes'] ?? '',
        });
      });
      await _load();
      if (mounted) {
        _tabController.animateTo(8);
      }
    } catch (error) {
      if (mounted) _showError('Failed to record dispensing: $error');
    } finally {
      patientController.dispose();
      notesController.dispose();
    }
  }

  // --- Report Suspicious Product Dialog ---
  Future<void> _reportSuspiciousProductDialog() async {
    final serialController = TextEditingController();
    final reasonController = TextEditingController();
    String severity = 'high';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Suspicious Product'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Report invalid QR codes, unexpected batch details, duplicate scans, or suspected tampering directly to regulators & manufacturer.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: serialController,
                  decoration: const InputDecoration(
                      labelText: 'Package Serial ID (if identifiable)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration:
                      const InputDecoration(labelText: 'Severity Level'),
                  items: const [
                    DropdownMenuItem(
                        value: 'low',
                        child: Text('Low - Packaging defect / minor issue')),
                    DropdownMenuItem(
                        value: 'medium',
                        child: Text('Medium - Label discrepancy')),
                    DropdownMenuItem(
                        value: 'high',
                        child: Text('High - Duplicate scan / Unknown serial')),
                    DropdownMenuItem(
                        value: 'critical',
                        child: Text(
                            'Critical - Confirmed Counterfeit / Tampering')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => severity = v ?? 'high'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Detailed Explanation of Suspicion'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit Alert Report'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (reasonController.text.trim().isEmpty) {
      _showError('Please provide a reason for the report.');
      return;
    }

    try {
      await apiService.reportSuspiciousProduct(
        packageSerialId: serialController.text.trim(),
        reason: reasonController.text.trim(),
        severity: severity,
      );
      if (!mounted) return;
      _showSuccess(
          'Suspicious activity alert logged and broadcasted to regulators & supply chain network.');
      await _load();
    } catch (error) {
      if (mounted) _showError('Failed to submit report: $error');
    } finally {
      serialController.dispose();
      reasonController.dispose();
    }
  }

  // ==========================================
  // TAB 0: OVERVIEW
  // ==========================================
  Widget _buildOverviewTab() {
    final available = _inventory
        .where(
            (p) => p['status'] == 'received' && p['batch_status'] != 'recalled')
        .toList();
    final lowStockCount = available.length < 5 ? available.length : 0;
    final expiryAlertCount = _inventory.where((p) {
      if (p['expiry_date'] == null) return false;
      final exp = DateTime.tryParse(p['expiry_date'].toString());
      if (exp == null) return false;
      return exp.isBefore(DateTime.now().add(const Duration(days: 30)));
    }).length;
    final recallCount = _recalls.where((r) => r['status'] == 'active').length;

    final metrics = [
      (
        'Incoming Deliveries',
        '${_incomingShipments.length}',
        Icons.local_shipping_outlined,
        AppTheme.navy
      ),
      (
        'Current Stock (Pkgs)',
        '${available.length}',
        Icons.inventory_2_outlined,
        AppTheme.deepTeal
      ),
      (
        'Low-Stock Alerts',
        '$lowStockCount',
        Icons.trending_down,
        AppTheme.warningAmber
      ),
      (
        'Expiry Warnings',
        '$expiryAlertCount',
        Icons.event_busy,
        AppTheme.warningAmber
      ),
      (
        'Recalled Products',
        '$recallCount',
        Icons.warning_amber_rounded,
        AppTheme.errorRed
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Pharmacy Overview',
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.navy),
        ),
        const SizedBox(height: 8),
        const Text(
            'Real-time supply chain monitoring, medicine inventory, and patient safety alerts.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map((m) => SizedBox(
                    width: 210,
                    child: Card(
                      child: ListTile(
                        leading: Icon(m.$3, color: m.$4),
                        title: Text(m.$2,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: m.$4)),
                        subtitle: Text(m.$1),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text('Recent Safety Alerts & Deliveries',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_notifications.isEmpty)
          const Card(
              child: ListTile(
                  title: Text('No current alerts or delivery notifications.')))
        else
          ..._notifications.take(5).map(_notificationTile),
      ],
    );
  }

  // ==========================================
  // TAB 1: INCOMING DELIVERIES
  // ==========================================
  Widget _buildIncomingDeliveriesTab() {
    if (_incomingShipments.isEmpty) {
      return const Center(
          child: Text('No incoming deliveries dispatched to this pharmacy.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _incomingShipments
          .map((s) => _shipmentCard(s,
              action: ElevatedButton.icon(
                onPressed: () => _confirmDeliveryReceipt(s),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Confirm Receipt'),
              )))
          .toList(),
    );
  }

  // ==========================================
  // TAB 2: SCAN & VERIFY
  // ==========================================
  Widget _buildScanVerifyTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Scan & Verify Batch / Package',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            'Scan a batch QR code and check the registered record, current status, and authorized custody chain.'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _verificationController,
                decoration: const InputDecoration(
                    labelText: 'Enter Package Serial ID or Scan QR Code',
                    prefixIcon: Icon(Icons.qr_code_scanner)),
                onSubmitted: _verifyPackage,
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () => _verifyPackage(_verificationController.text),
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Verify'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  QrScannerDialog.show(context, onScanned: _verifyPackage),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Camera'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_verificationResult != null)
          PackageVerificationCard(result: _verificationResult!)
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                  child: Text(
                      'Scan or enter a package serial ID to inspect on-chain custody and batch pedigree.')),
            ),
          ),
      ],
    );
  }

  // ==========================================
  // TAB 3: CONFIRM RECEIPT
  // ==========================================
  Widget _buildConfirmReceiptTab() {
    final pending = _incomingShipments;
    final received = _shipments
        .where((s) =>
            s['receiver_org_id'] == _organizationId &&
            ['received', 'partially_received', 'disputed']
                .contains(s['status']))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Confirm Incoming Deliveries',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            'Independently scan received packages to verify quantities against distributor manifests or report discrepancies.'),
        const SizedBox(height: 16),
        if (pending.isEmpty)
          const Card(
              child: ListTile(
                  title: Text(
                      'No pending deliveries awaiting receipt confirmation.')))
        else
          ...pending.map((s) => _shipmentCard(s,
              action: ElevatedButton.icon(
                onPressed: () => _confirmDeliveryReceipt(s),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Verify & Confirm Receipt'),
              ))),
        const SizedBox(height: 24),
        const Text('Receipt Confirmation History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (received.isEmpty)
          const Card(
              child: ListTile(title: Text('No past receipt records found.')))
        else
          ...received.map((s) => _shipmentCard(s)),
        if (_disputes.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Receipt Quantity Disputes',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.warningAmber)),
          const SizedBox(height: 12),
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

  // ==========================================
  // TAB 4: MEDICINE INVENTORY
  // ==========================================
  Widget _buildMedicineInventoryTab() {
    final activeStock =
        _inventory.where((p) => p['status'] == 'received').toList();
    if (activeStock.isEmpty) {
      return const Center(
          child: Text(
              'No medicine inventory currently in stock. Receive deliveries to populate.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Available Stock (${activeStock.length} items)',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navy)),
            Text(
                '${activeStock.map((p) => p['batch_number']).toSet().length} Batches',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppTheme.deepTeal)),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Serial ID')),
              DataColumn(label: Text('Batch Number')),
              DataColumn(label: Text('Expiry Date')),
              DataColumn(label: Text('Manufacturer')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: activeStock.map((item) {
              final isRecalled = item['batch_status'] == 'recalled';
              return DataRow(cells: [
                DataCell(Text(item['product_name'] ?? '-')),
                DataCell(Text(item['package_serial_id'] ?? '-')),
                DataCell(Text(item['batch_number'] ?? '-')),
                DataCell(Text(item['expiry_date'] ?? '-')),
                DataCell(Text(item['manufacturer_name'] ?? '-')),
                DataCell(
                  Chip(
                    label: Text(isRecalled
                        ? 'RECALLED'
                        : item['status']?.toString().toUpperCase() ?? ''),
                    backgroundColor: isRecalled
                        ? AppTheme.errorRed.withValues(alpha: 0.15)
                        : AppTheme.successGreen.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                        color: isRecalled
                            ? AppTheme.errorRed
                            : AppTheme.successGreen,
                        fontSize: 11),
                  ),
                ),
                DataCell(
                  ElevatedButton(
                    onPressed: isRecalled
                        ? null
                        : () => _recordDispenseDialog(
                            Map<String, dynamic>.from(item as Map)),
                    child: const Text('Dispense'),
                  ),
                ),
              ]);
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 5: BATCH DETAILS
  // ==========================================
  Widget _buildBatchDetailsTab() {
    final batches = <String, Map<String, dynamic>>{};
    for (final item in _inventory) {
      final bn = item['batch_number']?.toString();
      if (bn != null && !batches.containsKey(bn)) {
        batches[bn] = {
          'batch_number': bn,
          'product_name': item['product_name'],
          'manufacturer_name': item['manufacturer_name'],
          'manufacturing_date': item['manufacturing_date'],
          'expiry_date': item['expiry_date'],
          'batch_status': item['batch_status'],
          'count': 1,
        };
      } else if (bn != null) {
        batches[bn]!['count'] = (batches[bn]!['count'] as int) + 1;
      }
    }

    if (batches.isEmpty) {
      return const Center(
          child: Text('No batches registered in pharmacy storage.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Batch Pedigree & Supply-Chain Pedigree',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            'Inspect manufacturer, manufacturing dates, expiry dates, and authorized supply-chain provenance.'),
        const SizedBox(height: 16),
        ...batches.values.map((b) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.layers_outlined,
                    color: AppTheme.deepTeal, size: 36),
                title: Text('${b['product_name']} · Batch ${b['batch_number']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'Manufacturer: ${b['manufacturer_name'] ?? 'Authorized Pharma'}\nMfg Date: ${b['manufacturing_date'] ?? 'N/A'} | Expiry: ${b['expiry_date'] ?? 'N/A'} | In Stock: ${b['count']} packages'),
                trailing: Chip(
                  label: Text(
                      b['batch_status']?.toString().toUpperCase() ?? 'ACTIVE'),
                  backgroundColor: b['batch_status'] == 'recalled'
                      ? AppTheme.errorRed.withValues(alpha: 0.15)
                      : AppTheme.successGreen.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                      color: b['batch_status'] == 'recalled'
                          ? AppTheme.errorRed
                          : AppTheme.successGreen),
                ),
              ),
            )),
      ],
    );
  }

  // ==========================================
  // TAB 6: EXPIRY MANAGEMENT
  // ==========================================
  Widget _buildExpiryManagementTab() {
    final now = DateTime.now();
    final expired = <dynamic>[];
    final soonExpiring = <dynamic>[];

    for (final item in _inventory) {
      final expStr = item['expiry_date']?.toString();
      if (expStr == null) continue;
      final exp = DateTime.tryParse(expStr);
      if (exp == null) continue;
      if (exp.isBefore(now)) {
        expired.add(item);
      } else if (exp.isBefore(now.add(const Duration(days: 60)))) {
        soonExpiring.add(item);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Expiry Date Tracking & Management',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            'Flag expired or soon-to-expire stock to prevent accidental patient dispensing.'),
        const SizedBox(height: 16),
        Card(
          color: expired.isNotEmpty
              ? AppTheme.errorRed.withValues(alpha: 0.05)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dangerous_outlined,
                        color: expired.isNotEmpty
                            ? AppTheme.errorRed
                            : AppTheme.successGreen),
                    const SizedBox(width: 8),
                    Text('Expired Packages (${expired.length})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (expired.isEmpty)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('No expired stock in storage.'))
                else
                  ...expired.map((p) => ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.block, color: AppTheme.errorRed),
                        title: Text(
                            '${p['product_name']} (Serial: ${p['package_serial_id']})'),
                        subtitle: Text(
                            'Batch: ${p['batch_number']} · Expired on: ${p['expiry_date']}'),
                      )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.alarm,
                        color: soonExpiring.isNotEmpty
                            ? AppTheme.warningAmber
                            : AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text('Expiring Within 60 Days (${soonExpiring.length})',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (soonExpiring.isEmpty)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('No stock approaching expiration.'))
                else
                  ...soonExpiring.map((p) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber,
                            color: AppTheme.warningAmber),
                        title: Text(
                            '${p['product_name']} (Serial: ${p['package_serial_id']})'),
                        subtitle: Text(
                            'Batch: ${p['batch_number']} · Expiry: ${p['expiry_date']}'),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 7: RECALL ALERTS
  // ==========================================
  Widget _buildRecallAlertsTab() {
    if (_recalls.isEmpty) {
      return const Center(
          child: Text(
              'No active product recalls affecting your current inventory.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Manufacturer & Regulatory Recall Directives',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.errorRed)),
        const SizedBox(height: 8),
        const Text(
            'Quarantine affected inventory immediately and do not dispense.'),
        const SizedBox(height: 16),
        ..._recalls.map((r) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: AppTheme.errorRed.withValues(alpha: 0.05),
              child: ListTile(
                leading: const Icon(Icons.gpp_bad_outlined,
                    color: AppTheme.errorRed, size: 36),
                title: Text('${r['product_name']} · Batch ${r['batch_number']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppTheme.errorRed)),
                subtitle: Text(
                    'Reason: ${r['recall_reason']}\nSeverity: ${r['severity']?.toString().toUpperCase()} · Status: ${r['status']?.toString().toUpperCase()}'),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => RecallImpactSimulatorView.show(
                        context,
                        batchId: r['batch_id'].toString(),
                      ),
                      icon: const Icon(Icons.account_tree_outlined, size: 16),
                      label: const Text('Simulator'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorRed,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _showPharmacyQuarantineDialog(r),
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

  Future<void> _showPharmacyQuarantineDialog(dynamic recall) async {
    final qtyController = TextEditingController(text: '0');
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pharmacy Quarantine · Batch ${recall['batch_number']}'),
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
                  labelText: 'Quarantined Pharmacy Stock (units locked)',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Quarantine procedure notes',
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
            child: const Text('Confirm Quarantine & Lockdown'),
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
          responseNotes: notes.isEmpty
              ? 'Quarantined in pharmacy biohazard storage'
              : notes,
        );
        if (mounted) {
          _showSuccess(
              'Recall quarantine confirmation recorded on blockchain.');
          await _load();
        }
      } catch (e) {
        if (mounted) _showError('Failed to acknowledge recall: $e');
      }
    }
    qtyController.dispose();
    notesController.dispose();
  }

  // ==========================================
  // TAB 8: DISPENSING RECORDS
  // ==========================================
  Widget _buildDispensingRecordsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Patient Dispensing Records',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navy)),
            ElevatedButton.icon(
              onPressed: () {
                final activeStock = _inventory
                    .where((p) =>
                        p['status'] == 'received' &&
                        p['batch_status'] != 'recalled')
                    .toList();
                if (activeStock.isEmpty) {
                  _showError('No available inventory to dispense.');
                  return;
                }
                _recordDispenseDialog(
                    Map<String, dynamic>.from(activeStock.first as Map));
              },
              icon: const Icon(Icons.medication_outlined),
              label: const Text('Dispense Package'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_dispensingLogs.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                  child: Text(
                      'No dispensing events recorded in this session. Dispense packages from Medicine Inventory.')),
            ),
          )
        else
          ..._dispensingLogs.map((log) => Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle,
                      color: AppTheme.successGreen),
                  title: Text(
                      '${log['product_name']} (Serial: ${log['package_serial_id']})'),
                  subtitle: Text(
                      'Batch: ${log['batch_number']} | Time: ${log['dispensed_at']}\n${log['notes']}'),
                ),
              )),
      ],
    );
  }

  // ==========================================
  // TAB 9: SUSPICIOUS PRODUCT REPORT
  // ==========================================
  Widget _buildSuspiciousProductReportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Suspicious Product Reports',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navy)),
            ElevatedButton.icon(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
              onPressed: _reportSuspiciousProductDialog,
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('Submit Report'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
            'Report counterfeit suspicions, tampering, duplicate QR scans, or invalid signatures.'),
        const SizedBox(height: 16),
        if (_alerts.isEmpty)
          const Card(
              child: ListTile(
                  title: Text('No suspicious reports filed by this pharmacy.')))
        else
          ..._alerts.map((a) => Card(
                child: ListTile(
                  leading: const Icon(Icons.warning, color: AppTheme.errorRed),
                  title: Text(a['reason'] ?? 'Suspicious Activity Detected'),
                  subtitle: Text(
                      'Severity: ${a['severity']?.toString().toUpperCase()} · Status: ${a['review_status']?.toString().toUpperCase()} · Logged: ${a['created_at']}'),
                ),
              )),
      ],
    );
  }

  // ==========================================
  // TAB 10: SUPPLIER HISTORY
  // ==========================================
  Widget _buildSupplierHistoryTab() {
    final distributors = <String, Map<String, dynamic>>{};
    for (final s in _shipments) {
      final senderId = s['sender_org_id']?.toString();
      final senderName =
          s['sender_organization_name']?.toString() ?? 'Distributor Partner';
      if (senderId != null && !distributors.containsKey(senderId)) {
        distributors[senderId] = {
          'name': senderName,
          'deliveries_count': 1,
          'last_delivery': s['created_at'],
        };
      } else if (senderId != null) {
        distributors[senderId]!['deliveries_count'] =
            (distributors[senderId]!['deliveries_count'] as int) + 1;
      }
    }

    if (distributors.isEmpty) {
      return const Center(child: Text('No supplier history recorded yet.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Distributor Supplier Directory & History',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            'Review authorized wholesale distributors that have supplied deliveries to this pharmacy.'),
        const SizedBox(height: 16),
        ...distributors.values.map((d) => Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping,
                    color: AppTheme.deepTeal, size: 32),
                title: Text(d['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'Completed Deliveries: ${d['deliveries_count']} · Last Dispatched: ${d['last_delivery'] ?? 'Recent'}'),
              ),
            )),
      ],
    );
  }

  // ==========================================
  // TAB 11: AUDIT HISTORY
  // ==========================================
  Widget _buildAuditHistoryTab() {
    final allEvents = <Map<String, dynamic>>[];
    for (final s in _shipments) {
      allEvents.add({
        'title': 'Shipment ${s['shipment_reference']} · ${s['status']}',
        'subtitle':
            'From: ${s['sender_organization_name'] ?? 'Distributor'} | Declared: ${s['declared_quantity']} | Received: ${s['received_quantity'] ?? 0}',
        'date': s['created_at'],
        'icon': Icons.local_shipping,
      });
    }
    for (final d in _disputes) {
      allEvents.add({
        'title': 'Dispute: ${d['dispute_reason']}',
        'subtitle':
            'Status: ${d['status']} | Expected: ${d['expected_quantity']} vs Actual: ${d['actual_quantity']}',
        'date': d['created_at'],
        'icon': Icons.warning_amber_rounded,
      });
    }
    for (final a in _alerts) {
      allEvents.add({
        'title': 'Security Alert: ${a['reason']}',
        'subtitle':
            'Severity: ${a['severity']} · Status: ${a['review_status']}',
        'date': a['created_at'],
        'icon': Icons.security,
      });
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Pharmacy Supply-Chain Audit Log',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            'Immutable ledger audit trail of receipt confirmations, stock events, verifications, and discrepancy reports.'),
        const SizedBox(height: 16),
        if (allEvents.isEmpty)
          const Card(
              child: ListTile(title: Text('No audit events registered yet.')))
        else
          ...allEvents.map((e) => Card(
                child: ListTile(
                  leading: Icon(e['icon'] as IconData, color: AppTheme.navy),
                  title: Text(e['title'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${e['subtitle']}\nTimestamp: ${e['date']}'),
                ),
              )),
      ],
    );
  }

  // ==========================================
  // TAB 12: NOTIFICATIONS
  // ==========================================
  Widget _buildNotificationsTab() {
    if (_notifications.isEmpty) {
      return const Center(child: Text('No unread notifications.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Pharmacy Notifications',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            'Delivery updates, recalls, verification warnings, and expiry alerts.'),
        const SizedBox(height: 16),
        ..._notifications.map(_notificationTile),
      ],
    );
  }

  Widget _notificationTile(dynamic n) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          n['type'] == 'recall'
              ? Icons.warning_amber
              : (n['type'] == 'expiry' ? Icons.alarm : Icons.notifications),
          color: n['type'] == 'recall' ? AppTheme.errorRed : AppTheme.navy,
        ),
        title: Text(n['title']?.toString() ?? 'Notification',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(n['message']?.toString() ?? ''),
      ),
    );
  }

  Widget _shipmentCard(dynamic shipment, {Widget? action}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(shipment['shipment_reference']?.toString() ?? 'Shipment',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Chip(
                  label:
                      Text(shipment['status']?.toString().toUpperCase() ?? ''),
                  backgroundColor: shipment['status'] == 'delivered' ||
                          shipment['status'] == 'received'
                      ? AppTheme.successGreen.withValues(alpha: 0.15)
                      : AppTheme.navy.withValues(alpha: 0.1),
                  labelStyle: TextStyle(
                    color: shipment['status'] == 'delivered' ||
                            shipment['status'] == 'received'
                        ? AppTheme.successGreen
                        : AppTheme.navy,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                'Supplier: ${shipment['sender_organization_name'] ?? 'Distributor'}'),
            Text(
                'Declared Packages: ${shipment['declared_quantity']} | Received: ${shipment['received_quantity'] ?? 0}'),
            if (shipment['blockchain_tx_ref'] != null)
              Text('Ledger Tx: ${shipment['blockchain_tx_ref']}',
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.deepTeal)),
            if (action != null) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _shipments.isEmpty && _inventory.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    const tabs = [
      Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
      Tab(
          text: 'Incoming Deliveries',
          icon: Icon(Icons.local_shipping_outlined)),
      Tab(text: 'Scan & Verify', icon: Icon(Icons.qr_code_scanner)),
      Tab(text: 'Confirm Receipt', icon: Icon(Icons.fact_check_outlined)),
      Tab(text: 'Medicine Inventory', icon: Icon(Icons.inventory_2_outlined)),
      Tab(text: 'Batch Details', icon: Icon(Icons.layers_outlined)),
      Tab(text: 'Expiry Management', icon: Icon(Icons.event_busy_outlined)),
      Tab(text: 'Recall Alerts', icon: Icon(Icons.warning_amber_rounded)),
      Tab(text: 'Dispensing Records', icon: Icon(Icons.medication_outlined)),
      Tab(
          text: 'Suspicious Product Report',
          icon: Icon(Icons.report_problem_outlined)),
      Tab(text: 'Supplier History', icon: Icon(Icons.business_outlined)),
      Tab(text: 'Audit History', icon: Icon(Icons.history_edu_outlined)),
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
                  'Pharmacy Dashboard',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.navy),
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
              _buildIncomingDeliveriesTab(),
              _buildScanVerifyTab(),
              _buildConfirmReceiptTab(),
              _buildMedicineInventoryTab(),
              _buildBatchDetailsTab(),
              _buildExpiryManagementTab(),
              _buildRecallAlertsTab(),
              _buildDispensingRecordsTab(),
              _buildSuspiciousProductReportTab(),
              _buildSupplierHistoryTab(),
              _buildAuditHistoryTab(),
              _buildNotificationsTab(),
            ],
          ),
        ),
      ],
    );
  }
}
