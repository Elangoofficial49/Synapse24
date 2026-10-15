import 'package:flutter/material.dart';
import '../core/theme.dart';

class PackageVerificationCard extends StatelessWidget {
  final Map<String, dynamic> result;

  const PackageVerificationCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final isValid = result['is_valid'] == true;
    final warning = result['warning_message'] as String?;
    final events = (result['recent_events'] as List<dynamic>?) ?? const [];
    final accent = isValid ? AppTheme.successGreen : AppTheme.errorRed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isValid ? Icons.verified_outlined : Icons.error_outline,
                    color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isValid ? 'Verified package' : 'Package not verified',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: accent),
                  ),
                ),
                if (result['status'] != null)
                  Chip(
                      label: Text(result['status']
                          .toString()
                          .replaceAll('_', ' ')
                          .toUpperCase())),
              ],
            ),
            if (warning != null && warning.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(warning,
                    style: const TextStyle(
                        color: AppTheme.errorRed, fontWeight: FontWeight.w600)),
              ),
            ],
            if (isValid) ...[
              const SizedBox(height: 16),
              _detail('Serial ID', result['package_serial_id']),
              _detail('Product', result['product_name']),
              _detail('Generic name', result['generic_name']),
              _detail('Product code', result['product_code']),
              _detail('Form / strength',
                  '${result['dosage_form'] ?? '—'} / ${result['strength'] ?? '—'}'),
              _detail('Manufacturer', result['manufacturer_name']),
              _detail('Batch', result['batch_number']),
              _detail('Manufactured', result['manufacturing_date']),
              _detail('Expires', result['expiry_date']),
              _detail('Current custodian', result['current_custodian']),
              if (result['description'] != null &&
                  result['description'].toString().isNotEmpty)
                _detail('Description', result['description']),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Text('Custody tracking (${events.length} events)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              if (events.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('No custody events have been recorded yet.'),
                )
              else
                ...events.map((event) => _event(event as Map<String, dynamic>)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 150,
              child: Text(label,
                  style: const TextStyle(color: AppTheme.textSecondary))),
          Expanded(
              child: Text(value.toString(),
                  style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _event(Map<String, dynamic> event) {
    final route = [
      event['from_organization'],
      event['to_organization'],
    ].whereType<String>().where((name) => name.isNotEmpty).join(' → ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.route_outlined, color: AppTheme.deepTeal),
      title: Text(
          event['event_type']?.toString().replaceAll('_', ' ').toUpperCase() ??
              'CUSTODY UPDATE'),
      subtitle: Text([
        if (route.isNotEmpty) route,
        if (event['shipment_reference'] != null)
          'Shipment ${event['shipment_reference']}',
        if (event['quantity'] != null) 'Quantity: ${event['quantity']}',
        if (event['timestamp'] != null) event['timestamp'].toString(),
        if (event['notes'] != null && event['notes'].toString().isNotEmpty)
          event['notes'].toString(),
        event['is_on_chain'] == true
            ? 'Blockchain confirmed'
            : 'Ledger recorded',
      ].join('\n')),
      isThreeLine: true,
    );
  }
}
