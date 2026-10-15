import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class ManufacturerTools extends StatefulWidget {
  final VoidCallback onVerifyBatch;
  final int initialTabIndex;

  const ManufacturerTools({
    super.key,
    required this.onVerifyBatch,
    this.initialTabIndex = 0,
  });

  @override
  State<ManufacturerTools> createState() => _ManufacturerToolsState();
}

class _ManufacturerToolsState extends State<ManufacturerTools> {
  List<dynamic> _products = [];
  List<dynamic> _batches = [];
  List<dynamic> _packages = [];
  List<dynamic> _generatedPackages = [];
  List<dynamic> _distributors = [];
  List<dynamic> _pendingReceipts = [];
  List<dynamic> _recalls = [];
  List<dynamic> _auditHistory = [];
  List<dynamic> _documents = [];
  List<dynamic> _notifications = [];
  Map<String, dynamic> _summary = {};
  Map<String, dynamic>? _manufacturer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        apiService.getManufacturerDashboard(),
        apiService.getProducts(),
        apiService.getPackages(),
      ]);
      if (!mounted) return;
      final dashboard = results[0] as Map<String, dynamic>;
      setState(() {
        _manufacturer = dashboard['manufacturer'] as Map<String, dynamic>?;
        _summary = Map<String, dynamic>.from(dashboard['summary'] as Map);
        _batches = dashboard['batches'] as List<dynamic>;
        _distributors = dashboard['distributors'] as List<dynamic>;
        _pendingReceipts = dashboard['pending_receipts'] as List<dynamic>;
        _recalls = dashboard['recalls'] as List<dynamic>;
        _auditHistory = dashboard['audit_history'] as List<dynamic>;
        _documents = dashboard['documents'] as List<dynamic>;
        _notifications = dashboard['notifications'] as List<dynamic>;
        _products = results[1] as List<dynamic>;
        _packages = results[2] as List<dynamic>;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load manufacturing data: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createProduct() async {
    final name = TextEditingController();
    final generic = TextEditingController();
    final code = TextEditingController();
    final form = TextEditingController();
    final strength = TextEditingController();
    final description = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Register product'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _input(name, 'Product name'),
                  _input(generic, 'Generic name'),
                  _input(code, 'Product code'),
                  _input(form, 'Dosage form'),
                  _input(strength, 'Strength'),
                  _input(description, 'Description (optional)',
                      required: false),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Register product'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await apiService.createProduct({
          'name': name.text.trim(),
          'generic_name': generic.text.trim(),
          'product_code': code.text.trim(),
          'dosage_form': form.text.trim(),
          'strength': strength.text.trim(),
          'description':
              description.text.trim().isEmpty ? null : description.text.trim(),
        });
        await _load();
      } catch (error) {
        if (mounted) _showError('Product registration failed: $error');
      }
    }
    name.dispose();
    generic.dispose();
    code.dispose();
    form.dispose();
    strength.dispose();
    description.dispose();
  }

  Future<void> _createBatch(Map<String, dynamic> product) async {
    final batchNumber = TextEditingController();
    final quantity = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var manufacturingDate = DateTime.now();
    var expiryDate = DateTime.now().add(const Duration(days: 365));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Create batch — ${product['name']}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _input(batchNumber, 'Batch number'),
                _input(quantity, 'Manufactured quantity', numeric: true),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: Text(
                            'Manufacturing date: ${_date(manufacturingDate)}')),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: manufacturingDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          setDialogState(() => manufacturingDate = selected);
                        }
                      },
                      child: const Text('Select'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: Text('Expiry date: ${_date(expiryDate)}')),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: expiryDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          setDialogState(() => expiryDate = selected);
                        }
                      },
                      child: const Text('Select'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Create batch'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await apiService.createBatch({
          'product_id': product['id'],
          'batch_number': batchNumber.text.trim(),
          'manufacturing_date': _date(manufacturingDate),
          'expiry_date': _date(expiryDate),
          'quantity_manufactured': int.parse(quantity.text.trim()),
        });
        await _load();
      } catch (error) {
        if (mounted) _showError('Batch creation failed: $error');
      }
    }
    batchNumber.dispose();
    quantity.dispose();
  }

  Future<void> _generateQr(Map<String, dynamic> batch) async {
    final count = TextEditingController(text: '10');
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Generate package QR codes — ${batch['batch_number']}'),
        content: Form(
          key: formKey,
          child:
              _input(count, 'Number of packages (maximum 500)', numeric: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Generate QR codes'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final packages = await apiService.generatePackages(
            batch['id'], int.parse(count.text.trim()));
        if (mounted) setState(() => _generatedPackages = packages);
        await _load();
      } catch (error) {
        if (mounted) _showError('QR code generation failed: $error');
      }
    }
    count.dispose();
  }

  Future<void> _dispatchBatch() async {
    final verifiedDistributors = _distributors
        .where((organization) => organization['is_verified'] == true)
        .toList();
    final availablePackages = _packages.where((package) {
      return package['status'] == 'manufactured' &&
          _batches.any((batch) => batch['id'] == package['batch_id']);
    }).toList();
    if (verifiedDistributors.isEmpty || availablePackages.isEmpty) {
      _showError(verifiedDistributors.isEmpty
          ? 'No verified distributors are available.'
          : 'No undispatched packages are available.');
      return;
    }

    String? selectedDistributorId = verifiedDistributors.first['id'].toString();
    final selectedSerials = <String>{};
    final notesController = TextEditingController();
    final selectedPackages = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Dispatch management'),
          content: SizedBox(
            width: 520,
            height: 500,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedDistributorId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Select distributor'),
                  items: verifiedDistributors
                      .map((organization) => DropdownMenuItem<String>(
                            value: organization['id'].toString(),
                            child: Text(organization['name'].toString()),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedDistributorId = value),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Select serialized packages to dispatch'),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: availablePackages.length,
                    itemBuilder: (context, index) {
                      final package = availablePackages[index];
                      final batch = _batches.firstWhere(
                        (batch) => batch['id'] == package['batch_id'],
                      );
                      final serial = package['package_serial_id'].toString();
                      return CheckboxListTile(
                        value: selectedSerials.contains(serial),
                        onChanged: (value) => setDialogState(() {
                          if (value == true) {
                            selectedSerials.add(serial);
                          } else {
                            selectedSerials.remove(serial);
                          }
                        }),
                        title: Text(serial),
                        subtitle: Text(
                          '${batch['product_name']} · Batch ${batch['batch_number']}',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                      labelText: 'Dispatch notes (optional)'),
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
              onPressed:
                  selectedSerials.isEmpty || selectedDistributorId == null
                      ? null
                      : () => Navigator.pop(
                            dialogContext,
                            selectedSerials.toList(growable: false),
                          ),
              child: Text('Dispatch ${selectedSerials.length} packages'),
            ),
          ],
        ),
      ),
    );
    final notes = notesController.text.trim();
    notesController.dispose();
    final distributorId = selectedDistributorId;
    if (selectedPackages == null || distributorId == null) return;

    try {
      final shipment = await apiService.createShipment(
        distributorId,
        selectedPackages,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${shipment['shipment_reference']} dispatched and recorded on the ledger.',
          ),
          backgroundColor: AppTheme.successGreen,
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) _showError('Dispatch failed: $error');
    }
  }

  Future<void> _initiateRecall() async {
    final activeBatches =
        _batches.where((batch) => batch['status'] != 'recalled').toList();
    if (activeBatches.isEmpty) {
      _showError('There are no active batches available to recall.');
      return;
    }
    String? selectedBatchId = activeBatches.first['id'].toString();
    var severity = 'mandatory';
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Initiate batch recall'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedBatchId,
                  decoration: const InputDecoration(labelText: 'Batch'),
                  items: activeBatches
                      .map((batch) => DropdownMenuItem<String>(
                            value: batch['id'].toString(),
                            child: Text(
                              '${batch['product_name']} · ${batch['batch_number']}',
                            ),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedBatchId = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: const [
                    DropdownMenuItem(
                        value: 'mandatory', child: Text('Mandatory')),
                    DropdownMenuItem(
                        value: 'precautionary', child: Text('Precautionary')),
                    DropdownMenuItem(
                        value: 'voluntary', child: Text('Voluntary')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => severity = value);
                  },
                ),
                TextFormField(
                  controller: reasonController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Recall reason'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Recall reason is required'
                      : null,
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
              child: const Text('Initiate recall'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    final batchId = selectedBatchId;
    if (confirmed != true || batchId == null) return;
    try {
      await apiService.initiateRecall(
        batchId: batchId,
        reason: reason,
        severity: severity,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Batch recall recorded and affected packages quarantined.'),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) _showError('Could not initiate recall: $error');
    }
  }

  Future<void> _uploadDocument() async {
    if (_batches.isEmpty) {
      _showError('Create a batch before uploading its documents.');
      return;
    }
    final batchId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select document batch'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: _batches
                .map((batch) => ListTile(
                      title: Text(batch['product_name'].toString()),
                      subtitle: Text('Batch ${batch['batch_number']}'),
                      onTap: () =>
                          Navigator.pop(dialogContext, batch['id'].toString()),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (batchId == null) return;

    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (selection.isEmpty) return;
      final file = selection.single;
      await apiService.uploadBatchDocument(batchId, file);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} uploaded securely.')),
      );
      await _load();
    } catch (error) {
      if (mounted) _showError('Document upload failed: $error');
    }
  }

  Future<void> _downloadDocument(Map<String, dynamic> document) async {
    try {
      final bytes = await apiService.downloadBatchDocument(
        document['id'].toString(),
      );
      await FilePicker.saveFile(
        fileName: document['original_filename'].toString(),
        bytes: Uint8List.fromList(bytes),
        mimeType: document['content_type'].toString(),
      );
    } catch (error) {
      if (mounted) _showError('Document download failed: $error');
    }
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Widget _input(
    TextEditingController controller,
    String label, {
    bool required = true,
    bool numeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return 'Required';
          }
          if (numeric && value != null) {
            final parsed = int.tryParse(value);
            if (parsed == null ||
                parsed <= 0 ||
                (label.contains('500') && parsed > 500)) {
              return label.contains('500')
                  ? 'Enter a number from 1 to 500'
                  : 'Enter a positive number';
            }
          }
          return null;
        },
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.errorRed),
    );
  }

  Widget _buildOverviewTab() {
    final stats = [
      ('Batches created', _summary['total_batches'] ?? 0, Icons.inventory_2),
      ('Batches dispatched', _summary['batches_dispatched'] ?? 0, Icons.outbox),
      (
        'Batches in transit',
        _summary['batches_in_transit'] ?? 0,
        Icons.local_shipping
      ),
      (
        'Recalled batches',
        _summary['recalled_batches'] ?? 0,
        Icons.warning_amber
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_manufacturer != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.factory_outlined),
              title: Text(_manufacturer!['name'].toString()),
              subtitle: Text(
                '${_manufacturer!['contact_email']} · License ${_manufacturer!['license_number']}',
              ),
              trailing: Chip(
                label: Text(_manufacturer!['is_verified'] == true
                    ? 'Verified'
                    : 'Pending verification'),
              ),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: stats
              .map((stat) => SizedBox(
                    width: 210,
                    child: Card(
                      child: ListTile(
                        leading: Icon(stat.$3, color: AppTheme.deepTeal),
                        title: Text(
                          stat.$2.toString(),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(stat.$1),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Text('Recent notifications',
            style: Theme.of(context).textTheme.titleMedium),
        if (_notifications.isEmpty)
          const Card(child: ListTile(title: Text('No current notifications.')))
        else
          ..._notifications.take(5).map((notification) => Card(
                child: ListTile(
                  leading: Icon(_notificationIcon(notification['type'])),
                  title: Text(notification['title'].toString()),
                  subtitle: Text(notification['message'].toString()),
                ),
              )),
      ],
    );
  }

  IconData _notificationIcon(dynamic type) {
    switch (type) {
      case 'pending_receipt':
        return Icons.hourglass_top;
      case 'suspicious_scan':
        return Icons.security;
      case 'expiry':
        return Icons.event_busy;
      case 'recall':
        return Icons.warning_amber;
      default:
        return Icons.notifications_outlined;
    }
  }

  Widget _buildCreateBatchTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_manufacturer != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.business),
              title: Text(_manufacturer!['name'].toString()),
              subtitle: Text(
                'Manufacturer details are taken from the verified organization profile · '
                '${_manufacturer!['contact_email']} · ${_manufacturer!['address']}',
              ),
            ),
          ),
        Row(
          children: [
            const Expanded(
              child: Text('Medicine products',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton.icon(
              onPressed: _createProduct,
              icon: const Icon(Icons.add),
              label: const Text('Add medicine'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_products.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Register the medicine name, generic name, product code, dosage form, and strength first.',
              ),
            ),
          ),
        ..._products.map((product) {
          final productBatches = _batches
              .where((batch) => batch['product_id'] == product['id'])
              .toList();
          return Card(
            child: ExpansionTile(
              title: Text(product['name'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${product['generic_name']} · ${product['strength']} · ${product['product_code']}',
              ),
              trailing: TextButton.icon(
                onPressed: () =>
                    _createBatch(Map<String, dynamic>.from(product)),
                icon: const Icon(Icons.add),
                label: const Text('Create batch'),
              ),
              children: productBatches.isEmpty
                  ? [const ListTile(title: Text('No batches created yet.'))]
                  : productBatches
                      .map((batch) => ListTile(
                            title: Text('Batch ${batch['batch_number']}'),
                            subtitle: Text(
                              'Manufactured ${batch['manufacturing_date']} · '
                              'Expires ${batch['expiry_date']} · '
                              'Quantity ${batch['quantity_manufactured']}',
                            ),
                            trailing: Text(batch['status'].toString()),
                          ))
                      .toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInventoryTab() {
    if (_batches.isEmpty) {
      return const Center(child: Text('No batches have been created.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _batches.length,
      itemBuilder: (context, index) {
        final batch = _batches[index];
        final packageCounts =
            Map<String, dynamic>.from(batch['package_counts'] as Map? ?? {});
        final packaged = packageCounts.values.fold<int>(
          0,
          (sum, value) => sum + (value as num).toInt(),
        );
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(
              '${batch['product_name']} · ${batch['batch_number']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Manufactured: ${batch['manufacturing_date']} · '
              'Expiry: ${batch['expiry_date']} · '
              'Units: ${batch['quantity_manufactured']} · '
              'QR packages: $packaged · '
              'In transit: ${packageCounts['in_transit'] ?? 0} · '
              'Recalled: ${packageCounts['recalled'] ?? 0}',
            ),
            isThreeLine: true,
            trailing: Chip(label: Text(batch['status'].toString())),
          ),
        );
      },
    );
  }

  Widget _buildQrTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Generate unique package identifiers linked to each registered batch.',
        ),
        const SizedBox(height: 12),
        ..._batches.map((batch) => Card(
              child: ListTile(
                title:
                    Text('${batch['product_name']} · ${batch['batch_number']}'),
                subtitle: Text(
                  'Batch quantity: ${batch['quantity_manufactured']} · '
                  'Status: ${batch['status']}',
                ),
                trailing: ElevatedButton.icon(
                  onPressed: batch['status'] == 'recalled'
                      ? null
                      : () => _generateQr(Map<String, dynamic>.from(batch)),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Generate QR'),
                ),
              ),
            )),
        if (_generatedPackages.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Generated package QR codes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _generatedPackages.map((package) {
              return SizedBox(
                width: 190,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        QrImageView(data: package['qr_code_data'], size: 140),
                        const SizedBox(height: 8),
                        SelectableText(package['package_serial_id'],
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildDistributorsTab() {
    if (_distributors.isEmpty) {
      return const Center(child: Text('No registered distributors found.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _distributors.length,
      itemBuilder: (context, index) {
        final distributor = _distributors[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(distributor['name'].toString()),
            subtitle: Text(
              '${distributor['contact_email']}\n'
              '${distributor['address']}\n'
              'License ${distributor['license_number']}',
            ),
            isThreeLine: true,
            trailing: Chip(
              label: Text(distributor['is_verified'] == true
                  ? 'Verified'
                  : 'Unverified'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDispatchTab() {
    final availableCount = _packages
        .where((package) => package['status'] == 'manufactured')
        .length;
    final verifiedDistributorCount = _distributors
        .where((organization) => organization['is_verified'] == true)
        .length;
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.outbox, size: 48),
              const SizedBox(height: 12),
              const Text('Dispatch Management',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '$availableCount serialized packages are available for dispatch '
                'to $verifiedDistributorCount verified distributors.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: availableCount == 0 || verifiedDistributorCount == 0
                    ? null
                    : _dispatchBatch,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Select distributor and dispatch'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Dispatch creates a shipment and records the hand-off in the ledger.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingReceiptsTab() {
    if (_pendingReceipts.isEmpty) {
      return const Center(child: Text('No dispatched batches await receipt.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingReceipts.length,
      itemBuilder: (context, index) {
        final shipment = _pendingReceipts[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.hourglass_top),
            title: Text(shipment['shipment_reference'].toString()),
            subtitle: Text(
              '${shipment['receiver_organization_name']} · '
              '${shipment['declared_quantity']} units · '
              '${shipment['status']} · '
              'Dispatched ${shipment['dispatch_timestamp'] ?? 'date unavailable'}',
            ),
            isThreeLine: true,
            trailing: const Chip(label: Text('Awaiting receipt')),
          ),
        );
      },
    );
  }

  Widget _buildRecallTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _initiateRecall,
              icon: const Icon(Icons.warning_amber),
              label: const Text('Initiate recall'),
            ),
          ),
        ),
        Expanded(
          child: _recalls.isEmpty
              ? const Center(
                  child: Text('No batch recalls have been recorded.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _recalls.length,
                  itemBuilder: (context, index) {
                    final recall = _recalls[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber),
                        title: Text('Batch ${recall['batch_number']}'),
                        subtitle: Text(
                          '${recall['severity']} · ${recall['affected_package_count']} '
                          'packages · ${recall['recall_reason']}',
                        ),
                        isThreeLine: true,
                        trailing:
                            Chip(label: Text(recall['status'].toString())),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAuditTab() {
    if (_auditHistory.isEmpty) {
      return const Center(child: Text('No batch audit activity recorded yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _auditHistory.length,
      itemBuilder: (context, index) {
        final event = _auditHistory[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: Text(event['description'].toString()),
            subtitle: Text(
              '${event['batch_number'] ?? ''} · '
              '${event['occurred_at'] ?? ''}'
              '${event['notes'] == null ? '' : '\n${event['notes']}'}'
              '${event['blockchain_tx_ref'] == null ? '' : '\nLedger: ${event['blockchain_tx_ref']}'}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _buildDocumentsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Quality certificates and test reports are stored privately off-chain.',
                ),
              ),
              ElevatedButton.icon(
                onPressed: _uploadDocument,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload document'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _documents.isEmpty
              ? const Center(child: Text('No batch documents uploaded.'))
              : ListView.builder(
                  itemCount: _documents.length,
                  itemBuilder: (context, index) {
                    final document =
                        Map<String, dynamic>.from(_documents[index] as Map);
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(document['original_filename'].toString()),
                        subtitle: Text(
                          'Batch ${document['batch_number']} · '
                          '${(document['file_size'] as num) / 1024} KB · '
                          '${document['created_at']}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Download document',
                          onPressed: () => _downloadDocument(document),
                          icon: const Icon(Icons.download_outlined),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNotificationsTab() {
    if (_notifications.isEmpty) {
      return const Center(child: Text('No current notifications.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return Card(
          child: ListTile(
            leading: Icon(_notificationIcon(notification['type'])),
            title: Text(notification['title'].toString()),
            subtitle: Text(
              '${notification['message']}\n${notification['created_at'] ?? ''}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    const tabs = [
      Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
      Tab(text: 'Create New Batch', icon: Icon(Icons.add_box_outlined)),
      Tab(text: 'Generate QR Code', icon: Icon(Icons.qr_code_2)),
      Tab(text: 'Batch Inventory', icon: Icon(Icons.inventory_2_outlined)),
      Tab(text: 'Distributors', icon: Icon(Icons.local_shipping_outlined)),
      Tab(text: 'Dispatch Management', icon: Icon(Icons.outbox_outlined)),
      Tab(text: 'Pending Receipts', icon: Icon(Icons.hourglass_top)),
      Tab(text: 'Batch Verification', icon: Icon(Icons.qr_code_scanner)),
      Tab(text: 'Recall Management', icon: Icon(Icons.warning_amber_outlined)),
      Tab(text: 'Audit History', icon: Icon(Icons.history)),
      Tab(text: 'Document Management', icon: Icon(Icons.description_outlined)),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Manufacturer dashboard',
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
                _buildCreateBatchTab(),
                _buildQrTab(),
                _buildInventoryTab(),
                _buildDistributorsTab(),
                _buildDispatchTab(),
                _buildPendingReceiptsTab(),
                Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.qr_code_scanner, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Scan a package QR code to verify its batch registration and current status.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: widget.onVerifyBatch,
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Open batch verification'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildRecallTab(),
                _buildAuditTab(),
                _buildDocumentsTab(),
                _buildNotificationsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
