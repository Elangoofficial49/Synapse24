import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../core/theme.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  final VoidCallback onCancel;
  final VoidCallback onRegister;

  const LoginPage({
    super.key,
    required this.onLoginSuccess,
    required this.onCancel,
    required this.onRegister,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController =
      TextEditingController(text: "distributor@pharmatrace.dev");
  final _passwordController = TextEditingController(text: "DevDist2024!");
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  void _submitLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await apiService.login(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      widget.onLoginSuccess();
    } catch (e) {
      String msg = "Authentication failed. Check credentials.";
      final errStr = e.toString().toLowerCase();
      if (errStr.contains("disabled") ||
          errStr.contains("pending") ||
          errStr.contains("review") ||
          errStr.contains("403")) {
        msg =
            "Account is pending approval or disabled. Once an administrator approves or a partner verifies your organization, access will be enabled.";
      } else if (errStr.contains("incorrect") || errStr.contains("401")) {
        msg = "Incorrect email or password. Please verify your credentials.";
      }
      setState(() {
        _errorMessage = msg;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _fillAccount(String email, String pwd) {
    setState(() {
      _emailController.text = email;
      _passwordController.text = pwd;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onCancel,
        ),
        title: const Text("Sign In — PharmaTrace Portal"),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 40, color: AppTheme.deepTeal),
                    const SizedBox(height: 16),
                    const Text(
                      "Secure Portal Access",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.navy),
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.errorRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_errorMessage!,
                            style: const TextStyle(
                                color: AppTheme.errorRed, fontSize: 13)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                          labelText: "Organization Email",
                          prefixIcon: Icon(Icons.email_outlined)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submitLogin,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text("Sign In"),
                    ),
                    TextButton(
                      onPressed: widget.onRegister,
                      child: const Text('Register a company account'),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text(
                      "Demo Role Fast-Fill:",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _demoButton("Manufacturer",
                            "manufacturer@pharmatrace.dev", "DevMfr2024!"),
                        _demoButton("Distributor",
                            "distributor@pharmatrace.dev", "DevDist2024!"),
                        _demoButton("Pharmacy", "pharmacy@pharmatrace.dev",
                            "DevRx2024!"),
                        _demoButton("Auditor", "auditor@pharmatrace.dev",
                            "DevAudit2024!"),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _demoButton(String label, String email, String pwd) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _fillAccount(email, pwd),
    );
  }
}
