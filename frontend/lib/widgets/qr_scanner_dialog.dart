import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerDialog extends StatefulWidget {
  final ValueChanged<String> onScanned;

  const QrScannerDialog({super.key, required this.onScanned});

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onScanned,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => QrScannerDialog(onScanned: onScanned),
    );
  }

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  bool _handledScan = false;

  void _handleDetection(BarcodeCapture capture) {
    if (_handledScan) return;
    String? value;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue?.isNotEmpty == true) {
        value = barcode.rawValue;
        break;
      }
    }
    if (value == null || value.isEmpty) return;

    _handledScan = true;
    Navigator.of(context).pop();
    widget.onScanned(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan package QR code'),
      content: SizedBox(
        width: 480,
        height: 360,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: MobileScanner(onDetect: _handleDetection),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
