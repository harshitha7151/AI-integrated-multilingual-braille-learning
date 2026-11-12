import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Placeholder teacher dashboard shown until the real dashboard is built.
///
/// Provides:
/// - A clear "coming soon" message so sighted helpers understand the state.
/// - A prominent "Switch role" button (and voice "switch role" handled by the
///   caller via [voiceInputStream]).
/// - Full Semantics labels for accessibility.
class TeacherDashboardPlaceholder extends StatelessWidget {
  /// Called when the user wants to return to the role-selection screen.
  final void Function() onSwitchRole;

  /// Optional stream of recognised voice text; "switch role" triggers
  /// [onSwitchRole].
  final Stream<String>? voiceInputStream;

  const TeacherDashboardPlaceholder({
    super.key,
    required this.onSwitchRole,
    this.voiceInputStream,
  });

  @override
  Widget build(BuildContext context) {
    return _TeacherDashboardBody(
      onSwitchRole: onSwitchRole,
      voiceInputStream: voiceInputStream,
    );
  }
}

class _TeacherDashboardBody extends StatefulWidget {
  final void Function() onSwitchRole;
  final Stream<String>? voiceInputStream;

  const _TeacherDashboardBody({
    required this.onSwitchRole,
    this.voiceInputStream,
  });

  @override
  State<_TeacherDashboardBody> createState() => _TeacherDashboardBodyState();
}

class _TeacherDashboardBodyState extends State<_TeacherDashboardBody> {
  late final StreamSubscription? _voiceSub;

  @override
  void initState() {
    super.initState();
    _voiceSub = widget.voiceInputStream?.listen(_handleVoice);
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    super.dispose();
  }

  void _handleVoice(String text) {
    final t = text.toLowerCase().trim();
    if (t == 'switch role' || t == 'switch' || t == 'go back' ||
        t == 'i am a learner' || t == 'learner') {
      widget.onSwitchRole();
    }
  }

  void _doSwitch() {
    HapticFeedback.heavyImpact();
    widget.onSwitchRole();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('teacher-dashboard'),
      backgroundColor: const Color(0xFF202124),
      body: SafeArea(
        child: Semantics(
          label: 'Teacher dashboard. Coming soon.',
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Teacher Dashboard',
                      key: ValueKey('teacher-dashboard-title'),
                      style: TextStyle(
                        color: Color(0xFFE8EAED),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Teacher dashboard coming soon.',
                    style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  Semantics(
                    button: true,
                    label: 'Switch role. Return to role selection screen.',
                    child: ElevatedButton.icon(
                      key: const ValueKey('switch-role-button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5F6368),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(220, 72),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(fontSize: 20),
                      ),
                      onPressed: _doSwitch,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Switch Role'),
                    ),
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
