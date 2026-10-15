import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../core/theme.dart';
import '../widgets/package_verification_card.dart';
import '../widgets/qr_scanner_dialog.dart';

class LandingPage extends StatefulWidget {
  final VoidCallback onNavigateLogin;
  final VoidCallback onNavigateDashboard;
  final VoidCallback onNavigateRegister;

  const LandingPage({
    super.key,
    required this.onNavigateLogin,
    required this.onNavigateDashboard,
    required this.onNavigateRegister,
  });

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final TextEditingController _qrInputController = TextEditingController();
  Map<String, dynamic>? _verificationResult;
  bool _isLoading = false;

  void _verifyPackage() async {
    if (_qrInputController.text.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _verificationResult = null;
    });

    try {
      final res =
          await apiService.verifyPackage(_qrInputController.text.trim());
      if (mounted) setState(() => _verificationResult = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Verification error: $e"),
              backgroundColor: AppTheme.errorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyValue(String value) async {
    _qrInputController.text = value;
    _verifyPackage();
  }

  @override
  void dispose() {
    _qrInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, color: AppTheme.deepTeal),
            SizedBox(width: 8),
            Text(
              "PharmaTrace",
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navy),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.onNavigateLogin,
            child: const Text("Sign In",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.onNavigateRegister,
            child: const Text("Register"),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: widget.onNavigateLogin,
            child: const Text("Launch Console"),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Hero
            const SizedBox(height: 16),
            const Text(
              "Pharmaceutical Supply Chain Traceability",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navy),
            ),
            const SizedBox(height: 12),
            const Text(
              "Tamper-evident custody tracking, serialized QR verification, and two-party receipt confirmation.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),

            // Live Public QR Verification Widget
            Container(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.qr_code_scanner, color: AppTheme.deepTeal),
                          SizedBox(width: 8),
                          Text(
                            "Instant Package Verification",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.navy),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Verify authenticity, current custodian, and custody history against the blockchain ledger.",
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _qrInputController,
                        decoration: const InputDecoration(
                          hintText: "Enter package QR URL or Serial ID",
                          prefixIcon: Icon(Icons.link),
                        ),
                        onSubmitted: (_) => _verifyPackage(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () => QrScannerDialog.show(
                                      context,
                                      onScanned: _verifyValue,
                                    ),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Scan with camera'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isLoading ? null : _verifyPackage,
                            icon: const Icon(Icons.verified_outlined),
                            label: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text("Verify package"),
                          ),
                        ],
                      ),
                      if (_verificationResult != null) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 12),
                        PackageVerificationCard(result: _verificationResult!),
                      ]
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 48),
            // Core Architecture Pillars
            Wrap(
              spacing: 20,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _buildFeatureCard(
                  Icons.verified_user_outlined,
                  "Two-Party Verification",
                  "Strict sender-dispatch and recipient-acceptance workflow. Prevents silent inventory loss.",
                ),
                _buildFeatureCard(
                  Icons.policy_outlined,
                  "Anomaly Detection",
                  "Rules detect duplicate scans, unauthorized attempts, and invalid custody sequences.",
                ),
                _buildFeatureCard(
                  Icons.call_split_outlined,
                  "Shipment Splitting",
                  "Reconciles child allocations against verified received inventory to avoid over-allocation.",
                ),
                _buildFeatureCard(
                  Icons.history_edu_outlined,
                  "Append-Only Audits",
                  "Disputes and corrections record new auditable events without modifying past ledger history.",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String desc) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.deepTeal, size: 28),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.navy)),
          const SizedBox(height: 6),
          Text(desc,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
        ],
      ),
    );
  }
}
