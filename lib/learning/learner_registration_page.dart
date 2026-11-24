import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../accessibility/accessible_action_surface.dart';
import 'learner_account_store.dart';
import 'learner_api.dart';
import '../teacher/teacher_session_store.dart';
import '../teacher/teacher_login_page.dart';

Widget _buttonlessBackAction(BuildContext context) => Tooltip(
  message: 'Go back',
  child: AccessibleActionSurface(
    semanticsLabel: 'Go back',
    actionLabel: 'Go back',
    onActivate: () => Navigator.of(context).maybePop(),
    showDivider: false,
    padding: const EdgeInsets.all(12),
    child: const Icon(Icons.arrow_back),
  ),
);

// ---------------------------------------------------------------------------
// LearnerRegistrationGate
// ---------------------------------------------------------------------------

/// Shown immediately after the role screen for learners.
///
/// If a [LearnerAccount] already exists locally, [onAccountReady] is called
/// immediately (without showing any UI).  Otherwise the registration screen
/// is displayed until the teacher completes registration.
class LearnerRegistrationGate extends StatefulWidget {
  final LearnerAccountStorage? accountStorage;
  final LearnerApi? api;

  /// Called once a valid account is available (new or pre-existing).
  final void Function(LearnerAccount account) onAccountReady;

  const LearnerRegistrationGate({
    super.key,
    this.accountStorage,
    this.api,
    required this.onAccountReady,
  });

  @override
  State<LearnerRegistrationGate> createState() =>
      _LearnerRegistrationGateState();
}

class _LearnerRegistrationGateState extends State<LearnerRegistrationGate> {
  bool _loading = true;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _tts.setVolume(1.0);
    _init();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _init() async {
    final store =
        widget.accountStorage ?? await LearnerAccountStore.forApplication();
    final existing = await store.load();
    if (!mounted) return;
    if (existing != null) {
      widget.onAccountReady(existing);
      return;
    }
    // No account yet — show the waiting screen.
    setState(() => _loading = false);
    unawaited(
      _tts.speak('Welcome. Please ask your teacher to help you register.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: Color(0xFF202124));
    }
    return _AwaitRegistrationScreen(
      accountStorage: widget.accountStorage,
      api: widget.api,
      onRegistered: widget.onAccountReady,
    );
  }
}

// ---------------------------------------------------------------------------
// _AwaitRegistrationScreen
// ---------------------------------------------------------------------------

/// Shown to the learner while they wait for the teacher to register them.
/// Contains a focusable action surface that opens the registration form.
class _AwaitRegistrationScreen extends StatefulWidget {
  final LearnerAccountStorage? accountStorage;
  final LearnerApi? api;
  final void Function(LearnerAccount) onRegistered;

  const _AwaitRegistrationScreen({
    this.accountStorage,
    this.api,
    required this.onRegistered,
  });

  @override
  State<_AwaitRegistrationScreen> createState() =>
      _AwaitRegistrationScreenState();
}

class _AwaitRegistrationScreenState extends State<_AwaitRegistrationScreen> {
  /// Ensures there is a valid teacher session before opening the registration
  /// form.  If no session is saved, shows [TeacherLoginPage] first.
  /// Returns the token string, or null if the teacher dismissed login.
  Future<String?> _ensureTeacherToken() async {
    final store = await TeacherSessionStore.forApplication();
    final existing = await store.load();
    if (existing != null) return existing.token;
    // No session — ask the teacher to log in.
    if (!mounted) return null;
    final session = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute<dynamic>(
        builder: (_) => TeacherLoginPage(sessionStorage: store),
      ),
    );
    if (session == null) return null;
    // session may be a TeacherSession object returned from TeacherLoginPage.
    if (session is TeacherSession) return session.token;
    // Reload from store in case login saved it but returned void.
    final saved = await store.load();
    return saved?.token;
  }

