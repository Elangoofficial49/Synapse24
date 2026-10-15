import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../widgets/recall_impact_simulator_view.dart';

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

class _ManufacturerToolsState extends State<ManufacturerTools>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
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
    _tabController = TabController(
      length: 12,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 11),
    );
    _load();
  }

  @override
  void didUpdateWidget(ManufacturerTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      final target = widget.initialTabIndex.clamp(0, 11);
      if (_tabController.index != target) {
        _tabController.animateTo(target);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      final rawBatches =
          List<dynamic>.from(dashboard['batches'] as List? ?? []);
      final rawReceipts =
          List<dynamic>.from(dashboard['pending_receipts'] as List? ?? []);
      final rawRecalls =
          List<dynamic>.from(dashboard['recalls'] as List? ?? []);
      final rawAudit =
          List<dynamic>.from(dashboard['audit_history'] as List? ?? []);
      final rawDocs = List<dynamic>.from(dashboard['documents'] as List? ?? []);
      final rawNotifs =
          List<dynamic>.from(dashboard['notifications'] as List? ?? []);
      final rawProducts = List<dynamic>.from(results[1] as List? ?? []);
      final rawPackages = List<dynamic>.from(results[2] as List? ?? []);

      int compareDesc(dynamic a, dynamic b) {
        final aTime = (a['created_at'] ??
                a['manufacturing_date'] ??
                a['dispatch_timestamp'] ??
                '')
            .toString();
        final bTime = (b['created_at'] ??
                b['manufacturing_date'] ??
                b['dispatch_timestamp'] ??
                '')
            .toString();
        return bTime.compareTo(aTime);
      }

      rawBatches.sort(compareDesc);
      rawProducts.sort(compareDesc);
      rawPackages.sort(compareDesc);
      rawReceipts.sort(compareDesc);
      rawRecalls.sort(compareDesc);
      rawAudit.sort(compareDesc);
      rawNotifs.sort(compareDesc);

      setState(() {
        _manufacturer = dashboard['manufacturer'] as Map<String, dynamic>?;
        _summary = Map<String, dynamic>.from(dashboard['summary'] as Map);
        _batches = rawBatches;
        _distributors = dashboard['distributors'] as List<dynamic>;
        _pendingReceipts = rawReceipts;
        _recalls = rawRecalls;
        _auditHistory = rawAudit;
        _documents = rawDocs;
        _notifications = rawNotifs;
        _products = rawProducts;
        _packages = rawPackages;
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
        if (mounted) {
          _tabController.animateTo(1);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Medicine registered. Proceed to create a batch.'),
              backgroundColor: AppTheme.successGreen,
            ),
          );
        }
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
        if (mounted) {
          _tabController.animateTo(2);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Batch created successfully. Proceed to generate QR codes.'),
              backgroundColor: AppTheme.successGreen,
            ),
          );
        }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${packages.length} QR codes generated. You can now dispatch packages.'),
              backgroundColor: AppTheme.successGreen,
              action: SnackBarAction(
                label: 'Go to Dispatch',
                textColor: Colors.white,
                onPressed: () => _tabController.animateTo(5),
              ),
            ),
          );
          await _showGeneratedQrDialog(batch, packages);
        }
      } catch (error) {
        String msg = error.toString();
        if (error is DioException && error.response?.data is Map) {
          final detail = error.response!.data['detail'];
          if (detail != null) msg = detail.toString();
        }
        if (mounted) _showError('QR code generation failed: $msg');
      }
    }
    count.dispose();
  }

  Future<void> _showGeneratedQrDialog(
    Map<String, dynamic> batch,
    List<dynamic> packages,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0x1A0D3B66),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.qr_code_2, color: AppTheme.navy, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generated QR Codes (${packages.length})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text(
                      'Product: ${batch['product_name']} · Batch: ${batch['batch_number']}',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 720,
            height: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: Color(0xFF16A34A), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${packages.length} serialized package QR codes generated successfully and registered to ledger. '
                          'Ready for physical labeling and distributor dispatch.',
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF166534)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: packages.map((package) {
                          final serial =
                              package['package_serial_id']?.toString() ?? '';
                          final qrData =
                              package['qr_code_data']?.toString() ?? serial;
                          final status =
                              package['status']?.toString() ?? 'manufactured';

                          return Container(
                            width: 215,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0A000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: QrImageView(
                                    data: qrData,
                                    size: 140,
                                    version: QrVersions.auto,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  serial,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: AppTheme.navy,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F2F1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00796B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.deepTeal,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                _tabController.animateTo(5); // Go to Dispatch Management
              },
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: const Text('Proceed to Dispatch Management'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _dispatchBatch() async {
    final verifiedDistributors = _distributors
        .where((organization) => organization['is_verified'] == true)
        .toList();
    if (verifiedDistributors.isEmpty) {
      _showError(
          'No verified distributors are available. Please onboard a distributor first.');
      _tabController.animateTo(4); // Go to Distributors tab
      return;
    }
    final availablePackages = _packages.where((package) {
      return package['status'] == 'manufactured' &&
          _batches.any((batch) => batch['id'] == package['batch_id']);
    }).toList();

    String? selectedDistributorId = verifiedDistributors.first['id'].toString();
    final selectedSerials = <String>{};
    final notesController = TextEditingController();

    // Group available packages by batch
    final Map<String, List<dynamic>> packagesByBatch = {};
    for (final package in availablePackages) {
      final batch = _batches.firstWhere(
        (b) => b['id'] == package['batch_id'],
        orElse: () => {'batch_number': 'Unknown', 'product_name': 'Unknown'},
      );
      final batchKey =
          '${batch['product_name']} · Batch ${batch['batch_number']}';
      packagesByBatch.putIfAbsent(batchKey, () => []).add(package);
    }

    final selectedPackages = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allSerials = availablePackages
              .map((p) => p['package_serial_id'].toString())
              .toSet();
          final isAllSelected = selectedSerials.length == allSerials.length &&
              allSerials.isNotEmpty;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: AppTheme.deepTeal),
                SizedBox(width: 8),
                Text('Dispatch Management — Manufacturer to Distributor'),
              ],
            ),
            content: SizedBox(
              width: 580,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedDistributorId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Select Verified Recipient Distributor',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    items: verifiedDistributors
                        .map((organization) => DropdownMenuItem<String>(
                              value: organization['id'].toString(),
                              child: Text(
                                '${organization['name']} (${organization['license_number'] ?? 'Verified'})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedDistributorId = value),
                  ),
                  const SizedBox(height: 12),
                  if (availablePackages.isEmpty) ...[
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppTheme.warningAmber
                                    .withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inventory_2_outlined,
                                  size: 48, color: AppTheme.warningAmber),
                              const SizedBox(height: 12),
                              const Text(
                                'No manufactured packages available to dispatch',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.navy),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'All registered batches have already been dispatched or need QR packages generated. '
                                'Please create a batch and generate QR codes to prepare stock for dispatch.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  _tabController
                                      .animateTo(2); // Go to Generate QR Code
                                },
                                icon: const Icon(Icons.qr_code_2),
                                label: const Text('Go to Generate QR Codes'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select packages (${selectedSerials.length}/${availablePackages.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              if (isAllSelected) {
                                selectedSerials.clear();
                              } else {
                                selectedSerials.addAll(allSerials);
                              }
                            });
                          },
                          icon: Icon(
                            isAllSelected
                                ? Icons.deselect_outlined
                                : Icons.select_all_outlined,
                            size: 18,
                          ),
                          label: Text(
                              isAllSelected ? 'Deselect All' : 'Select All'),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        children: packagesByBatch.entries.map((entry) {
                          final batchLabel = entry.key;
                          final batchPackages = entry.value;
                          final batchSerials = batchPackages
                              .map((p) => p['package_serial_id'].toString())
                              .toSet();
                          final isBatchAllSelected = batchSerials.every(
                            (s) => selectedSerials.contains(s),
                          );

                          return Container(
                            margin: const EdgeInsets.only(top: 8, bottom: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.border),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey.withValues(alpha: 0.03),
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: true,
                              dense: true,
                              title: Text(
                                batchLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppTheme.navy,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      setDialogState(() {
                                        if (isBatchAllSelected) {
                                          selectedSerials
                                              .removeAll(batchSerials);
                                        } else {
                                          selectedSerials.addAll(batchSerials);
                                        }
                                      });
                                    },
                                    child: Text(
                                      isBatchAllSelected
                                          ? 'Deselect Batch'
                                          : 'Select Batch (${batchPackages.length})',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const Icon(Icons.expand_more, size: 20),
                                ],
                              ),
                              children: batchPackages.map((package) {
                                final serial =
                                    package['package_serial_id'].toString();
                                return CheckboxListTile(
                                  dense: true,
                                  value: selectedSerials.contains(serial),
                                  onChanged: (value) => setDialogState(() {
                                    if (value == true) {
                                      selectedSerials.add(serial);
                                    } else {
                                      selectedSerials.remove(serial);
                                    }
                                  }),
                                  title: Text(serial,
                                      style: const TextStyle(fontSize: 13)),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              }).toList(),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                          labelText: 'Dispatch notes (optional)'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              if (availablePackages.isNotEmpty)
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
          );
        },
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
      if (mounted) {
        _tabController.animateTo(6);
      }
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
    final displayPackages = _generatedPackages.isNotEmpty
        ? _generatedPackages
        : _packages.take(24).toList();

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
        if (displayPackages.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code_2, color: AppTheme.navy, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    _generatedPackages.isNotEmpty
                        ? 'Recently Generated QR Codes (${_generatedPackages.length})'
                        : 'Batch QR Code Inventory (${_packages.length} packages)',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.navy),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.deepTeal,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _tabController.animateTo(5), // Go to Dispatch
                icon: const Icon(Icons.send_outlined, size: 16),
                label: const Text('Go to Dispatch Management'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: displayPackages.map((package) {
              final serial = package['package_serial_id']?.toString() ?? '';
              final qrData = package['qr_code_data']?.toString() ?? serial;
              final status = package['status']?.toString() ?? 'manufactured';
              return SizedBox(
                width: 200,
                child: Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: QrImageView(
                            data: qrData,
                            size: 140,
                            version: QrVersions.auto,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          serial,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Chip(
                          label: Text(
                            status,
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                          backgroundColor: status == 'manufactured'
                              ? const Color(0xFFE0F2F1)
                              : const Color(0xFFF1F5F9),
                          visualDensity: VisualDensity.compact,
                        ),
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

  Future<void> _onboardDistributorDialog() async {
    final nameController = TextEditingController();
    final licenseController = TextEditingController();
    final addressController = TextEditingController();
    final emailController = TextEditingController();
    final otpController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    bool otpSent = false;
    bool otpSending = false;
    String? otpFeedback;
    String? demoOtpCode;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> sendOtp() async {
            final email = emailController.text.trim().toLowerCase();
            if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
              setDialogState(() {
                otpFeedback = 'Enter a valid authorized contact email first.';
              });
              return;
            }
            setDialogState(() {
              otpSending = true;
              otpFeedback = null;
            });
            try {
              final res = await apiService.sendDistributorOtp(email);
              setDialogState(() {
                otpSent = true;
                demoOtpCode = res['demo_code']?.toString();
                if (res['email_delivered'] == true) {
                  otpFeedback = '6-digit OTP code sent to $email.';
                } else if (demoOtpCode != null) {
                  otpFeedback =
                      'Verification OTP: $demoOtpCode (Test Demo Mode)';
                } else {
                  otpFeedback = 'Verification code dispatched to $email.';
                }
              });
            } catch (err) {
              setDialogState(() {
                otpFeedback = 'Failed to dispatch OTP: $err';
              });
            } finally {
              setDialogState(() {
                otpSending = false;
              });
            }
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.verified_user_outlined, color: AppTheme.deepTeal),
                SizedBox(width: 8),
                Text('Verify & Onboard New Distributor'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Verify a registered distributor profile by sending an OTP to their registered authorized contact email. Once verified, the distributor account is linked and orders dispatched to them will appear on their dashboard.',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Distributor Organization Name',
                          hintText: 'e.g. FastDist Global Logistics',
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Enter distributor name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: licenseController,
                        decoration: const InputDecoration(
                          labelText: 'Regulatory Wholesale Drug License Number',
                          hintText: 'e.g. DIST-2024-9981 or WDL-4482',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Enter regulatory license number';
                          }
                          if (val.trim().length < 5) {
                            return 'License number must be at least 5 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(
                          labelText: 'Official Warehouse / Hub Address',
                          hintText: 'e.g. 500 Logistics Blvd, Warehouse Bay 4',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Enter verified warehouse address'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Authorized Contact Email',
                                hintText: 'e.g. distributor@pharmatrace.dev',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter authorized contact email';
                                }
                                if (!val.contains('@') || !val.contains('.')) {
                                  return 'Enter a valid email address';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                              ),
                              onPressed: otpSending ? null : sendOtp,
                              icon: otpSending
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Icon(otpSent ? Icons.refresh : Icons.send,
                                      size: 16),
                              label: Text(otpSent ? 'Resend' : 'Send OTP'),
                            ),
                          ),
                        ],
                      ),
                      if (otpFeedback != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 16, color: AppTheme.navy),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  otpFeedback!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.navy),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (otpSent) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Enter 6-Digit Email OTP',
                            hintText: 'e.g. 123456',
                            prefixIcon: Icon(Icons.security),
                            helperText:
                                'Verification code sent to distributor registered email',
                          ),
                          validator: (val) {
                            if (val == null || val.trim().length != 6) {
                              return 'Enter 6-digit verification code';
                            }
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(ctx, true);
                  }
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Verify & Confirm Distributor'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      try {
        final newDistributor = await apiService.onboardDistributor(
          name: nameController.text.trim(),
          licenseNumber: licenseController.text.trim().toUpperCase(),
          address: addressController.text.trim(),
          contactEmail: emailController.text.trim().toLowerCase(),
          otpCode: otpController.text.trim().isNotEmpty
              ? otpController.text.trim()
              : null,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Distributor "${newDistributor['name']}" verified successfully via OTP. Account linked and ready for dispatch!',
            ),
            backgroundColor: AppTheme.successGreen,
          ),
        );
        await _load();
      } catch (e) {
        String errDetail =
            'Verification failed. Please check the entered details or OTP code.';
        if (mounted) _showError('Distributor verification: $errDetail');
      }
    }
    nameController.dispose();
    licenseController.dispose();
    addressController.dispose();
    emailController.dispose();
    otpController.dispose();
  }

  Widget _buildDistributorsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verified Distributor Network',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.navy),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_distributors.length} licensed distributors authorized for batch dispatch and transit.',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _onboardDistributorDialog,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Verify New Distributor'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_distributors.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                    'No verified distributors registered. Click "Verify New Distributor" above to add one.'),
              ),
            ),
          )
        else
          ..._distributors.map((distributor) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2F1),
                    child: Icon(Icons.local_shipping_outlined,
                        color: AppTheme.deepTeal),
                  ),
                  title: Text(distributor['name'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Contact: ${distributor['contact_email']}\n'
                    'Warehouse: ${distributor['address']}\n'
                    'License: ${distributor['license_number']} · State Board Verified',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(
                            distributor['is_verified'] == true
                                ? 'Verified Partner'
                                : 'Unverified',
                            style: TextStyle(
                                color: distributor['is_verified'] == true
                                    ? AppTheme.successGreen
                                    : AppTheme.warningAmber)),
                        avatar: Icon(
                            distributor['is_verified'] == true
                                ? Icons.verified
                                : Icons.hourglass_top,
                            size: 18,
                            color: distributor['is_verified'] == true
                                ? AppTheme.successGreen
                                : AppTheme.warningAmber),
                        backgroundColor: distributor['is_verified'] == true
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFFBEB),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Dispatch batch to this distributor',
                        icon: const Icon(Icons.send_outlined,
                            color: AppTheme.deepTeal),
                        onPressed: () {
                          _tabController
                              .animateTo(5); // Navigate to Dispatch Management
                        },
                      ),
                    ],
                  ),
                ),
              )),
      ],
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
                onPressed: _dispatchBatch,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  if (_batches.isEmpty) return;
                  _showRecallSimulatorDialog(_batches.first['id'].toString(),
                      _batches.first['batch_number']?.toString());
                },
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Recall Impact Simulator'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorRed),
                onPressed: _initiateRecall,
                icon: const Icon(Icons.warning_amber),
                label: const Text('Initiate recall'),
              ),
            ],
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
                        leading: const Icon(Icons.warning_amber,
                            color: AppTheme.errorRed),
                        title: Text('Batch ${recall['batch_number']}'),
                        subtitle: Text(
                          '${recall['severity']} · ${recall['affected_package_count']} '
                          'packages · ${recall['recall_reason']}',
                        ),
                        isThreeLine: true,
                        trailing: ElevatedButton.icon(
                          onPressed: () => _showRecallSimulatorDialog(
                            recall['batch_id']?.toString() ?? '',
                            recall['batch_number']?.toString(),
                          ),
                          icon: const Icon(Icons.account_tree, size: 16),
                          label: const Text('View Impact'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showRecallSimulatorDialog(String batchId, String? batchNumber) {
    showDialog(
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
    return Column(
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
    );
  }
}
