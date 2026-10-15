import 'package:flutter/material.dart';
import '../core/theme.dart';

class PackageVerificationCard extends StatelessWidget {
  final Map<String, dynamic> result;

  const PackageVerificationCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final isValid = result['is_valid'] == true;
    final verificationStatus = (result['verification_status'] as String?) ??
        (isValid ? 'VERIFIED' : 'INVALID_QR');
    final verificationReason = result['verification_reason'] as String?;
    final blockchainTxRef = result['blockchain_tx_ref'] as String?;
    final events = (result['recent_events'] as List<dynamic>?) ?? const [];

    Color statusColor;
    IconData statusIcon;

    switch (verificationStatus) {
      case 'VERIFIED':
        statusColor = AppTheme.successGreen;
        statusIcon = Icons.verified_outlined;
        break;
      case 'DUPLICATE_SCAN':
        statusColor = AppTheme.warningAmber;
        statusIcon = Icons.repeat;
        break;
      case 'CUSTODY_MISMATCH':
        statusColor = AppTheme.warningAmber;
        statusIcon = Icons.swap_horiz;
        break;
      case 'RECALLED':
      case 'EXPIRED':
      case 'INVALID_QR':
        statusColor = AppTheme.errorRed;
        statusIcon = Icons.gpp_bad_outlined;
        break;
      case 'QUARANTINED':
        statusColor = Colors.purple;
        statusIcon = Icons.pause_circle_outline;
        break;
      default:
        statusColor = AppTheme.navy;
        statusIcon = Icons.info_outline;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        verificationStatus.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      if (blockchainTxRef != null)
                        Text(
                          'Ledger: $blockchainTxRef',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.deepTeal),
                        ),
                    ],
                  ),
                ),
                if (result['status'] != null)
                  Chip(
                    label: Text(
                      result['status']
                          .toString()
                          .replaceAll('_', ' ')
                          .toUpperCase(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
            if (verificationReason != null &&
                verificationReason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: statusColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        verificationReason,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
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