  Future<void> _openRegistration() async {
    final token = await _ensureTeacherToken();
    if (token == null || !mounted) return;
    final account = await Navigator.of(context).push<LearnerAccount>(
      MaterialPageRoute<LearnerAccount>(
        builder: (_) => _TeacherRegistrationForm(
          accountStorage: widget.accountStorage,
          api: widget.api ?? LearnerApi(teacherToken: token),
        ),
      ),
    );
    if (account != null && mounted) {
      widget.onRegistered(account);
    }
  }

  Future<void> _openRestore() async {
    final account = await Navigator.of(context).push<LearnerAccount>(
      MaterialPageRoute<LearnerAccount>(
        builder: (_) => _RestoreAccountForm(
          accountStorage: widget.accountStorage,
          api: widget.api,
        ),
      ),
    );
    if (account != null && mounted) {
      widget.onRegistered(account);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              const Icon(
                Icons.school_outlined,
                color: Color(0xFF8AB4F8),
                size: 60,
              ),
              const SizedBox(height: 16),
              const Text(
                'Welcome',
                style: TextStyle(
                  color: Color(0xFFE8EAED),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please ask your teacher to help you register.',
                style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              AccessibleActionSurface(
                key: const ValueKey('register-learner-button'),
                semanticsLabel: 'Teacher: Register learner',
                semanticsHint:
                    'Double tap to sign in as a teacher and register this learner.',
                actionLabel: 'Register learner',
                onActivate: _openRegistration,
                child: const Row(
                  children: [
                    Icon(
                      Icons.app_registration,
                      color: Color(0xFF8AB4F8),
                      size: 28,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Teacher: Register learner',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              AccessibleActionSurface(
                key: const ValueKey('already-have-account-button'),
                semanticsLabel: 'I already have an account',
                semanticsHint: 'Double tap to restore a learner account.',
                actionLabel: 'Restore learner account',
                onActivate: _openRestore,
                child: const Row(
                  children: [
                    Icon(Icons.restore, color: Color(0xFF8AB4F8)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'I already have an account',
                        style: TextStyle(
                          color: Color(0xFF8AB4F8),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _TeacherRegistrationForm
// ---------------------------------------------------------------------------

/// Visual form filled in by the teacher. Not voice-driven.
/// On success navigates back with [LearnerAccount] as the result.
class _TeacherRegistrationForm extends StatefulWidget {
  final LearnerAccountStorage? accountStorage;
  final LearnerApi? api;

  const _TeacherRegistrationForm({this.accountStorage, this.api});

  @override
  State<_TeacherRegistrationForm> createState() =>
      _TeacherRegistrationFormState();
}

class _TeacherRegistrationFormState extends State<_TeacherRegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtr = TextEditingController();
  final _phoneCtr = TextEditingController();
  final _emailCtr = TextEditingController();
  final _batchCtr = TextEditingController();
  String _selectedLanguage = 'English';
  bool _consent = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameCtr.dispose();
    _phoneCtr.dispose();
    _emailCtr.dispose();
    _batchCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = _phoneCtr.text.trim();
    final email = _emailCtr.text.trim();
    if (phone.isEmpty && email.isEmpty) {
      setState(
        () => _errorMessage =
            'Please supply at least a phone number or an email address.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final api = widget.api ?? LearnerApi();
      final account = await api.register(
        name: _nameCtr.text.trim(),
        phone: phone.isEmpty ? null : phone,
        email: email.isEmpty ? null : email,
        batch: _batchCtr.text.trim().isEmpty ? null : _batchCtr.text.trim(),
        preferredLanguage: _selectedLanguage,
        consent: _consent,
      );
      final store =
          widget.accountStorage ?? await LearnerAccountStore.forApplication();
      await store.save(account);
      if (!mounted) return;
      // Show code screen, then return account to caller.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => _CodeDisplayScreen(
            account: account,
            onDone: () => Navigator.of(context).pop(account),
          ),
        ),
      );
    } on LearnerApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      const msg =
          'Cannot connect to server. Please check your network connection and server settings.';
      setState(() => _errorMessage = msg);
      // Announce audibly as well so visually impaired learners/assistants are aware
      try {
        final tts = FlutterTts();
        tts.speak(msg);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202124),
        foregroundColor: const Color(0xFFE8EAED),
        automaticallyImplyLeading: false,
        leading: _buttonlessBackAction(context),
        title: const Text('Register Learner'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                controller: _nameCtr,
                label: 'Learner name *',
                hint: 'Full name',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Name is required.';
                  if (v.trim().length > 100) return 'Name is too long.';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _field(
                controller: _phoneCtr,
                label: 'Phone number',
                hint: 'Digits only (required if no email)',
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null; // optional
                  if (!RegExp(r'^\d{7,15}$').hasMatch(v.trim())) {
                    return 'Enter 7–15 digits.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _field(
                controller: _emailCtr,
                label: 'Email (optional)',
                hint: 'used if phone is not available',
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _field(
                controller: _batchCtr,
                label: 'Batch / class (optional)',
                hint: 'e.g. Grade 6 – Section A',
              ),
              const SizedBox(height: 16),
              Semantics(
                label: 'Required preferred learning language',
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('preferred-language-field'),
                  value: _selectedLanguage,
                  dropdownColor: const Color(0xFF303134),
                  style: const TextStyle(
                    color: Color(0xFFE8EAED),
                    fontSize: 17,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Preferred learning language',
                    helperText: 'Choose the language for lessons and practice.',
                    prefixIcon: const Icon(Icons.language),
                    filled: true,
                    fillColor: const Color(0xFF303134),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'English', child: Text('English')),
                    DropdownMenuItem(
                      value: 'Hindi',
                      child: Text('Hindi · हिन्दी'),
                    ),
                    DropdownMenuItem(
                      value: 'Kannada',
                      child: Text('Kannada · ಕನ್ನಡ'),
                    ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _selectedLanguage = value);
                          }
                        },
                ),
              ),
              const SizedBox(height: 24),
              // Consent checkbox
              CheckboxListTile(
                key: const ValueKey('consent-checkbox'),
                value: _consent,
                activeColor: const Color(0xFF2468D9),
                tileColor: const Color(0xFF303134),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                title: const Text(
                  'The learner (or guardian) agrees to progress being shared with the teacher.',
                  style: TextStyle(color: Color(0xFFE8EAED), fontSize: 14),
                ),
                onChanged: (v) => setState(() => _consent = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              AccessibleActionSurface(
                key: const ValueKey('submit-registration-button'),
                semanticsLabel: _submitting
                    ? 'Registering learner'
                    : 'Register learner',
                semanticsHint: !_consent
                    ? 'Consent is required before registration.'
                    : 'Double tap to register the learner.',
                actionLabel: 'Register learner',
                onActivate: (_submitting || !_consent) ? null : _submit,
                child: _submitting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Registering…'),
                        ],
                      )
                    : const Row(
                        children: [
                          Icon(Icons.how_to_reg, color: Color(0xFF8AB4F8)),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Register',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: Color(0xFFE8EAED)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF9AA0A6)),
        hintStyle: const TextStyle(color: Color(0xFF5F6368)),
        filled: true,
        fillColor: const Color(0xFF303134),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CodeDisplayScreen
// ---------------------------------------------------------------------------

/// Shown immediately after successful registration.
///
/// TTS reads the code digit by digit, then offers "say 'repeat code'" (or the
/// user activates the repeat surface). The teacher can also read it on-screen.
class _CodeDisplayScreen extends StatefulWidget {
  final LearnerAccount account;
  final VoidCallback onDone;

  const _CodeDisplayScreen({required this.account, required this.onDone});

  @override
  State<_CodeDisplayScreen> createState() => _CodeDisplayScreenState();
}

class _CodeDisplayScreenState extends State<_CodeDisplayScreen> {
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.35); // slower for digit-by-digit reading
    _tts.setVolume(1.0);
    _speakCode();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speakCode() async {
    final code = widget.account.learnerCode;
    final digits = code.split('').join(', ');
    await _tts.stop();
    await _tts.speak(
      'Registration complete. Your learner code is: $digits. '
      'Activate Repeat Code to hear it again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.account.learnerCode;
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF34A853),
                size: 56,
              ),
              const SizedBox(height: 12),
              const Text(
                'Registration complete!',
                style: TextStyle(
                  color: Color(0xFFE8EAED),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.account.name,
                style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Learner code',
                style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 14),
              ),
              const SizedBox(height: 4),
              Semantics(
                label: 'Learner code: ${code.split('').join(', ')}',
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Color(0xFF8AB4F8),
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Write this code down. It is needed to restore the account on a new device.',
                style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              AccessibleActionSurface(
                key: const ValueKey('repeat-code-button'),
                semanticsLabel: 'Repeat learner code',
                actionLabel: 'Repeat learner code',
                onActivate: _speakCode,
                child: const Row(
                  children: [
                    Icon(Icons.volume_up_outlined, color: Color(0xFF8AB4F8)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Repeat code',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              AccessibleActionSurface(
                key: const ValueKey('continue-button'),
                semanticsLabel: 'Start lesson plan',
                actionLabel: 'Start lesson plan',
                onActivate: widget.onDone,
                child: const Row(
                  children: [
                    Icon(Icons.play_arrow, color: Color(0xFF8AB4F8)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Start Lesson Plan',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RestoreAccountForm
// ---------------------------------------------------------------------------

/// Allows an existing learner (or their teacher) to restore the account on a
/// new device using the contact detail + 6-digit learner code.
class _RestoreAccountForm extends StatefulWidget {
  final LearnerAccountStorage? accountStorage;
  final LearnerApi? api;

  const _RestoreAccountForm({this.accountStorage, this.api});

  @override
  State<_RestoreAccountForm> createState() => _RestoreAccountFormState();
}

class _RestoreAccountFormState extends State<_RestoreAccountForm> {
  final _formKey = GlobalKey<FormState>();
  final _contactCtr = TextEditingController();
  final _codeCtr = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _contactCtr.dispose();
    _codeCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final api = widget.api ?? LearnerApi();
      final account = await api.restore(
        phoneOrEmail: _contactCtr.text.trim(),
        code: _codeCtr.text.trim(),
      );
      final store =
          widget.accountStorage ?? await LearnerAccountStore.forApplication();
      await store.save(account);
      if (!mounted) return;
      Navigator.of(context).pop(account);
    } on LearnerApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      const msg =
          'Cannot connect to server. Please check your network connection and server settings.';
      setState(() => _errorMessage = msg);
      try {
        final tts = FlutterTts();
        tts.speak(msg);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202124),
        foregroundColor: const Color(0xFFE8EAED),
        automaticallyImplyLeading: false,
        leading: _buttonlessBackAction(context),
        title: const Text('Restore Account'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter the phone number or email used at registration, plus the 6-digit learner code.',
                style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 15),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _contactCtr,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Color(0xFFE8EAED)),
                decoration: _inputDec(
                  'Phone number or email',
                  'digits or user@example.com',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Phone number or email is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeCtr,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(color: Color(0xFFE8EAED)),
                decoration: _inputDec('6-digit learner code', '000000'),
                validator: (v) {
                  if (v == null || !RegExp(r'^\d{6}$').hasMatch(v.trim())) {
                    return 'Enter the 6-digit code.';
                  }
                  return null;
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              AccessibleActionSurface(
                key: const ValueKey('restore-button'),
                semanticsLabel: _submitting
                    ? 'Restoring learner account'
                    : 'Restore learner account',
                actionLabel: 'Restore learner account',
                onActivate: _submitting ? null : _submit,
                child: _submitting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Restoring…'),
                        ],
                      )
                    : const Row(
                        children: [
                          Icon(Icons.restore, color: Color(0xFF8AB4F8)),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Restore account',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: Color(0xFF9AA0A6)),
    hintStyle: const TextStyle(color: Color(0xFF5F6368)),
    filled: true,
    fillColor: const Color(0xFF303134),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
  );
}
