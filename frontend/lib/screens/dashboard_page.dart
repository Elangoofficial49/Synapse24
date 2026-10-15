import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../core/theme.dart';
import '../screens/manufacturer_tools.dart';
import '../widgets/package_verification_card.dart';
import '../widgets/qr_scanner_dialog.dart';

class DashboardPage extends StatefulWidget {
  final VoidCallback onLogout;

  const DashboardPage({super.key, required this.onLogout});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _selectedTab = 'overview';
  bool _isLoading = true;
  Map<String, dynamic>? _metrics;
  Map<String, dynamic>? _user;
  List<dynamic> _shipments = [];
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
      await _loadAllData();
    } catch (e) {
      if (mounted) _showError('Unable to load your account: $e');
    }
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        apiService.getDashboardMetrics(),
        apiService.getShipments(),
        apiService.getAlerts(),
        apiService.getDisputes(),
        if (_role == 'admin') apiService.getPendingUsers(),
      ]);

      setState(() {
        _metrics = results[0] as Map<String, dynamic>;
        _shipments = results[1] as List<dynamic>;
        _alerts = results[2] as List<dynamic>;
        _disputes = results[3] as List<dynamic>;
        if (_role == 'admin') _pendingUsers = results[4] as List<dynamic>;
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
    final items = <_NavItem>[
      const _NavItem('overview', 'Overview', Icons.dashboard_outlined),
      const _NavItem('scan', 'Scan QR', Icons.qr_code_scanner),
    ];
    if (_role == 'manufacturer') {
      items.add(const _NavItem(
          'manufacturing', 'Manufacturing & QR', Icons.qr_code_2));
    }
    if ([
      'manufacturer',
      'distributor',
      'transporter',
      'pharmacy_staff',
      'admin'
    ].contains(_role)) {
      items.add(const _NavItem(
          'shipments', 'Shipments', Icons.local_shipping_outlined));
    }
    if (['admin', 'auditor', 'manufacturer'].contains(_role)) {
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
    final qtyController =
        TextEditingController(text: shipment['declared_quantity'].toString());
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Two-Party Receipt: ${shipment['shipment_reference']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Declared by Sender: ${shipment['declared_quantity']} units",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Actual Quantity Received",
                helperText:
                    "Enter less than declared to trigger discrepancy dispute workflow",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                  labelText: "Inspection Notes (Optional)"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final actual = int.tryParse(qtyController.text) ?? 0;
              try {
                final res = await apiService.receiveShipment(
                    shipment['id'], actual, notesController.text);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(res['discrepancy_detected']
                        ? "Discrepancy registered! Dispute #${res['dispute_id'] ?? 'auto'} opened."
                        : "Shipment accepted and confirmed on ledger."),
                    backgroundColor: res['discrepancy_detected']
                        ? AppTheme.warningAmber
                        : AppTheme.successGreen,
                  ),
                );
                _loadAllData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text("Error: $e"),
                      backgroundColor: AppTheme.errorRed),
                );
              }
            },
            child: const Text("Confirm Receipt"),
          ),
        ],
      ),
    );
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
          NavigationRail(
            selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
            onDestinationSelected: (idx) =>
                setState(() => _selectedTab = _navItems[idx].id),
            labelType: NavigationRailLabelType.all,
            destinations: _navItems
                .map((item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.icon),
                      label: Text(item.label),
                    ))
                .toList(),
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
    switch (_selectedTab) {
      case 'overview':
        return _buildOverviewTab();
      case 'scan':
        return _buildScanTab();
      case 'manufacturing':
        return const ManufacturerTools();
      case 'shipments':
        return _buildShipmentsTab();
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
            leading:
                const Icon(Icons.inventory_outlined, color: AppTheme.deepTeal),
            title: Text(shp['shipment_reference'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                "Declared: ${shp['declared_quantity']} units | Received: ${shp['received_quantity'] ?? 'Pending'} | Status: ${shp['status']}"),
            trailing: canReceive
                ? ElevatedButton(
                    onPressed: () => _receiveShipmentDialog(shp),
                    child: const Text("Receive Shipment"),
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
            trailing: Chip(
                label: Text(d['status']),
                backgroundColor: AppTheme.warningAmber.withValues(alpha: 0.2)),
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
            trailing: Chip(
                label: Text(a['review_status']),
                backgroundColor: AppTheme.errorRed.withValues(alpha: 0.1)),
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
