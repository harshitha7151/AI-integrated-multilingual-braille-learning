import 'package:flutter/material.dart';

import 'teacher_api.dart';
import 'teacher_session_store.dart';

/// Full-screen teacher login / sign-up page (visual-only, no voice).
///
/// On success pops with a [TeacherSession]. On failure shows an inline error
/// with a retry option.
class TeacherLoginPage extends StatefulWidget {
  final TeacherSessionStorage? sessionStorage;
  final TeacherApi? api;

  const TeacherLoginPage({super.key, this.sessionStorage, this.api});

  @override
  State<TeacherLoginPage> createState() => _TeacherLoginPageState();
}

class _TeacherLoginPageState extends State<TeacherLoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _busy = false;
  String? _error;

  // Login form
  final _loginFormKey = GlobalKey<FormState>();
  final _loginEmailCtr = TextEditingController();
  final _loginPassCtr = TextEditingController();

  // Sign-up form
  final _signupFormKey = GlobalKey<FormState>();
  final _signupNameCtr = TextEditingController();
  final _signupEmailCtr = TextEditingController();
  final _signupPassCtr = TextEditingController();
  final _signupOrgCtr = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmailCtr.dispose();
    _loginPassCtr.dispose();
    _signupNameCtr.dispose();
    _signupEmailCtr.dispose();
    _signupPassCtr.dispose();
    _signupOrgCtr.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.api ?? TeacherApi();
      final session = await api.login(
        email: _loginEmailCtr.text.trim(),
        password: _loginPassCtr.text,
      );
      final store =
          widget.sessionStorage ?? await TeacherSessionStore.forApplication();
      await store.save(session);
      if (!mounted) return;
      Navigator.of(context).pop(session);
    } on TeacherApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleSignup() async {
    if (!(_signupFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.api ?? TeacherApi();
      final session = await api.signup(
        name: _signupNameCtr.text.trim(),
        email: _signupEmailCtr.text.trim(),
        password: _signupPassCtr.text,
        organization: _signupOrgCtr.text.trim().isEmpty
            ? null
            : _signupOrgCtr.text.trim(),
      );
      final store =
          widget.sessionStorage ?? await TeacherSessionStore.forApplication();
      await store.save(session);
      if (!mounted) return;
      Navigator.of(context).pop(session);
    } on TeacherApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openForgotPasswordDialog() {
    final emailCtr = TextEditingController(text: _loginEmailCtr.text.trim());
    final tokenCtr = TextEditingController();
    final newPassCtr = TextEditingController();
    String? dialogMsg;
    bool tokenSent = false;
    bool dialogBusy = false;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF303134),
              title: Text(
                tokenSent ? 'Reset Password' : 'Forgot Password',
                style: const TextStyle(color: Color(0xFFE8EAED)),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dialogMsg != null) ...[
                      Text(
                        dialogMsg!,
                        style: TextStyle(
                          color: dialogMsg!.startsWith('Error')
                              ? Colors.redAccent
                              : const Color(0xFF34A853),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!tokenSent) ...[
                      const Text(
                        'Password reset is not configured. No reset email can be sent. Contact your administrator.',
                        style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      _emailField(emailCtr),
                    ] else ...[
                      _textField(tokenCtr, 'Reset Token', validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Token required.';
                        return null;
                      }),
                      const SizedBox(height: 12),
                      _passwordField(newPassCtr, label: 'New Password (min 8 chars)',
                          extraValidator: (v) {
                        if (v != null && v.length < 8) return 'Min 8 characters.';
                        return null;
                      }),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF9AA0A6))),
                ),
                if (!tokenSent)
                  ElevatedButton(
                    onPressed: dialogBusy
                        ? null
                        : () async {
                            final email = emailCtr.text.trim();
                            if (email.isEmpty) return;
                            setDialogState(() => dialogBusy = true);
                            try {
                              final api = widget.api ?? TeacherApi();
                              await api.requestPasswordReset(email);
                              setDialogState(() {
                                tokenSent = true;
                                dialogMsg = 'Reset token issued. Check server console (or email).';
                                dialogBusy = false;
                              });
                            } catch (e) {
                              setDialogState(() {
                                dialogMsg = 'Error: ${e.toString()}';
                                dialogBusy = false;
                              });
                            }
                          },
                    child: const Text('Send Token'),
                  )
                else
                  ElevatedButton(
                    onPressed: dialogBusy
                        ? null
                        : () async {
                            final tok = tokenCtr.text.trim();
                            final pass = newPassCtr.text;
                            if (tok.isEmpty || pass.length < 8) return;
                            setDialogState(() => dialogBusy = true);
                            try {
                              final api = widget.api ?? TeacherApi();
                              await api.resetPassword(token: tok, newPassword: pass);
                              if (context.mounted) Navigator.of(ctx).pop();
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Password updated successfully! Please log in.'),
                                    backgroundColor: Color(0xFF34A853),
                                  ),
                                );
                              }
                            } catch (e) {
                              setDialogState(() {
                                dialogMsg = 'Error: ${e.toString()}';
                                dialogBusy = false;
                              });
                            }
                          },
                    child: const Text('Update Password'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202124),
        foregroundColor: const Color(0xFFE8EAED),
        title: const Text('Teacher Account'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFF8AB4F8),
          unselectedLabelColor: const Color(0xFF9AA0A6),
          indicatorColor: const Color(0xFF8AB4F8),
          tabs: const [Tab(text: 'Log in'), Tab(text: 'Sign up')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildLoginTab(),
          _buildSignupTab(),
        ],
      ),
    );
  }

  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _loginFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _emailField(_loginEmailCtr),
            const SizedBox(height: 16),
            _passwordField(_loginPassCtr, label: 'Password'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _openForgotPasswordDialog,
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 13),
                ),
              ),
            ),
            _errorText(),
            const SizedBox(height: 16),
            _submitButton('Log in', _handleLogin),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _signupFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _textField(_signupNameCtr, 'Full name *', validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Name is required.';
              if (v.trim().length > 100) return 'Name is too long.';
              return null;
            }),
            const SizedBox(height: 16),
            _emailField(_signupEmailCtr),
            const SizedBox(height: 16),
            _passwordField(_signupPassCtr,
                label: 'Password (min 8 characters)',
                extraValidator: (v) {
                  if (v != null && v.length < 8) {
                    return 'Password must be at least 8 characters.';
                  }
                  return null;
                }),
            const SizedBox(height: 16),
            _textField(_signupOrgCtr, 'School / organisation (optional)'),
            _errorText(),
            const SizedBox(height: 24),
            _submitButton('Create account', _handleSignup),
          ],
        ),
      ),
    );
  }

  Widget _emailField(TextEditingController ctr) => TextFormField(
        controller: ctr,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(color: Color(0xFFE8EAED)),
        decoration: _dec('Email *'),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Email is required.';
          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
            return 'Enter a valid email address.';
          }
          return null;
        },
      );

  Widget _passwordField(TextEditingController ctr,
      {required String label,
      String? Function(String?)? extraValidator}) =>
      TextFormField(
        controller: ctr,
        obscureText: true,
        style: const TextStyle(color: Color(0xFFE8EAED)),
        decoration: _dec(label),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Password is required.';
          return extraValidator?.call(v);
        },
      );

  Widget _textField(TextEditingController ctr, String label,
      {String? Function(String?)? validator}) =>
      TextFormField(
        controller: ctr,
        style: const TextStyle(color: Color(0xFFE8EAED)),
        decoration: _dec(label),
        validator: validator,
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9AA0A6)),
        filled: true,
        fillColor: const Color(0xFF303134),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      );

  Widget _errorText() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        _error!,
        style: const TextStyle(color: Colors.redAccent, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _submitButton(String label, VoidCallback onPressed) =>
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2468D9),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 64),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        onPressed: _busy ? null : onPressed,
        child: _busy
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Text(label),
      );
}
