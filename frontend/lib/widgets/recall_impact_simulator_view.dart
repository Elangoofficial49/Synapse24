import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class RecallImpactSimulatorView extends StatefulWidget {
  final String batchId;
  final String? batchNumber;
  final VoidCallback? onBack;

  const RecallImpactSimulatorView({
    super.key,
    required this.batchId,
    this.batchNumber,
    this.onBack,
  });

  static Future<void> show(BuildContext context,
      {required String batchId, String? batchNumber}) {
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
          child: RecallImpactSimulatorView(
            batchId: batchId,
            batchNumber: batchNumber,
            onBack: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }

  @override
  State<RecallImpactSimulatorView> createState() =>
      _RecallImpactSimulatorViewState();
}

class _RecallImpactSimulatorViewState extends State<RecallImpactSimulatorView> {
  bool _loading = true;
  Map<String, dynamic>? _impactData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImpact();
  }

  Future<void> _loadImpact() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await apiService.getRecallImpact(widget.batchId);
      if (mounted) setState(() => _impactData = res);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
            const SizedBox(height: 12),
            Text('Failed to simulate recall impact: $_error'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadImpact, child: const Text('Retry')),
          ],
        ),
      );
    }

    final data = _impactData!;
    final quantities =
        Map<String, dynamic>.from(data['quantities'] as Map? ?? {});
    final distributors = (data['distributors'] as List<dynamic>?) ?? [];
    final pharmacies = (data['pharmacies'] as List<dynamic>?) ?? [];
    final acks = (data['acknowledgements'] as List<dynamic>?) ?? [];
    final unresponded =
        (data['unresponded_organizations'] as List<dynamic>?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            if (widget.onBack != null)
              IconButton(
                  onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recall Impact Simulator · Batch ${data['batch_number'] ?? widget.batchNumber}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.navy),
                  ),
                  Text(
                      'Product: ${data['product_name'] ?? 'Pharmaceutical Unit'} | Manufacturer: ${data['manufacturer_name'] ?? 'Authorized Pharma'}'),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loadImpact,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Tree'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Quantities Breakdown Card
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard('Manufactured', '${quantities['manufactured'] ?? 0}',
                Icons.factory_outlined, AppTheme.navy),
            _metricCard('Serialized Units', '${quantities['serialized'] ?? 0}',
                Icons.qr_code_2, AppTheme.deepTeal),
            _metricCard(
                'Quarantined / Recovered',
                '${quantities['quarantined'] ?? 0}',
                Icons.gpp_bad_outlined,
                AppTheme.errorRed),
            _metricCard(
                'Unresolved In Circulation',
                '${quantities['unresolved'] ?? 0}',
                Icons.warning_amber_rounded,
                AppTheme.warningAmber),
          ],
        ),
        const SizedBox(height: 24),
        if (data['is_recalled'] == true)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.errorRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, color: AppTheme.errorRed, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACTIVE RECALL (${data['severity']?.toString().toUpperCase() ?? 'MANDATORY'})',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.errorRed),
                      ),
                      Text(
                          'Reason: ${data['recall_reason'] ?? 'Safety directive'}'),
                      Text('Initiated At: ${data['initiated_at'] ?? 'N/A'}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const Text('Downstream Supply-Chain Traceability Flow',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 4),
        const Text(
            'Connected node flow tracing distribution handoffs from manufacturer to distributors and pharmacies.'),
        const SizedBox(height: 16),

        // Node Flow visualization
        _buildFlowNode(
          icon: Icons.factory,
          title: 'Manufacturer',
          subtitle: data['manufacturer_name'] ?? 'Production Facility',
          badge: 'BATCH ORIGIN',
          color: AppTheme.navy,
        ),
        _buildConnector(),
        _buildFlowNode(
          icon: Icons.local_shipping,
          title: 'Distributor Hand-off (${distributors.length} partners)',
          subtitle: distributors.isEmpty
              ? 'No downstream distributor dispatches recorded'
              : distributors
                  .map((d) =>
                      '${d['name']} (${d['received_qty']}/${d['dispatched_qty']} units)')
                  .join('\n'),
          badge: distributors.isEmpty ? 'NONE' : 'RECORDED IN TRANSIT',
          color: AppTheme.deepTeal,
        ),
        _buildConnector(),
        _buildFlowNode(
          icon: Icons.local_pharmacy,
          title: 'Pharmacy Endpoints (${pharmacies.length} locations)',
          subtitle: pharmacies.isEmpty
              ? 'No pharmacy consignments dispatched yet'
              : pharmacies
                  .map((p) =>
                      '${p['name']} (${p['received_qty']}/${p['dispatched_qty']} units)')
                  .join('\n'),
          badge: pharmacies.isEmpty ? 'NONE' : 'REACHED ENDPOINT',
          color: AppTheme.deepTeal,
        ),
        const SizedBox(height: 24),

        // Unresponded Organizations Card
        if (unresponded.isNotEmpty)
          Card(
            color: AppTheme.warningAmber.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active_outlined,
                          color: AppTheme.warningAmber),
                      const SizedBox(width: 8),
                      Text(
                        'Outstanding Quarantine Confirmations (${unresponded.length} pending)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warningAmber),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'The following downstream organizations have not submitted their recall quarantine acknowledgement:'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: unresponded
                        .map((name) => Chip(
                              label: Text(name.toString()),
                              backgroundColor: Colors.white,
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),

        // Acknowledgements List
        const Text('Downstream Acknowledgements & Quarantine Submissions',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 8),
        if (acks.isEmpty)
          const Card(
              child: ListTile(
                  title: Text(
                      'No organizations have acknowledged this recall yet.')))
        else
          ...acks.map((ack) => Card(
                child: ListTile(
                  leading:
                      const Icon(Icons.verified, color: AppTheme.successGreen),
                  title: Text(
                      '${ack['organization_name']} · Quarantined ${ack['quarantined_quantity']} units'),
                  subtitle: Text(
                      'Acknowledged: ${ack['acknowledged_at']}\nNotes: ${ack['notes'] ?? 'None'} | Tx: ${ack['tx_ref'] ?? 'Pending'}'),
                ),
              )),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return SizedBox(
      width: 220,
      child: Card(
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          subtitle: Text(label),
        ),
      ),
    );
  }

  Widget _buildFlowNode({
    required IconData icon,
    required String title,
    required String subtitle,
    required String badge,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              radius: 24,
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      Chip(
                        label: Text(badge,
                            style: TextStyle(
                                fontSize: 10,
                                color: color,
                                fontWeight: FontWeight.bold)),
                        backgroundColor: color.withValues(alpha: 0.1),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnector() {
    return Center(
      child: Container(
        height: 24,
        width: 2,
        color: AppTheme.deepTeal.withValues(alpha: 0.5),
      ),
    );
  }
}
