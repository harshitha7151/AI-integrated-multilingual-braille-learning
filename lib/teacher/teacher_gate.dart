import 'package:flutter/material.dart';

import 'teacher_session_store.dart';
import 'teacher_login_page.dart';
import 'teacher_dashboard_page.dart';

/// Stateful bridge shown when [AppRole.teacher] is selected.
///
/// Loads the saved [TeacherSession] from disk:
/// - If a valid session exists → shows [TeacherDashboardPage] directly.
/// - If none → shows [TeacherLoginPage]; on success, proceeds to the dashboard.
///
/// [onSwitchRole] is forwarded to the dashboard's logout/switch-role action.
class TeacherGate extends StatefulWidget {
  final void Function() onSwitchRole;
  final TeacherSessionStorage? sessionStorage;

  const TeacherGate({
    super.key,
    required this.onSwitchRole,
    this.sessionStorage,
  });

  @override
  State<TeacherGate> createState() => _TeacherGateState();
}

class _TeacherGateState extends State<TeacherGate> {
  bool _loading = true;
  TeacherSession? _session;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final store =
        widget.sessionStorage ?? await TeacherSessionStore.forApplication();
    final saved = await store.load();
    if (!mounted) return;
    setState(() {
      _session = saved;
      _loading = false;
    });
    if (saved == null) {
      _openLogin();
    }
  }

  Future<void> _openLogin() async {
    final session = await Navigator.of(context).push<TeacherSession>(
      MaterialPageRoute<TeacherSession>(
        builder: (_) => TeacherLoginPage(
          sessionStorage: widget.sessionStorage,
        ),
      ),
    );
    if (!mounted) return;
    if (session != null) {
      setState(() => _session = session);
    } else {
      // User dismissed login without signing in → go back to role selection.
      widget.onSwitchRole();
    }
  }

  void _handleLogout() {
    setState(() => _session = null);
    widget.onSwitchRole();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: Color(0xFF202124));
    }
    final session = _session;
    if (session == null) {
      // Login is being shown via Navigator push; show blank until it resolves.
      return const Scaffold(backgroundColor: Color(0xFF202124));
    }
    return TeacherDashboardPage(
      session: session,
      sessionStorage: widget.sessionStorage,
      onLogout: _handleLogout,
    );
  }
}

