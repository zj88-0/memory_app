import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose(); _newPassCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context)!;
    if (_emailCtrl.text.isEmpty || _newPassCtrl.text.isEmpty) {
      setState(() => _error = l10n.fillAllFields);
      return;
    }
    if (_newPassCtrl.text != _confirmCtrl.text) {
      setState(() => _error = l10n.passwordMismatch);
      return;
    }
    setState(() { _loading = true; _error = null; });
    final err = await context.read<AuthProvider>().resetPassword(
      _emailCtrl.text.trim(), _newPassCtrl.text,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() { _error = l10n.invalidCredentials; _loading = false; });
    } else {
      setState(() { _success = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.forgotPassword)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: _success
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 80),
                    ),
                    const SizedBox(height: 24),
                    Text('Password reset successfully!',
                        style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.login),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_reset_rounded, size: 56, color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(l10n.resetPassword, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('Enter your email and new password',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 32),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 15)),
                      ),
                    ],
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        labelText: l10n.email,
                        prefixIcon: const Icon(Icons.email_rounded, color: AppTheme.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _newPassCtrl,
                      obscureText: true,
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        prefixIcon: const Icon(Icons.lock_rounded, color: AppTheme.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmCtrl,
                      obscureText: true,
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        labelText: l10n.confirmPassword,
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primary),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _reset,
                            child: Text(l10n.resetPassword),
                          ),
                  ],
                ),
        ),
      ),
    );
  }
}
