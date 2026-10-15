import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/api_service.dart';
import '../widgets/package_verification_card.dart';
import '../widgets/qr_scanner_dialog.dart';

class DistributorTools extends StatefulWidget {
  final int initialTabIndex;

  const DistributorTools({super.key, this.initialTabIndex = 0});

  @override
  State<DistributorTools> createState() => _DistributorToolsState();
}

class _DistributorToolsState extends State<DistributorTools> {
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _verificationController.dispose();
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
      setState(() {
        _organizationId = dashboard['organization_id']?.toString();
        _summary = Map<String, dynamic>.from(dashboard['summary'] as Map);
        _shipments = dashboard['shipments'] as List<dynamic>;
        _incomingShipments = dashboard['incoming_shipments'] as List<dynamic>;
        _outgoingShipments = dashboard['outgoing_shipments'] as List<dynamic>;
        _inventory = dashboard['inventory'] as List<dynamic>;
        _recalls = dashboard['recalls'] as List<dynamic>;
        _alerts = dashboard['alerts'] as List<dynamic>;
        _disputes = dashboard['disputes'] as List<dynamic>;
        _notifications = dashboard['notifications'] as List<dynamic>;
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
      _showError('No verified pharmacies are currently available.');
      return;
    }
    final available = _availablePackages;
    if (available.isEmpty) {
      _showError('There are no available, non-recalled packages to dispatch.');
      return;
    }
    final selectedPackages = <String>{};
    final notesController = TextEditingController();
    var selectedPharmacyId = _pharmacies.first['id'].toString();
    final packageSerials = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create pharmacy order'),
          content: SizedBox(
            width: 560,
            height: 500,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedPharmacyId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Verified pharmacy',
                  ),
                  items: _pharmacies
                      .map((pharmacy) => DropdownMenuItem<String>(
                            value: pharmacy['id'].toString(),
                            child: Text(pharmacy['name'].toString()),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedPharmacyId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Select package quantities to supply'),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: available.length,
                    itemBuilder: (context, index) {
                      final package = available[index];
                      final serial = package['package_serial_id'].toString();
                      return CheckboxListTile(
                        value: selectedPackages.contains(serial),
                        onChanged: (selected) => setDialogState(() {
                          if (selected == true) {
                            selectedPackages.add(serial);
                          } else {
                            selectedPackages.remove(serial);
                          }
                        }),
                        title: Text(
                          '${package['product_name']} · ${package['batch_number']}',
                        ),
                        subtitle: Text(
                          '$serial · Expires ${package['expiry_date']}',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Order / delivery notes (optional)',
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
    if (packageSerials == null) return;
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

  Widget _buildIncomingTab({bool allowScanReceipt = false}) {
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
                action: allowScanReceipt
                    ? ElevatedButton.icon(
                        onPressed: () => _confirmScannedReceipt(shipment),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan & receive'),
                      )
                    : null,
              ))
          .toList(),
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

  Widget _buildPharmacyDirectoryTab() {
    if (_pharmacies.isEmpty) {
      return const Center(
          child: Text('No verified pharmacies are registered.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _pharmacies
          .map((pharmacy) => Card(
                child: ListTile(
                  leading: const Icon(Icons.local_pharmacy_outlined),
                  title: Text(pharmacy['name'].toString()),
                  subtitle: Text(
                    '${pharmacy['contact_email']}\n'
                    'Delivery address: ${pharmacy['address']}\n'
                    'License ${pharmacy['license_number']} · Verified',
                  ),
                  isThreeLine: true,
                  trailing: const Chip(
                    label: Text('Verified'),
                    avatar: Icon(Icons.verified, size: 18),
                  ),
                ),
              ))
          .toList(),
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
                onPressed: _pharmacies.isEmpty || _availablePackages.isEmpty
                    ? null
                    : _createPharmacyOrder,
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
              onPressed: _pharmacies.isEmpty || _availablePackages.isEmpty
                  ? null
                  : _createPharmacyOrder,
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
                trailing: Chip(label: Text(recall['status'].toString())),
              ),
            )),
      ],
    );
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
    return DefaultTabController(
      key: ValueKey<int>(widget.initialTabIndex),
      length: tabs.length,
      initialIndex: widget.initialTabIndex.clamp(0, tabs.length - 1),
      child: Column(
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
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: tabs,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildOverviewTab(),
                _buildIncomingTab(),
                _buildIncomingTab(allowScanReceipt: true),
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
      ),
    );
  }
}
