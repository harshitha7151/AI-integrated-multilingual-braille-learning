import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dashboard_api.dart';
import 'learner_detail_page.dart';
import 'teacher_session_store.dart';
import '../learning/learner_registration_page.dart';
import '../learning/learner_api.dart';

class TeacherDashboardPage extends StatefulWidget {
  final TeacherSession session;
  final TeacherSessionStorage? sessionStorage;
  final void Function() onLogout;
  final DashboardApi? api;

  const TeacherDashboardPage({
    super.key,
    required this.session,
    required this.onLogout,
    this.sessionStorage,
    this.api,
  });

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  late final DashboardApi _api;
  bool _loading = true;
  String? _error;
  TeacherDashboardData? _dashboardData;

  String _searchQuery = '';
  String _selectedBatch = 'All';
  String _selectedStatus = 'All';

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? DashboardApi(teacherToken: widget.session.token);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetchDashboard();
      if (!mounted) return;
      setState(() {
        _dashboardData = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    HapticFeedback.heavyImpact();
    final store =
        widget.sessionStorage ?? await TeacherSessionStore.forApplication();
    await store.clear();
    widget.onLogout();
  }

  Future<void> _registerLearner() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _TeacherRegistrationWrapper(session: widget.session),
      ),
    );
    _load();
  }

  List<LearnerProgressItem> get _filteredLearners {
    if (_dashboardData == null) return [];
    return _dashboardData!.learners.where((l) {
      if (_searchQuery.isNotEmpty &&
          !l.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_selectedBatch != 'All') {
        if ((l.batch ?? '') != _selectedBatch) return false;
      }
      if (_selectedStatus != 'All') {
        if (l.status.toLowerCase() != _selectedStatus.toLowerCase()) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<String> get _availableBatches {
    if (_dashboardData == null) return ['All'];
    final batches = _dashboardData!.learners
        .map((l) => l.batch)
        .where((b) => b != null && b.trim().isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    batches.sort();
    return ['All', ...batches];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('teacher-dashboard'),
      backgroundColor: const Color(0xFF202124),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202124),
        foregroundColor: const Color(0xFFE8EAED),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Teacher Dashboard',
              key: ValueKey('teacher-dashboard-title'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              widget.session.organization != null
                  ? '${widget.session.name} • ${widget.session.organization}'
                  : widget.session.name,
              style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 13),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Register Learner',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _registerLearner,
          ),
          IconButton(
            key: const ValueKey('logout-button'),
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _dashboardData == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8AB4F8)),
      );
    }
    if (_error != null && _dashboardData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final summary = _dashboardData?.summary ??
        const DashboardSummary(
          totalLearners: 0,
          activeThisWeek: 0,
          struggling: 0,
        );
    final learners = _filteredLearners;

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF8AB4F8),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSummaryCards(summary),
          const SizedBox(height: 20),
          _buildFilterBar(),
          const SizedBox(height: 16),
          if (learners.isEmpty)
            _buildEmptyState()
          else
            ...learners.map(_buildLearnerTile),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(DashboardSummary summary) {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            'Total Learners',
            '${summary.totalLearners}',
            const Color(0xFF8AB4F8),
            Icons.people_outline,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            'Active (7d)',
            '${summary.activeThisWeek}',
            const Color(0xFF34A853),
            Icons.bolt_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            'Struggling',
            '${summary.struggling}',
            summary.struggling > 0 ? Colors.redAccent : const Color(0xFF9AA0A6),
            Icons.warning_amber_rounded,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(String title, String count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF303134),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const Spacer(),
              Text(
                count,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Column(
      children: [
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(color: Color(0xFFE8EAED)),
          decoration: InputDecoration(
            hintText: 'Search by learner name...',
            hintStyle: const TextStyle(color: Color(0xFF5F6368)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF9AA0A6)),
            filled: true,
            fillColor: const Color(0xFF303134),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _dropdownFilter(
                label: 'Batch',
                value: _selectedBatch,
                items: _availableBatches,
                onChanged: (v) => setState(() => _selectedBatch = v ?? 'All'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdownFilter(
                label: 'Status',
                value: _selectedStatus,
                items: const ['All', 'Active', 'Inactive', 'Struggling'],
                onChanged: (v) => setState(() => _selectedStatus = v ?? 'All'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dropdownFilter({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF303134),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          dropdownColor: const Color(0xFF303134),
          style: const TextStyle(color: Color(0xFFE8EAED), fontSize: 13),
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF9AA0A6)),
          isExpanded: true,
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text('$label: $item'),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.inbox, size: 48, color: Color(0xFF5F6368)),
            const SizedBox(height: 12),
            const Text(
              'No learners match your search or filter.',
              style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _registerLearner,
              icon: const Icon(Icons.add),
              label: const Text('Register a learner'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLearnerTile(LearnerProgressItem l) {
    return Card(
      color: const Color(0xFF303134),
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final deleted = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => LearnerDetailPage(
                learnerId: l.id,
                api: _api,
              ),
            ),
          );
          if (deleted == true) {
            _load();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.name,
                      style: const TextStyle(
                        color: Color(0xFFE8EAED),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildStatusBadge(l.status),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Language: ${l.preferredLanguage}'
                '${l.lastActiveAt == null ? '' : ' • Last active: ${_formatDate(l.lastActiveAt!)}'}',
                style: const TextStyle(
                  color: Color(0xFF9AA0A6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (l.batch != null && l.batch!.isNotEmpty) ...[
                    Text(
                      l.batch!,
                      style: const TextStyle(
                          color: Color(0xFF9AA0A6), fontSize: 13),
                    ),
                    const Text(' • ',
                        style: TextStyle(color: Color(0xFF5F6368))),
                  ],
                  Text(
                    'Acc: ${l.accuracyPct}%',
                    style: TextStyle(
                      color: l.accuracyPct >= 80
                          ? const Color(0xFF34A853)
                          : l.accuracyPct < 60
                              ? Colors.redAccent
                              : const Color(0xFFFBBC04),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Text(' • ', style: TextStyle(color: Color(0xFF5F6368))),
                  Text(
                    '${l.attempts7d} atts (7d)',
                    style:
                        const TextStyle(color: Color(0xFF9AA0A6), fontSize: 13),
                  ),
                ],
              ),
              if (l.currentLetter.isNotEmpty || l.topWeakLetters.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (l.currentLetter.isNotEmpty)
                      Chip(
                        backgroundColor: const Color(0xFF3C4043),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          'Current: ${l.currentLetter}',
                          style: const TextStyle(
                              color: Color(0xFF8AB4F8), fontSize: 11),
                        ),
                      ),
                    if (l.topWeakLetters.isNotEmpty)
                      Chip(
                        backgroundColor: const Color(0xFF3C4043),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          'Weak: ${l.topWeakLetters.join(', ')}',
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status.toLowerCase()) {
      case 'struggling':
        bg = Colors.redAccent.withValues(alpha: 0.2);
        fg = Colors.redAccent;
        label = 'Struggling';
        break;
      case 'active':
        bg = const Color(0xFF34A853).withValues(alpha: 0.2);
        fg = const Color(0xFF34A853);
        label = 'Active';
        break;
      case 'inactive':
      default:
        bg = const Color(0xFF5F6368).withValues(alpha: 0.2);
        fg = const Color(0xFF9AA0A6);
        label = 'Inactive';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final date = DateTime.parse(iso).toLocal();
      return '${date.month}/${date.day}';
    } catch (_) {
      return iso;
    }
  }
}

class _TeacherRegistrationWrapper extends StatelessWidget {
  final TeacherSession session;

  const _TeacherRegistrationWrapper({required this.session});

  @override
  Widget build(BuildContext context) {
    return LearnerRegistrationGate(
      api: LearnerApi(teacherToken: session.token),
      onAccountReady: (_) => Navigator.of(context).pop(),
    );
  }
}
