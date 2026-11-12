import '../theme/app_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'role_store.dart';

/// Full-screen role-selection shown before any other app content.
///
/// Behaviour:
/// - TTS speaks the prompt immediately and repeats every ~10 s until a choice
///   is made (via [onSpeak]/[onStop] callbacks, matching [WelcomeOnboarding]).
/// - Swipe up anywhere on the learner zone → learner.
/// - Tap the Teacher button → teacher.
/// - Voice "learner" / "i am a learner" or "teacher" / "i am a teacher" →
///   handled by the caller via [onVoiceInput]; the page itself does not init
///   STT — the caller passes already-recognised text.
/// - [onRoleSelected] is called with the chosen role; the caller persists and
///   navigates away.
class RoleSelectionPage extends StatefulWidget {
  final Future<void> Function(String text) onSpeak;
  final Future<void> Function() onStop;

  /// Called when the user has chosen a role. The caller should persist the
  /// choice via [RoleStore] and replace this widget with the appropriate page.
  final Future<void> Function(AppRole role) onRoleSelected;

  /// Optional: the caller feeds recognised voice text here so this widget can
  /// check for "learner" / "teacher" / "switch role" phrases.
  final Stream<String>? voiceInputStream;

  const RoleSelectionPage({
    super.key,
    required this.onSpeak,
    required this.onStop,
    required this.onRoleSelected,
    this.voiceInputStream,
  });

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  static const _prompt =
      'Are you a teacher or a learner? '
      'Swipe up if you are a learner. '
      'Teachers, tap the Teacher button on screen.';

  Timer? _repeatTimer;
  StreamSubscription<String>? _voiceSub;

  // Swipe tracking for the learner zone.
  Offset? _swipeStart;

  @override
  void initState() {
    super.initState();
    _speakPrompt();
    _repeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _speakPrompt();
    });
    _voiceSub = widget.voiceInputStream?.listen(_handleVoice);
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _voiceSub?.cancel();
    super.dispose();
  }

  void _speakPrompt() {
    if (!mounted) return;
    widget.onSpeak(_prompt);
  }

  Future<void> _choose(AppRole role) async {
    if (!mounted) return;
    _repeatTimer?.cancel();
    widget.onStop();
    HapticFeedback.heavyImpact();
    final confirmation = role == AppRole.learner
        ? 'Learner selected. Opening your learning screen.'
        : 'Teacher selected. Opening the teacher dashboard.';
    widget.onSpeak(confirmation);
    await widget.onRoleSelected(role);
  }

  void _handleVoice(String text) {
    final t = text.toLowerCase().trim();
    if (t == 'learner' || t == 'i am a learner' || t == 'i am learner') {
      unawaited(_choose(AppRole.learner));
    } else if (t == 'teacher' || t == 'i am a teacher' || t == 'i am teacher') {
      unawaited(_choose(AppRole.teacher));
    }
  }

  // ── Swipe gesture helpers ───────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent e) => _swipeStart = e.position;

  void _onPointerUp(PointerUpEvent e) {
    final start = _swipeStart;
    _swipeStart = null;
    if (start == null) return;
    final dy = e.position.dy - start.dy;
    if (dy < -48) unawaited(_choose(AppRole.learner));
  }

  void _onPointerCancel(PointerCancelEvent _) => _swipeStart = null;

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top: Teacher button (40 % height) ──────────────────────
            Expanded(
              flex: 4,
              child: Semantics(
                label: 'Teacher selection area. Tap the Teacher button.',
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'I am a teacher. Tap to open the teacher dashboard.',
                    child: ElevatedButton(
                      key: const ValueKey('teacher-button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(240, 96),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => unawaited(_choose(AppRole.teacher)),
                      child: const Text('Teacher'),
                    ),
                  ),
                ),
              ),
            ),

            // ── Divider ────────────────────────────────────────────────
            const Divider(color: AppColors.outline, thickness: 1, height: 1),

            // ── Bottom: Learner swipe zone (60 % height) ───────────────
            Expanded(
              flex: 6,
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: Semantics(
                  key: const ValueKey('learner-swipe-zone'),
                  label: 'Learner area. Swipe up to continue as a learner.',
                  hint: 'Swipe up anywhere in this area.',
                  customSemanticsActions: {
                    const CustomSemanticsAction(label: 'I am a learner'):
                        () => _choose(AppRole.learner),
                  },
                  child: Container(
                    width: double.infinity,
                    color: Colors.transparent,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.keyboard_arrow_up,
                          color: AppColors.accent,
                          size: 56,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Swipe up — I am a Learner',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _prompt,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin stateful wrapper rendered as [ResonantApp]'s home.
///
/// Loads the persisted role asynchronously; while loading it shows a blank
/// dark screen (no flash). Once loaded it routes to:
/// - [RoleSelectionPage] — if no role is saved.
/// - The learner page builder — if role is [AppRole.learner].
/// - The teacher page builder — if role is [AppRole.teacher].
///
/// All page builders are injected so this widget is testable without disk I/O.
class RoleGate extends StatefulWidget {
  final RoleStorage? roleStorage;
  final Future<void> Function(String) onSpeak;
  final Future<void> Function() onStop;
  final Widget learnerHome;
  final Widget Function(void Function() onSwitchRole) teacherHome;
  final Stream<String>? voiceInputStream;

  const RoleGate({
    super.key,
    this.roleStorage,
    required this.onSpeak,
    required this.onStop,
    required this.learnerHome,
    required this.teacherHome,
    this.voiceInputStream,
  });

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  RoleStorage? _store;
  AppRole? _role;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final store = widget.roleStorage ?? await RoleStore.forApplication();
    final role = await store.savedRole();
    if (!mounted) return;
    setState(() {
      _store = store;
      _role = role;
      _loading = false;
    });
  }

  Future<void> _onRoleSelected(AppRole role) async {
    await _store?.saveRole(role);
    if (!mounted) return;
    setState(() => _role = role);
  }

  Future<void> _switchRole() async {
    await _store?.clearRole();
    if (!mounted) return;
    setState(() => _role = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: AppColors.background);
    }
    if (_role == null) {
      return RoleSelectionPage(
        onSpeak: widget.onSpeak,
        onStop: widget.onStop,
        onRoleSelected: _onRoleSelected,
        voiceInputStream: widget.voiceInputStream,
      );
    }
    if (_role == AppRole.teacher) {
      return widget.teacherHome(_switchRole);
    }
    return widget.learnerHome;
  }
}

