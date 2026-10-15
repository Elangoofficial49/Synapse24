import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../core/theme.dart';
import '../screens/manufacturer_tools.dart';
import '../screens/distributor_tools.dart';
import '../screens/pharmacy_tools.dart';
import '../widgets/package_verification_card.dart';
import '../widgets/qr_scanner_dialog.dart';

class DashboardPage extends StatefulWidget {
  final VoidCallback onLogout;

  const DashboardPage({super.key, required this.onLogout});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _selectedTab = 'manufacturing-overview';
  int _distributorTabIndex = 0;
  int _manufacturerTabIndex = 0;
  int _pharmacyTabIndex = 0;
  bool _isLoading = true;
  Map<String, dynamic>? _metrics;
  Map<String, dynamic>? _user;
  List<dynamic> _shipments = [];
  List<dynamic> _wholesalerPartners = [];
  List<dynamic> _transferInventory = [];
  List<dynamic> _alerts = [];
  List<dynamic> _disputes = [];
  List<dynamic> _pendingUsers = [];
  final TextEditingController _scanInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _user = await apiService.getCurrentUser();
      if (_role == 'manufacturer') {
        _selectedTab = 'manufacturing-overview';
        _manufacturerTabIndex = 0;
      } else if (_role == 'distributor') {
        _selectedTab = 'distributor-overview';
        _distributorTabIndex = 0;
      } else if (_role == 'pharmacy_staff' || _role == 'pharmacy') {
        _selectedTab = 'pharmacy-overview';
        _pharmacyTabIndex = 0;
      }
      await _loadAllData();
    } catch (e) {
      if (mounted) _showError('Unable to load your account: $e');
    }
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final canReviewCompliance = [
        'admin',
        'auditor',
        'manufacturer',
      ].contains(_role);
      final requests = <Future<dynamic>>[
        apiService.getDashboardMetrics(),
        apiService.getShipments(),
      ];
      if (canReviewCompliance) {
        requests
          ..add(apiService.getAlerts())
          ..add(apiService.getDisputes());
      }
      if (_role == 'admin') requests.add(apiService.getPendingUsers());
      if (_role == 'distributor') {
        requests
          ..add(apiService.getWholesalerPartners())
          ..add(apiService.getTransferInventory());
      }
      final results = await Future.wait(requests);

      setState(() {
        _metrics = results[0] as Map<String, dynamic>;
        _shipments = results[1] as List<dynamic>;
        var resultIndex = 2;
        if (canReviewCompliance) {
          _alerts = results[resultIndex++] as List<dynamic>;
          _disputes = results[resultIndex++] as List<dynamic>;
        } else {
          _alerts = [];
          _disputes = [];
        }
        if (_role == 'admin') {
          _pendingUsers = results[resultIndex++] as List<dynamic>;
        }
        if (_role == 'distributor') {
          _wholesalerPartners = results[resultIndex++] as List<dynamic>;
          _transferInventory = results[resultIndex] as List<dynamic>;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching dashboard: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _role => _user?['role']?.toString() ?? '';
  String get _organizationId => _user?['organization_id']?.toString() ?? '';

  List<_NavItem> get _navItems {
    if (_role == 'manufacturer') {
      return const <_NavItem>[
        _NavItem(
            'manufacturing-overview', 'Overview', Icons.dashboard_outlined),
        _NavItem('manufacturing-create-batch', 'Create New Batch',
            Icons.add_box_outlined),
        _NavItem('manufacturing-qr', 'Generate QR Code', Icons.qr_code_2),
        _NavItem('manufacturing-inventory', 'Batch Inventory',
            Icons.inventory_2_outlined),
        _NavItem('manufacturing-distributors', 'Distributors',
            Icons.local_shipping_outlined),
        _NavItem('manufacturing-dispatch', 'Dispatch Management',
            Icons.outbox_outlined),
        _NavItem(
            'manufacturing-pending', 'Pending Receipts', Icons.hourglass_top),
        _NavItem('manufacturing-verify', 'Batch Verification',
            Icons.qr_code_scanner),
        _NavItem('manufacturing-recall', 'Recall Management',
            Icons.warning_amber_outlined),
        _NavItem('manufacturing-audit', 'Audit History', Icons.history),
        _NavItem('manufacturing-documents', 'Document Management',
            Icons.description_outlined),
        _NavItem('manufacturing-notifications', 'Notifications',
            Icons.notifications_outlined),
      ];
    }

    if (_role == 'distributor') {
      return const <_NavItem>[
        _NavItem('distributor-overview', 'Overview', Icons.dashboard_outlined),
        _NavItem(
            'distributor-incoming', 'Incoming Shipments', Icons.move_to_inbox),
        _NavItem('distributor-scan', 'Scan & Receive', Icons.qr_code_scanner),
        _NavItem('distributor-receipt', 'Receipt Confirmation',
            Icons.fact_check_outlined),
        _NavItem('distributor-inventory', 'My Inventory',
            Icons.inventory_2_outlined),
        _NavItem('distributor-directory', 'Pharmacy Directory',
            Icons.local_pharmacy_outlined),
        _NavItem('distributor-order', 'Create Pharmacy Order',
            Icons.add_shopping_cart),
        _NavItem('distributor-dispatch', 'Dispatch to Pharmacy',
            Icons.outbox_outlined),
        _NavItem('distributor-pending', 'Pending Pharmacy Receipts',
            Icons.hourglass_top),
        _NavItem('distributor-history', 'Transfer History', Icons.history),
        _NavItem('distributor-verify', 'Batch Verification',
            Icons.verified_outlined),
        _NavItem('distributor-recall', 'Recall & Quarantine',
            Icons.gpp_bad_outlined),
        _NavItem('distributor-suspicious', 'Suspicious Scan Reports',
            Icons.security_outlined),
        _NavItem('distributor-notifications', 'Notifications',
            Icons.notifications_outlined),
      ];
    }

    if (_role == 'pharmacy_staff' || _role == 'pharmacy') {
      return const <_NavItem>[
        _NavItem('pharmacy-overview', 'Overview', Icons.dashboard_outlined),
        _NavItem('pharmacy-incoming', 'Incoming Deliveries',
            Icons.local_shipping_outlined),
        _NavItem('pharmacy-verify', 'Scan & Verify', Icons.qr_code_scanner),
        _NavItem(
            'pharmacy-receipt', 'Confirm Receipt', Icons.fact_check_outlined),
        _NavItem('pharmacy-inventory', 'Medicine Inventory',
            Icons.inventory_2_outlined),
        _NavItem(
            'pharmacy-batch-details', 'Batch Details', Icons.layers_outlined),
        _NavItem(
            'pharmacy-expiry', 'Expiry Management', Icons.event_busy_outlined),
        _NavItem(
            'pharmacy-recall', 'Recall Alerts', Icons.warning_amber_rounded),
        _NavItem('pharmacy-dispense', 'Dispensing Records',
            Icons.medication_outlined),
        _NavItem('pharmacy-suspicious', 'Suspicious Product Report',
            Icons.report_problem_outlined),
        _NavItem(
            'pharmacy-suppliers', 'Supplier History', Icons.business_outlined),
        _NavItem('pharmacy-audit', 'Audit History', Icons.history_edu_outlined),
        _NavItem('pharmacy-notifications', 'Notifications',
            Icons.notifications_outlined),
      ];
    }

    final items = <_NavItem>[
      const _NavItem('overview', 'Overview', Icons.dashboard_outlined),
      const _NavItem('scan', 'Scan QR', Icons.qr_code_scanner),
    ];
    if (['transporter', 'admin'].contains(_role)) {
      items.add(const _NavItem(
          'shipments', 'Shipments', Icons.local_shipping_outlined));
    }
    if (['admin', 'auditor'].contains(_role)) {
      items.add(
          const _NavItem('disputes', 'Disputes', Icons.warning_amber_outlined));
      items.add(const _NavItem('alerts', 'Alerts', Icons.security_outlined));
    }
    if (_role == 'admin') {
      items.add(const _NavItem(
          'approvals', 'Account approvals', Icons.approval_outlined));
    }
    return items;
  }

  Future<void> _verifyPackage(String rawData) async {
    final value = rawData.trim();
    if (value.isEmpty) return;
    setState(() {
      _scanInputController.text = value;
      _isLoading = true;
    });
    try {
      final result = await apiService.verifyPackage(value);
      if (mounted) {
        setState(() {
          _scanInputController.text = value;
          _verificationResult = result;
        });
      }
    } catch (error) {
      if (mounted) _showError('Package verification failed: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _verificationResult;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorRed),
    );
  }

  Future<void> _approveUser(dynamic pendingUser) async {
    try {
      await apiService.approveUser(pendingUser['id'].toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${pendingUser['organization_name']} approved.')),
        );
        await _loadAllData();
      }
    } catch (error) {
      if (mounted) _showError('Could not approve account: $error');
    }
  }

  Future<void> _logout() async {
    await apiService.logout();
    widget.onLogout();
  }

  @override
  void dispose() {
    _scanInputController.dispose();
    super.dispose();
  }

  void _receiveShipmentDialog(dynamic shipment) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Confirm Transfer: ${shipment['shipment_reference']}"),
        content: Text(
          "The sender declared ${shipment['declared_quantity']} units. "
          "Confirm success if the shipment arrived complete, or declare a "
          "discrepancy to record the quantity received and notify the sender.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _recordShipmentReceipt(
                shipment,
                int.parse(shipment['declared_quantity'].toString()),
              );
            },
            child: const Text("Confirm Transfer Success"),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _declareShipmentDiscrepancy(shipment);
            },
            child: const Text("Declare Discrepancy"),
          ),
        ],
      ),
    );
  }

  Future<void> _declareShipmentDiscrepancy(dynamic shipment) async {
    final quantityController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Declare shipment discrepancy'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The sender declared ${shipment['declared_quantity']} units. '
                'Enter the quantity actually received and explain the discrepancy. '
                'Your reason will be included in the dispute sent to the sender.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Actual quantity received',
                ),
                validator: (value) {
                  final quantity = int.tryParse(value?.trim() ?? '');
                  if (quantity == null || quantity < 0) {
                    return 'Enter a valid non-negative quantity';
                  }
                  if (quantity ==
                      int.parse(shipment['declared_quantity'].toString())) {
                    return 'The quantity matches the declaration; confirm transfer success instead';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason for the manufacturer / sender',
                  hintText: 'Describe missing, damaged, or incorrect goods',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'A discrepancy reason is required'
                    : null,
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
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  (
                    int.parse(quantityController.text.trim()),
                    reasonController.text.trim(),
                  ),
                );
              }
            },
            child: const Text('Submit discrepancy'),
          ),
        ],
      ),
    );
    quantityController.dispose();
    reasonController.dispose();
    if (result != null) {
      await _recordShipmentReceipt(shipment, result.$1, result.$2);
    }
  }

  Future<void> _recordShipmentReceipt(
    dynamic shipment,
    int actualQuantity, [
    String? reason,
  ]) async {
    try {
      final result = await apiService.receiveShipment(
        shipment['id'].toString(),
        actualQuantity,
        reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['discrepancy_detected']
              ? 'Discrepancy reported to the sender. Dispute #${result['dispute_id'] ?? 'auto'} opened.'
              : 'Transfer confirmed successfully.'),
          backgroundColor: result['discrepancy_detected']
              ? AppTheme.warningAmber
              : AppTheme.successGreen,
        ),
      );
      await _loadAllData();
    } catch (error) {
      if (mounted) _showError('Could not confirm transfer: $error');
    }
  }

  Future<void> _createWholesalerTransfer(dynamic partner) async {
    final selectedPackages = <String>{};
    final notesController = TextEditingController();
    final packageInventory =
        _transferInventory.whereType<Map<String, dynamic>>().toList();
    final packageSerialIds = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Transfer inventory · ${partner['name']}'),
          content: SizedBox(
            width: 520,
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select packages currently in your custody to dispatch to this wholesaler.',
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: packageInventory.isEmpty
                      ? const Center(
                          child: Text('No available inventory to transfer.'),
                        )
                      : ListView.builder(
                          itemCount: packageInventory.length,
                          itemBuilder: (context, index) {
                            final item = packageInventory[index];
                            final serial = item['package_serial_id'].toString();
                            return CheckboxListTile(
                              value: selectedPackages.contains(serial),
                              onChanged: (selected) => setDialogState(() {
                                if (selected == true) {
                                  selectedPackages.add(serial);
                                } else {
                                  selectedPackages.remove(serial);
                                }
                              }),
                              title: Text(serial),
                              subtitle: Text(
                                '${item['product_name']} · Batch ${item['batch_number']}',
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Transfer notes (optional)',
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
    if (packageSerialIds == null) return;

    try {
      final shipment = await apiService.createShipment(
        partner['id'].toString(),
        packageSerialIds,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transfer ${shipment['shipment_reference']} dispatched to ${partner['name']}.',
          ),
          backgroundColor: AppTheme.successGreen,
        ),
      );
      await _loadAllData();
    } catch (error) {
      if (mounted) _showError('Could not dispatch transfer: $error');
    }
  }

  void _showShipmentDetails(dynamic shipment) {
    final shipmentId = shipment['id'].toString();
    final detailsFuture = apiService.getShipmentDetails(shipmentId);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: FutureBuilder<Map<String, dynamic>>(
            future: detailsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          'Could not load shipment details: ${snapshot.error}'),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }

              final details = snapshot.data!;
              final items = details['items'] as List<dynamic>? ?? [];
              final disputes = details['disputes'] as List<dynamic>? ?? [];
              final status = details['status'].toString();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            details['shipment_reference'].toString(),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(24),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                                label: Text(
                                    status.replaceAll('_', ' ').toUpperCase())),
                            Chip(
                              label: Text(
                                'Received ${details['received_quantity'] ?? '—'} / ${details['declared_quantity']} units',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _shipmentDetailLine(
                          'Sender',
                          details['sender_organization_name'].toString(),
                        ),
                        _shipmentDetailLine(
                          'Receiver',
                          details['receiver_organization_name'].toString(),
                        ),
                        _shipmentDetailLine(
                          'Dispatched',
                          _formatShipmentDate(details['dispatch_timestamp']),
                        ),
                        _shipmentDetailLine(
                          'Received',
                          _formatShipmentDate(details['receipt_timestamp']),
                        ),
                        if ((details['notes'] as String?)?.isNotEmpty == true)
                          _shipmentDetailLine(
                              'Shipment notes', details['notes'].toString()),
                        const SizedBox(height: 16),
                        Text(
                          'Packages (${items.length})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final item in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const Icon(Icons.qr_code_2),
                            title: Text(item['package_serial_id'].toString()),
                            subtitle: Text(
                              'Status: ${item['status']} · Received: ${item['quantity_received'] ?? 'Pending'}',
                            ),
                          ),
                        if (disputes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Discrepancies (${disputes.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          for (final dispute in disputes)
                            Card(
                              color:
                                  AppTheme.warningAmber.withValues(alpha: 0.12),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${dispute['status'].toString().toUpperCase()} · Expected ${dispute['expected_quantity']}, received ${dispute['actual_quantity']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(dispute['dispute_reason'].toString()),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _shipmentDetailLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  String _formatShipmentDate(dynamic value) {
    if (value == null) return '—';
    final date = DateTime.tryParse(value.toString());
    return date?.toLocal().toString().split('.').first ?? value.toString();
  }

  bool get _canReviewCompliance => _role == 'admin' || _role == 'auditor';

  Future<void> _openDispute(dynamic dispute) async {
    final shipmentId = dispute['shipment_id'].toString();
    final shipmentFuture = apiService.getShipmentDetails(shipmentId);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Dispute · Shipment #${shipmentId.substring(0, 8)}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _shipmentDetailLine(
                  'Status',
                  dispute['status'].toString().replaceAll('_', ' '),
                ),
                _shipmentDetailLine(
                  'Expected',
                  '${dispute['expected_quantity']} units',
                ),
                _shipmentDetailLine(
                  'Received',
                  '${dispute['actual_quantity']} units',
                ),
                const SizedBox(height: 12),
                const Text('Dispute reason',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(dispute['dispute_reason'].toString()),
                if ((dispute['resolution_notes'] as String?)?.isNotEmpty ==
                    true) ...[
                  const SizedBox(height: 12),
                  const Text('Resolution notes',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(dispute['resolution_notes'].toString()),
                ],
                const SizedBox(height: 16),
                const Text('Related shipment',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                FutureBuilder<Map<String, dynamic>>(
                  future: shipmentFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text(
                          'Shipment details unavailable: ${snapshot.error}');
                    }
                    final shipment = snapshot.data!;
                    return Text(
                      '${shipment['shipment_reference']} · '
                      '${shipment['sender_organization_name']} → '
                      '${shipment['receiver_organization_name']} · '
                      '${shipment['received_quantity'] ?? '—'} / '
                      '${shipment['declared_quantity']} received',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_canReviewCompliance &&
              dispute['status'].toString() != 'resolved')
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _resolveDispute(dispute);
              },
              child: const Text('Resolve dispute'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveDispute(dynamic dispute) async {
    final notesController = TextEditingController();
    final justificationController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final shouldResolve = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve dispute'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Resolution notes',
                  hintText: 'Explain how the discrepancy was resolved',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Resolution notes are required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: justificationController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Correction justification (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (shouldResolve != true) {
      notesController.dispose();
      justificationController.dispose();
      return;
    }

    try {
      await apiService.resolveDispute(
        dispute['id'].toString(),
        resolutionNotes: notesController.text.trim(),
        correctionJustification: justificationController.text.trim().isEmpty
            ? null
            : justificationController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispute resolved.')),
      );
      await _loadAllData();
    } catch (error) {
      if (mounted) _showError('Could not resolve dispute: $error');
    } finally {
      notesController.dispose();
      justificationController.dispose();
    }
  }

  Future<void> _openAlert(dynamic alert) async {
    final notesController = TextEditingController(
      text: alert['investigator_notes']?.toString() ?? '',
    );
    final outcomeController = TextEditingController(
      text: alert['resolution_outcome']?.toString() ?? '',
    );
    final currentStatus = alert['review_status'].toString();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Alert · ${alert['alert_type']}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _shipmentDetailLine('Severity', alert['severity'].toString()),
                _shipmentDetailLine(
                    'Status', currentStatus.replaceAll('_', ' ')),
                _shipmentDetailLine(
                  'Created',
                  _formatShipmentDate(alert['created_at']),
                ),
                if (alert['shipment_id'] != null)
                  _shipmentDetailLine(
                    'Shipment ID',
                    alert['shipment_id'].toString(),
                  ),
                if (alert['package_id'] != null)
                  _shipmentDetailLine(
                    'Package ID',
                    alert['package_id'].toString(),
                  ),
                const SizedBox(height: 12),
                const Text('Alert details',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(alert['reason'].toString()),
                if (_canReviewCompliance) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Investigation notes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: outcomeController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Resolution outcome',
                    ),
                  ),
                ] else ...[
                  if ((alert['investigator_notes'] as String?)?.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 12),
                    const Text('Investigation notes',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(alert['investigator_notes'].toString()),
                  ],
                  if ((alert['resolution_outcome'] as String?)?.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 12),
                    const Text('Resolution outcome',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(alert['resolution_outcome'].toString()),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_canReviewCompliance && currentStatus != 'resolved')
            TextButton(
              onPressed: () => _saveAlertReview(
                dialogContext,
                alert,
                'under_review',
                notesController,
                outcomeController,
              ),
              child: const Text('Mark under review'),
            ),
          if (_canReviewCompliance && currentStatus != 'false_positive')
            TextButton(
              onPressed: () => _saveAlertReview(
                dialogContext,
                alert,
                'false_positive',
                notesController,
                outcomeController,
              ),
              child: const Text('False positive'),
            ),
          if (_canReviewCompliance && currentStatus != 'resolved')
            ElevatedButton(
              onPressed: () => _saveAlertReview(
                dialogContext,
                alert,
                'resolved',
                notesController,
                outcomeController,
              ),
              child: const Text('Resolve alert'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    notesController.dispose();
    outcomeController.dispose();
  }

  Future<void> _saveAlertReview(
    BuildContext dialogContext,
    dynamic alert,
    String reviewStatus,
    TextEditingController notesController,
    TextEditingController outcomeController,
  ) async {
    try {
      await apiService.updateAlert(
        alert['id'].toString(),
        reviewStatus: reviewStatus,
        investigatorNotes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        resolutionOutcome: outcomeController.text.trim().isEmpty
            ? null
            : outcomeController.text.trim(),
      );
      if (!mounted || !dialogContext.mounted) return;
      Navigator.pop(dialogContext);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert review updated.')),
      );
      await _loadAllData();
    } catch (error) {
      if (mounted) _showError('Could not update alert: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        _navItems.indexWhere((item) => item.id == _selectedTab);
    return Scaffold(
      appBar: AppBar(
        title: Text(_user?['organization_name']?.toString().isNotEmpty == true
            ? 'PharmaTrace · ${_user!['organization_name']}'
            : 'PharmaTrace Operational Console'),
        actions: [
          if (_user?['full_name'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                  child: Text(
                      '${_user!['full_name']} · ${_role.replaceAll('_', ' ')}')),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAllData),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height - kToolbarHeight),
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
                  onDestinationSelected: (idx) {
                    final tabId = _navItems[idx].id;
                    if (tabId.startsWith('manufacturing-')) {
                      final manufacturerTabMap = {
                        'manufacturing-overview': 0,
                        'manufacturing-create-batch': 1,
                        'manufacturing-qr': 2,
                        'manufacturing-inventory': 3,
                        'manufacturing-distributors': 4,
                        'manufacturing-dispatch': 5,
                        'manufacturing-pending': 6,
                        'manufacturing-verify': 7,
                        'manufacturing-recall': 8,
                        'manufacturing-audit': 9,
                        'manufacturing-documents': 10,
                        'manufacturing-notifications': 11,
                      };
                      setState(() {
                        _selectedTab = tabId;
                        _manufacturerTabIndex = manufacturerTabMap[tabId] ?? 0;
                      });
                    } else if (tabId.startsWith('distributor-')) {
                      final distributorTabMap = {
                        'distributor-overview': 0,
                        'distributor-incoming': 1,
                        'distributor-scan': 2,
                        'distributor-receipt': 3,
                        'distributor-inventory': 4,
                        'distributor-directory': 5,
                        'distributor-order': 6,
                        'distributor-dispatch': 7,
                        'distributor-pending': 8,
                        'distributor-history': 9,
                        'distributor-verify': 10,
                        'distributor-recall': 11,
                        'distributor-suspicious': 12,
                        'distributor-notifications': 13,
                      };
                      setState(() {
                        _selectedTab = tabId;
                        _distributorTabIndex = distributorTabMap[tabId] ?? 0;
                      });
                    } else if (tabId.startsWith('pharmacy-')) {
                      final pharmacyTabMap = {
                        'pharmacy-overview': 0,
                        'pharmacy-incoming': 1,
                        'pharmacy-verify': 2,
                        'pharmacy-receipt': 3,
                        'pharmacy-inventory': 4,
                        'pharmacy-batch-details': 5,
                        'pharmacy-expiry': 6,
                        'pharmacy-recall': 7,
                        'pharmacy-dispense': 8,
                        'pharmacy-suspicious': 9,
                        'pharmacy-suppliers': 10,
                        'pharmacy-audit': 11,
                        'pharmacy-notifications': 12,
                      };
                      setState(() {
                        _selectedTab = tabId;
                        _pharmacyTabIndex = pharmacyTabMap[tabId] ?? 0;
                      });
                    } else {
                      setState(() => _selectedTab = tabId);
                    }
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: _navItems
                      .map((item) => NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.icon),
                            label: Text(item.label),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, color: AppTheme.border),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildCurrentTab(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTab() {
    if (_role == 'manufacturer' || _selectedTab.startsWith('manufacturing-')) {
      final tabIndex = {
            'manufacturing-overview': 0,
            'manufacturing-create-batch': 1,
            'manufacturing-qr': 2,
            'manufacturing-inventory': 3,
            'manufacturing-distributors': 4,
            'manufacturing-dispatch': 5,
            'manufacturing-pending': 6,
            'manufacturing-verify': 7,
            'manufacturing-recall': 8,
            'manufacturing-audit': 9,
            'manufacturing-documents': 10,
            'manufacturing-notifications': 11,
          }[_selectedTab] ??
          _manufacturerTabIndex;

      return ManufacturerTools(
        initialTabIndex: tabIndex,
        onVerifyBatch: () => setState(() {
          _selectedTab = 'manufacturing-verify';
          _manufacturerTabIndex = 7;
        }),
      );
    }

    if (_role == 'distributor' || _selectedTab.startsWith('distributor-')) {
      final tabIndex = {
            'distributor-overview': 0,
            'distributor-incoming': 1,
            'distributor-scan': 2,
            'distributor-receipt': 3,
            'distributor-inventory': 4,
            'distributor-directory': 5,
            'distributor-order': 6,
            'distributor-dispatch': 7,
            'distributor-pending': 8,
            'distributor-history': 9,
            'distributor-verify': 10,
            'distributor-recall': 11,
            'distributor-suspicious': 12,
            'distributor-notifications': 13,
          }[_selectedTab] ??
          _distributorTabIndex;

      return DistributorTools(initialTabIndex: tabIndex);
    }

    if (_role == 'pharmacy_staff' ||
        _role == 'pharmacy' ||
        _selectedTab.startsWith('pharmacy-')) {
      final tabIndex = {
            'pharmacy-overview': 0,
            'pharmacy-incoming': 1,
            'pharmacy-verify': 2,
            'pharmacy-receipt': 3,
            'pharmacy-inventory': 4,
            'pharmacy-batch-details': 5,
            'pharmacy-expiry': 6,
            'pharmacy-recall': 7,
            'pharmacy-dispense': 8,
            'pharmacy-suspicious': 9,
            'pharmacy-suppliers': 10,
            'pharmacy-audit': 11,
            'pharmacy-notifications': 12,
          }[_selectedTab] ??
          _pharmacyTabIndex;

      return PharmacyTools(initialTabIndex: tabIndex);
    }

    switch (_selectedTab) {
      case 'overview':
        return _buildOverviewTab();
      case 'scan':
        return _buildScanTab();
      case 'manufacturing':
        return ManufacturerTools(
          initialTabIndex: _manufacturerTabIndex,
          onVerifyBatch: () => setState(() => _selectedTab = 'scan'),
        );
      case 'distributor-dashboard':
        return DistributorTools(initialTabIndex: _distributorTabIndex);
      case 'shipments':
        return _buildShipmentsTab();
      case 'partners':
        return _buildWholesalerPartnersTab();
      case 'disputes':
        return _buildDisputesTab();
      case 'alerts':
        return _buildAlertsTab();
      case 'approvals':
        return _buildApprovalsTab();
      default:
        return _buildOverviewTab();
    }
  }

  Widget _buildScanTab() {
    return ListView(
      children: [
        const Text('Package QR scanner',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            'Scan a manufacturer-issued package QR code to view product information and custody tracking.'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => QrScannerDialog.show(
                        context,
                        onScanned: (value) => _verifyPackage(value),
                      ),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Open camera scanner'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _scanInputController,
          decoration: const InputDecoration(
            labelText: 'Or enter a package QR URL / serial ID',
            prefixIcon: Icon(Icons.qr_code),
          ),
          onSubmitted: _verifyPackage,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            onPressed: _isLoading
                ? null
                : () => _verifyPackage(_scanInputController.text),
            icon: const Icon(Icons.search),
            label: const Text('Verify package'),
          ),
        ),
        if (_verificationResult != null) ...[
          const SizedBox(height: 20),
          PackageVerificationCard(result: _verificationResult!),
        ],
      ],
    );
  }

  Widget _buildApprovalsTab() {
    if (_pendingUsers.isEmpty) {
      return const Center(child: Text('There are no pending registrations.'));
    }
    return ListView(
      children: [
        const Text('Organization registrations awaiting review',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 12),
        ..._pendingUsers.map((pending) => Card(
              child: ListTile(
                leading: const Icon(Icons.business_outlined,
                    color: AppTheme.deepTeal),
                title: Text(pending['organization_name'].toString()),
                subtitle: Text(
                  '${pending['organization_type']} · License ${pending['license_number']}\n'
                  '${pending['full_name']} (${pending['email']}) · ${pending['role']}',
                ),
                isThreeLine: true,
                trailing: ElevatedButton(
                  onPressed: () => _approveUser(pending),
                  child: const Text('Approve'),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final summary = _metrics?['summary'] ?? {};
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              _role == 'manufacturer'
                  ? 'Manufacturing overview'
                  : 'Supply Chain Operational Metrics',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navy)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _metricCard("Total Packages", "${summary['total_packages'] ?? 0}",
                  Icons.inventory_2_outlined, AppTheme.deepTeal),
              _metricCard("Shipments", "${summary['total_shipments'] ?? 0}",
                  Icons.local_shipping_outlined, AppTheme.mutedTeal),
              _metricCard("Disputes Open", "${summary['open_disputes'] ?? 0}",
                  Icons.gavel_outlined, AppTheme.warningAmber),
              _metricCard("Anomalies Flagged", "${summary['open_alerts'] ?? 0}",
                  Icons.crisis_alert_outlined, AppTheme.errorRed),
            ],
          ),
          const SizedBox(height: 32),
          const Text("Recent Shipments",
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navy)),
          const SizedBox(height: 12),
          _buildShipmentsTable(limit: 5, isScrollable: false),
        ],
      ),
    );
  }

  Widget _buildShipmentsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Custody Transfers & Two-Party Acceptance",
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        const Text(
            "Receiver organization must independently verify quantity before on-chain confirmation.",
            style: TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(height: 16),
        Expanded(child: _buildShipmentsTable()),
      ],
    );
  }

  Widget _buildWholesalerPartnersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Wholesaler partners',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_wholesalerPartners.length} existing partners · '
          '${_transferInventory.length} packages available to transfer',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        if (_wholesalerPartners.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No wholesaler relationships yet. Your distributor contacts '
                'will appear here after you exchange a shipment with them.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _wholesalerPartners.length,
              itemBuilder: (context, index) {
                final partner = _wholesalerPartners[index];
                final transfers = _shipments.where((shipment) =>
                    shipment['sender_org_id'] == partner['id'] ||
                    shipment['receiver_org_id'] == partner['id']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.storefront_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                partner['name'].toString(),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.navy,
                                ),
                              ),
                            ),
                            Text('${transfers.length} transfers'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _shipmentDetailLine(
                          'Contact email',
                          partner['contact_email'].toString(),
                        ),
                        _shipmentDetailLine(
                          'Address',
                          partner['address'].toString(),
                        ),
                        _shipmentDetailLine(
                          'License',
                          partner['license_number'].toString(),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _transferInventory.isEmpty
                                ? null
                                : () => _createWholesalerTransfer(partner),
                            icon: const Icon(Icons.local_shipping_outlined),
                            label: const Text('Transfer inventory'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildShipmentsTable({int? limit, bool isScrollable = true}) {
    final list = limit != null && _shipments.length > limit
        ? _shipments.sublist(0, limit)
        : _shipments;
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text("No shipments found.",
            style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    return ListView.builder(
      shrinkWrap: !isScrollable,
      physics: isScrollable
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      itemBuilder: (ctx, idx) {
        final shp = list[idx];
        final isPending =
            shp['status'] == 'dispatched' || shp['status'] == 'in_transit';
        final canReceive =
            isPending && shp['receiver_org_id'] == _organizationId;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            onTap: () => _showShipmentDetails(shp),
            leading:
                const Icon(Icons.inventory_outlined, color: AppTheme.deepTeal),
            title: Text(shp['shipment_reference'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                "Declared: ${shp['declared_quantity']} units | Received: ${shp['received_quantity'] ?? 'Pending'} | Status: ${shp['status']}"),
            trailing: canReceive
                ? ElevatedButton(
                    onPressed: _role == 'distributor'
                        ? () => setState(() {
                              _selectedTab = 'distributor-dashboard';
                              _distributorTabIndex = 2;
                            })
                        : () => _receiveShipmentDialog(shp),
                    child: Text(_role == 'distributor'
                        ? "Scan to Receive"
                        : "Receive Shipment"),
                  )
                : Chip(
                    label: Text(shp['status'].toString().toUpperCase(),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white)),
                    backgroundColor: shp['status'] == 'received'
                        ? AppTheme.successGreen
                        : AppTheme.warningAmber,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildDisputesTab() {
    if (_disputes.isEmpty) {
      return const Center(child: Text("No open discrepancy disputes."));
    }
    return ListView.builder(
      itemCount: _disputes.length,
      itemBuilder: (ctx, idx) {
        final d = _disputes[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.gavel, color: AppTheme.warningAmber),
            title: Text(
                "Dispute on Shipment #${d['shipment_id'].toString().substring(0, 8)}"),
            subtitle: Text(
                "Expected: ${d['expected_quantity']} | Received: ${d['actual_quantity']}\nReason: ${d['dispute_reason']}"),
            isThreeLine: true,
            onTap: () => _openDispute(d),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(d['status']),
                  backgroundColor: AppTheme.warningAmber.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _openDispute(d),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlertsTab() {
    if (_alerts.isEmpty) {
      return const Center(
          child: Text("No suspicious activity alerts recorded."));
    }
    return ListView.builder(
      itemCount: _alerts.length,
      itemBuilder: (ctx, idx) {
        final a = _alerts[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded,
                color: AppTheme.errorRed),
            title: Text("Anomaly: ${a['alert_type']}"),
            subtitle: Text("${a['reason']}\nSeverity: ${a['severity']}"),
            isThreeLine: true,
            onTap: () => _openAlert(a),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(a['review_status']),
                  backgroundColor: AppTheme.errorRed.withValues(alpha: 0.1),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _openAlert(a),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.navy)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          )
        ],
      ),
    );
  }
}

class _NavItem {
  final String id;
  final String label;
  final IconData icon;

  const _NavItem(this.id, this.label, this.icon);
}
