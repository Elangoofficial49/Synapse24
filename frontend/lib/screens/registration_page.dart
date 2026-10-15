import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class RegistrationPage extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onRegistered;

  const RegistrationPage({
    super.key,
    required this.onBack,
    required this.onRegistered,
  });

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _otpCode = TextEditingController();
  final _password = TextEditingController();
  final _organizationName = TextEditingController();
  final _licenseNumber = TextEditingController();
  final _address = TextEditingController();
  final _contactEmail = TextEditingController();
  String _organizationType = 'manufacturer';
  String? _errorMessage;
  bool _isLoading = false;
  bool _submitted = false;
  String? _otpSentFor;
  bool _otpVerified = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _otpCode.dispose();
    _password.dispose();
    _organizationName.dispose();
    _licenseNumber.dispose();
    _address.dispose();
    _contactEmail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_otpVerified || _otpSentFor != _email.text.trim().toLowerCase()) {
      setState(() =>
          _errorMessage = 'Verify your sign-in email before registering.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await apiService.register({
        'full_name': _name.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'password': _password.text,
        'organization_name': _organizationName.text.trim(),
        'organization_type': _organizationType,
        'license_number': _licenseNumber.text.trim(),
        'address': _address.text.trim(),
        'contact_email': _contactEmail.text.trim(),
      });
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) {
        setState(
            () => _errorMessage = 'Registration failed: ${_errorText(error)}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String _errorText(Object error) {
    if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData is Map && responseData['detail'] is String) {
        return responseData['detail'] as String;
      }
      return error.message ?? 'Could not connect to the server.';
    }
    return error.toString();
  }

  void _onEmailChanged(String value) {
    if (_otpSentFor != null && _otpSentFor != value.trim().toLowerCase()) {
      setState(() {
        _otpSentFor = null;
        _otpVerified = false;
        _otpCode.clear();
      });
    }
  }

  Future<void> _sendOtp() async {
    final email = _email.text.trim().toLowerCase();
    final validationError = _validateEmail(email);
    if (validationError != null) {
      setState(() => _errorMessage = validationError);
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await apiService.sendRegistrationOtp(email);
      if (mounted) {
        setState(() {
          _otpSentFor = email;
          _otpVerified = false;
          _otpCode.clear();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _errorMessage = _errorText(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final email = _email.text.trim().toLowerCase();
    if (_otpSentFor != email) {
      setState(() =>
          _errorMessage = 'Send a verification code to this email first.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(_otpCode.text.trim())) {
      setState(
          () => _errorMessage = 'Enter the six-digit code from your email.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await apiService.verifyRegistrationOtp(email, _otpCode.text.trim());
      if (mounted) setState(() => _otpVerified = true);
    } catch (error) {
      if (mounted) setState(() => _errorMessage = _errorText(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: const Text('Register an organization'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _submitted ? _buildSubmitted() : _buildForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitted() {
    return Column(
      children: [
        const Icon(Icons.hourglass_top, size: 52, color: AppTheme.deepTeal),
        const SizedBox(height: 16),
        const Text('Registration submitted',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.navy)),
        const SizedBox(height: 12),
        const Text(
          'Your organization and account are pending administrator review. You can sign in after the administrator approves the registration.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
            onPressed: widget.onRegistered,
            child: const Text('Return to sign in')),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Create a supply-chain account',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.navy)),
          const SizedBox(height: 8),
          const Text(
              'New accounts are reviewed and approved by a PharmaTrace administrator before access is enabled.'),
          const SizedBox(height: 20),
          if (_errorMessage != null) ...[
            Text(_errorMessage!,
                style: const TextStyle(color: AppTheme.errorRed)),
            const SizedBox(height: 12),
          ],
          TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Your full name'),
              validator: _required),
          const SizedBox(height: 12),
          TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Sign-in email'),
              onChanged: _onEmailChanged,
              validator: _validateEmail),
          const SizedBox(height: 12),
          if (_otpSentFor == null)
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _sendOtp,
              icon: const Icon(Icons.mail_outline),
              label: const Text('Send email verification code'),
            )
          else ...[
            TextFormField(
              controller: _otpCode,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Email verification code',
                helperText: _otpVerified
                    ? 'Email verified'
                    : 'Enter the six-digit code sent to $_otpSentFor',
                suffixIcon: _otpVerified
                    ? const Icon(Icons.verified, color: AppTheme.deepTeal)
                    : null,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading || _otpVerified ? null : _verifyOtp,
                    child: const Text('Verify code'),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  child: const Text('Resend code'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password (10+ characters)',
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
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                ),
              ),
              validator: (value) {
                if (value == null || value.length < 10) {
                  return 'Use at least 10 characters';
                }
                if (!RegExp(r'[a-z]').hasMatch(value) ||
                    !RegExp(r'[A-Z]').hasMatch(value) ||
                    !RegExp(r'\d').hasMatch(value) ||
                    !RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
                  return 'Use uppercase and lowercase letters, a number, and a symbol';
                }
                return null;
              }),
          const SizedBox(height: 20),
          const Text('Organization details',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: AppTheme.navy)),
          const SizedBox(height: 12),
          TextFormField(
              controller: _organizationName,
              decoration: const InputDecoration(labelText: 'Organization name'),
              validator: _required),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _organizationType,
            decoration: const InputDecoration(labelText: 'Organization type'),
            items: const [
              DropdownMenuItem(
                  value: 'manufacturer', child: Text('Manufacturer')),
              DropdownMenuItem(
                  value: 'distributor',
                  child: Text('Distributor / Wholesaler')),
              DropdownMenuItem(
                  value: 'transporter', child: Text('Transporter')),
              DropdownMenuItem(value: 'pharmacy', child: Text('Pharmacy')),
              DropdownMenuItem(value: 'hospital', child: Text('Hospital')),
              DropdownMenuItem(
                  value: 'regulator', child: Text('Regulator / Auditor')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _organizationType = value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
              controller: _licenseNumber,
              decoration: const InputDecoration(
                  labelText: 'Business / operating license number'),
              validator: _required),
          const SizedBox(height: 12),
          TextFormField(
              controller: _address,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Organization address'),
              validator: _required),
          const SizedBox(height: 12),
          TextFormField(
              controller: _contactEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Organization contact email'),
              validator: _required),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isLoading || !_otpVerified ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Submit for approval'),
          ),
        ],
      ),
    );
  }
}
