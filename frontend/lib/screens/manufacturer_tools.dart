import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class ManufacturerTools extends StatefulWidget {
  const ManufacturerTools({super.key});

  @override
  State<ManufacturerTools> createState() => _ManufacturerToolsState();
}

class _ManufacturerToolsState extends State<ManufacturerTools> {
  List<dynamic> _products = [];
  List<dynamic> _batches = [];
  List<dynamic> _generatedPackages = [];
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
        apiService.getProducts(),
        apiService.getBatches(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0];
        _batches = results[1];
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Manufacturing & QR codes',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.navy)),
            ),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
                onPressed: _createProduct,
                icon: const Icon(Icons.add),
                label: const Text('Register product')),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              if (_products.isEmpty)
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                            'Register a product first, then create its batch and package QR codes.'))),
              ..._products.map((product) {
                final productBatches = _batches
                    .where((batch) => batch['product_id'] == product['id'])
                    .toList();
                return Card(
                  child: ExpansionTile(
                    title: Text(product['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${product['generic_name']} · ${product['strength']} · ${product['product_code']}'),
                    trailing: TextButton.icon(
                      onPressed: () =>
                          _createBatch(Map<String, dynamic>.from(product)),
                      icon: const Icon(Icons.add),
                      label: const Text('New batch'),
                    ),
                    children: productBatches.isEmpty
                        ? [const ListTile(title: Text('No batches yet'))]
                        : productBatches
                            .map((batch) => ListTile(
                                  leading: const Icon(
                                      Icons.inventory_2_outlined,
                                      color: AppTheme.deepTeal),
                                  title: Text('Batch ${batch['batch_number']}'),
                                  subtitle: Text(
                                      'Quantity: ${batch['quantity_manufactured']} · Expires: ${batch['expiry_date']} · Status: ${batch['status']}'),
                                  trailing: ElevatedButton.icon(
                                    onPressed: () => _generateQr(
                                        Map<String, dynamic>.from(batch)),
                                    icon: const Icon(Icons.qr_code_2),
                                    label: const Text('Generate QR codes'),
                                  ),
                                ))
                            .toList(),
                  ),
                );
              }),
              if (_generatedPackages.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 20, bottom: 8),
                  child: Text('Generated package QR codes',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
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
                              QrImageView(
                                  data: package['qr_code_data'], size: 140),
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
          ),
        ),
      ],
    );
  }
}
