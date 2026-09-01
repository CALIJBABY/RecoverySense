import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../services/auth/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;

  Future<void> _createAccount() async {
    if (_loading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_looksLikeEmail(email)) {
      _showError('Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _showError('Use a password with at least 6 characters.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await _authService.createAccount(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.baseline);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showError(_authMessage(error));
    } catch (error, stackTrace) {
      debugPrint('Account creation failed: $error\n$stackTrace');
      if (!mounted) return;
      _showError('Unable to create the account right now. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _authMessage(FirebaseAuthException error) => switch (error.code) {
        'email-already-in-use' => 'An account already exists for this email.',
        'invalid-email' => 'Enter a valid email address.',
        'weak-password' => 'Use a stronger password with at least 6 characters.',
        'network-request-failed' => 'Check your internet connection and try again.',
        _ => 'Unable to create the account. Please try again.',
      };

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    final dot = value.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < value.length - 1;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Create your study account',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password (minimum 6 characters)',
                      ),
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton(
                      onPressed: _loading ? null : _createAccount,
                      child: Text(
                        _loading ? 'Creating Account...' : 'Create Account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
