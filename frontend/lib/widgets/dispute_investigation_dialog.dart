import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class DisputeInvestigationDialog extends StatefulWidget {
  final Map<String, dynamic> dispute;
  final VoidCallback onResolved;

  const DisputeInvestigationDialog({
    super.key,
    required this.dispute,
    required this.onResolved,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> dispute,
    required VoidCallback onUpdated,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) =>
          DisputeInvestigationDialog(dispute: dispute, onResolved: onUpdated),
    );
  }

  @override
  State<DisputeInvestigationDialog> createState() =>
      _DisputeInvestigationDialogState();
}

class _DisputeInvestigationDialogState
    extends State<DisputeInvestigationDialog> {
  late String _status;
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _evidenceRefController = TextEditingController();
  final TextEditingController _evidenceHashController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.dispute['status']?.toString().toLowerCase() ??
        'under_investigation';
    _evidenceRefController.text =
        widget.dispute['evidence_reference']?.toString() ?? '';
    _evidenceHashController.text =
        widget.dispute['evidence_hash']?.toString() ?? '';
  }

  @override
  void dispose() {
    _commentController.dispose();
    _evidenceRefController.dispose();
    _evidenceHashController.dispose();
    super.dispose();
  }

  Future<void> _submitUpdate() async {
    setState(() => _saving = true);
    try {
      await apiService.updateDisputeInvestigation(
        widget.dispute['id'].toString(),
        status: _status,
        comments: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
        evidenceHash: _evidenceHashController.text.trim().isEmpty
            ? null
            : _evidenceHashController.text.trim(),
        evidenceReference: _evidenceRefController.text.trim().isEmpty
            ? null
            : _evidenceRefController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Discrepancy investigation updated with audit trail.'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        widget.onResolved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update investigation: $e'),
              backgroundColor: AppTheme.errorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expected = widget.dispute['expected_quantity'] ?? 0;
    final actual = widget.dispute['actual_quantity'] ?? 0;
    final discrepancy = (expected as num) - (actual as num);

    return AlertDialog(
      title: Text(
          'Investigate Discrepancy · ${widget.dispute['shipment_reference'] ?? 'Shipment'}'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warningAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.warningAmber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Dispatched: $expected units',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Received: $actual units',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          'Discrepancy: $discrepancy units',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.errorRed),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                        'Reported Reason: ${widget.dispute['dispute_reason'] ?? 'Not specified'}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration:
                    const InputDecoration(labelText: 'Investigation Status'),
                items: const [
                  DropdownMenuItem(
                      value: 'open', child: Text('Open / Pending Review')),
                  DropdownMenuItem(
                      value: 'under_investigation',
                      child: Text('Under Investigation')),
                  DropdownMenuItem(
                      value: 'resolved',
                      child: Text('Resolved (Correction Confirmed)')),
                  DropdownMenuItem(
                      value: 'escalated',
                      child: Text('Escalated to Regulatory Authority')),
                ],
                onChanged: (val) => setState(() => _status = val ?? _status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _evidenceRefController,
                decoration: const InputDecoration(
                  labelText: 'Evidence Document Reference / URL',
                  hintText: 'e.g. DocRef-BOL-89241.pdf',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _evidenceHashController,
                decoration: const InputDecoration(
                  labelText: 'Evidence SHA-256 Hash',
                  hintText:
                      'e.g. e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Investigation Comments & Party Submissions',
                  hintText:
                      'Enter notes from carrier reconciliation, physical count audit, or resolution rationale.',
                ),
              ),
              if (widget.dispute['resolution_notes'] != null &&
                  widget.dispute['resolution_notes'].toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Audit Discussion History:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(widget.dispute['resolution_notes'].toString()),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _submitUpdate,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save Investigation Update'),
        ),
      ],
    );
  }
}
