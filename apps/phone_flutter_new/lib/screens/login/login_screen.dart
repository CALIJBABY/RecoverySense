import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../../services/auth/auth_service.dart';
import '../../services/firebase/baseline_assessment_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;

  Future<void> _signIn() async {
    if (_loading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_looksLikeEmail(email)) {
      _showError('Enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      _showError('Enter your password.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await _authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      final baselineComplete = await BaselineAssessmentRepository().isComplete();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        baselineComplete ? AppRoutes.dashboard : AppRoutes.baseline,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showError(_authMessage(error));
    } catch (error, stackTrace) {
      debugPrint('Sign-in failed: $error\n$stackTrace');
      if (!mounted) return;
      _showError('Unable to sign in right now. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showPasswordResetSheet() async {
    FocusScope.of(context).unfocus();

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _PasswordResetSheet(
          initialEmail: _emailController.text.trim(),
          authService: _authService,
        );
      },
    );

    if (!mounted || sent != true) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset email sent. Check your inbox and spam folder.',
          ),
        ),
      );
  }

  static String _authMessage(FirebaseAuthException error) => switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'invalid-credential' => 'Email or password is incorrect.',
        'wrong-password' => 'Email or password is incorrect.',
        'user-not-found' => 'Email or password is incorrect.',
        'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
        'network-request-failed' => 'Check your internet connection and try again.',
        _ => 'Unable to sign in. Please try again.',
      };

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    final dot = value.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < value.length - 1;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;

            return Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.all(compact ? 16 : 26),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 18 : 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.watch_outlined,
                            size: compact ? 42 : 56,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          SizedBox(height: compact ? 8 : 14),
                          Text(
                            'RecoverySense',
                            style: TextStyle(
                              fontSize: compact ? 25 : 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to securely store sensor and EMA data.',
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: compact ? 16 : 24),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration:
                                const InputDecoration(labelText: 'Email'),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            decoration:
                                const InputDecoration(labelText: 'Password'),
                            onSubmitted: (_) => _signIn(),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed:
                                  _loading ? null : _showPasswordResetSheet,
                              child: const Text('Forgot password?'),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _signIn,
                              child: Text(
                                _loading ? 'Signing In...' : 'Sign In',
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.pushNamed(
                                      context,
                                      AppRoutes.register,
                                    ),
                            child: const Text('Create Account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({
    required this.initialEmail,
    required this.authService,
  });

  final String initialEmail;
  final AuthService authService;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _sending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (_sending || !(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _resetMessage(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to send a reset email right now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  static String _resetMessage(FirebaseAuthException error) => switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
        'network-request-failed' => 'Check your internet connection and try again.',
        _ => 'Unable to send a reset email right now. Please try again.',
      };

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Reset password',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the email address connected to your RecoverySense account.',
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _emailController,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty || !email.contains('@')) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _sendResetEmail(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _sendResetEmail,
                      child: _sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send reset email'),
                    ),
                  ),
                  TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
