import 'package:flutter/material.dart';

import 'dashboard_api.dart';

class LearnerDetailPage extends StatefulWidget {
  final String learnerId;
  final DashboardApi api;

  const LearnerDetailPage({
    super.key,
    required this.learnerId,
    required this.api,
  });

  @override
  State<LearnerDetailPage> createState() => _LearnerDetailPageState();
}

class _LearnerDetailPageState extends State<LearnerDetailPage> {
  bool _loading = true;
  String? _error;
  LearnerDetailData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.fetchLearnerDetail(widget.learnerId);
      if (!mounted) return;
      setState(() {
        _data = res;
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

  Future<void> _confirmDeleteLearner() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF303134),
        title: const Text(
          'Delete Learner?',
          style: TextStyle(color: Color(0xFFE8EAED)),
        ),
        content: Text(
          'Are you sure you want to permanently delete ${_data?.name ?? 'this learner'} and all their practice records? This action cannot be undone.',
          style: const TextStyle(color: Color(0xFF9AA0A6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF9AA0A6)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _loading = true);
      try {
        await widget.api.deleteLearner(widget.learnerId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Learner deleted successfully.'),
            backgroundColor: Color(0xFF34A853),
          ),
        );
        Navigator.of(context).pop(true); // Return true so dashboard can refresh
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Failed to delete learner: ${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202124),
        foregroundColor: const Color(0xFFE8EAED),
        title: Text(_data?.name ?? 'Learner Detail'),
        actions: [
          if (_data != null)
            IconButton(
              tooltip: 'Delete Learner',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _confirmDeleteLearner,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8AB4F8)),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
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

    final data = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF8AB4F8),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildProfileCard(data),
          const SizedBox(height: 16),
          _buildStatsRow(data),
          const SizedBox(height: 16),
          _buildWeakLettersCard(data),
          const SizedBox(height: 24),
          _buildSkillProgressCard(data),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: const Text(
              'Lesson Assessments',
              style: TextStyle(
                color: Color(0xFFE8EAED),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildAssessmentList(data),
          if (data.assessmentErrors.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildAssessmentErrors(data),
          ],
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: const Text(
              'Adaptive Decision Support',
              style: TextStyle(
                color: Color(0xFFE8EAED),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildPredictionList(data),
          const SizedBox(height: 12),
          _buildEvaluationAvailability(),
          const SizedBox(height: 16),
          _buildAdaptiveQuestionList(data),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: const Text(
              'Recent Attempts',
              style: TextStyle(
                color: Color(0xFFE8EAED),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildAttemptsList(data),
        ],
      ),
    );
  }

  Widget _buildProfileCard(LearnerDetailData data) {
    return Card(
      color: const Color(0xFF303134),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data.name,
                    style: const TextStyle(
                      color: Color(0xFFE8EAED),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusBadge(data.status),
              ],
            ),
            const SizedBox(height: 12),
            if (data.batch != null && data.batch!.isNotEmpty)
              _infoRow(Icons.group, 'Batch', data.batch!),
            if (data.phone != null && data.phone!.isNotEmpty)
              _infoRow(Icons.phone, 'Phone', data.phone!),
            if (data.email != null && data.email!.isNotEmpty)
              _infoRow(Icons.email, 'Email', data.email!),
            _infoRow(Icons.language, 'Language', data.preferredLanguage),
            if (data.lastActiveAt != null)
              _infoRow(
                Icons.access_time,
                'Last Active',
                _formatDate(data.lastActiveAt!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF9AA0A6)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE8EAED),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(LearnerDetailData data) {
    return Row(
      children: [
        Expanded(
          child: _statBox(
            'Accuracy',
            '${data.accuracyPct}%',
            data.accuracyPct >= 80
                ? const Color(0xFF34A853)
                : data.accuracyPct < 60
                ? Colors.redAccent
                : const Color(0xFFFBBC04),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statBox(
            '7d Attempts',
            '${data.attempts7d}',
            const Color(0xFF8AB4F8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statBox(
            'Total',
            '${data.totalAttempts}',
            const Color(0xFFE8EAED),
          ),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF303134),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildWeakLettersCard(LearnerDetailData data) {
    return Card(
      color: const Color(0xFF303134),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Weak Letters / Skills',
              style: TextStyle(
                color: Color(0xFF9AA0A6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            if (data.topWeakLetters.isEmpty)
              const Text(
                'None detected yet — great progress!',
                style: TextStyle(color: Color(0xFF34A853), fontSize: 14),
              )
            else
              Wrap(
                spacing: 8,
                children: data.topWeakLetters
                    .map(
                      (letter) => Chip(
                        backgroundColor: const Color(0xFF3C4043),
                        label: Text(
                          letter,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillProgressCard(LearnerDetailData data) {
    return Card(
      color: const Color(0xFF303134),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skill Accuracy, Mastery & Review',
              style: TextStyle(
                color: Color(0xFFE8EAED),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (data.skillProgress.isEmpty)
              const Text(
                'No synchronized skill-level practice is available yet.',
                style: TextStyle(color: Color(0xFF9AA0A6)),
              )
            else
              ...data.skillProgress.map((skill) {
                final mastery = skill.masteryEstimate
                    .clamp(0.0, 1.0)
                    .toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${skill.skillId} · ${skill.language}',
                        style: const TextStyle(
                          color: Color(0xFFE8EAED),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${skill.correctCount}/${skill.attempts} correct · '
                        '${skill.accuracyPct.toStringAsFixed(1)}% measured accuracy · '
                        '${(mastery * 100).toStringAsFixed(1)}% estimated BKT mastery',
                        style: const TextStyle(color: Color(0xFF9AA0A6)),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: mastery,
                        backgroundColor: const Color(0xFF202124),
                        color: skill.reviewDue
                            ? Colors.orangeAccent
                            : const Color(0xFF8AB4F8),
                        semanticsLabel:
                            'Estimated Bayesian Knowledge Tracing mastery for ${skill.skillId}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        skill.reviewDue
                            ? 'Review due now.'
                            : skill.nextReviewAt == null
                            ? 'No review date recorded.'
                            : 'Next review: ${_formatDate(skill.nextReviewAt!)}',
                        style: TextStyle(
                          color: skill.reviewDue
                              ? Colors.orangeAccent
                              : const Color(0xFF9AA0A6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildAttemptsList(LearnerDetailData data) {
    if (data.recentAttempts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No attempts recorded yet.',
            style: TextStyle(color: Color(0xFF9AA0A6)),
          ),
        ),
      );
    }

    return Column(
      children: data.recentAttempts.map((att) {
        final isCorrect = att.outcome == 'correct';
        return Card(
          color: const Color(0xFF303134),
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: Icon(
              isCorrect ? Icons.check_circle : Icons.cancel,
              color: isCorrect ? const Color(0xFF34A853) : Colors.redAccent,
            ),
            title: Text(
              att.skillId.isNotEmpty ? att.skillId : att.exerciseId,
              style: const TextStyle(
                color: Color(0xFFE8EAED),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${att.exerciseType} • ${att.responseTimeMs}ms'
              '${att.hintUsed ? ' • hint used' : ''}',
              style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
            ),
            trailing: att.createdAt != null
                ? Text(
                    _formatDate(att.createdAt!),
                    style: const TextStyle(
                      color: Color(0xFF9AA0A6),
                      fontSize: 12,
                    ),
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAssessmentList(LearnerDetailData data) {
    if (data.recentAssessments.isEmpty) {
      return const Card(
        color: Color(0xFF303134),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No lesson assessments have synchronized yet.',
            style: TextStyle(color: Color(0xFF9AA0A6)),
          ),
        ),
      );
    }
    return Column(
      children: data.recentAssessments.map((assessment) {
        final action = assessment.action.replaceAll('_', ' ');
        final outcome = switch (assessment.remediationSucceeded) {
          true => 'remediation succeeded',
          false => 'remediation needs more practice',
          null => assessment.decisionStatus.replaceAll('_', ' '),
        };
        final assigned = assessment.recommendedLessonId.isEmpty
            ? ''
            : '\nAssigned lesson: ${assessment.recommendedLessonId}';
        final skill = assessment.recommendedSkillId.isEmpty
            ? ''
            : '\nReinforcement skill: ${assessment.recommendedSkillId}';
        final mastery =
            assessment.masteryBefore == null || assessment.masteryAfter == null
            ? ''
            : '\nMastery: ${(assessment.masteryBefore! * 100).toStringAsFixed(1)}% to ${(assessment.masteryAfter! * 100).toStringAsFixed(1)}%';
        final method = assessment.decisionMethod == 'hybrid_ml_rules'
            ? '\nMethod: qualified model advice validated by deterministic curriculum rules'
            : '\nMethod: transparent deterministic rules';
        final difficulty =
            assessment.difficultyBefore == null ||
                assessment.difficultyAfter == null ||
                assessment.difficultyBefore == assessment.difficultyAfter
            ? ''
            : '\nValidated difficulty: ${assessment.difficultyBefore} to ${assessment.difficultyAfter}';
        final question = assessment.questionInstanceId == null
            ? ''
            : '\nA validated adaptive question was assigned.';
        final evidence = assessment.selectionEvidence;
        final eligibleScores = (evidence['eligible_skill_scores'] as List?)
                ?.whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList() ??
            const <Map<String, dynamic>>[];
        final selectedSkill = evidence['selected_skill_for_next_exercise'];
        final selectionMethod = evidence['adaptive_selection_method'];
        final decisionEvidence = <String>[
          if (selectionMethod is String && selectionMethod.isNotEmpty)
            selectionMethod == 'linucb_with_information_gain_forgetting_context'
                ? 'Selection policy: LinUCB with information gain and heuristic forgetting-risk context.'
                : 'Selection policy: deterministic information-gain and heuristic forgetting-risk cold-start rules.',
          if (selectedSkill is Map && selectedSkill['skill_id'] != null)
            'Selected skill: ${selectedSkill['skill_id']}.',
          if (evidence['bandit_observation_count'] is num &&
              (evidence['bandit_observation_count'] as num) > 0)
            'Persisted LinUCB outcome observations: ${evidence['bandit_observation_count']}.',
          if (evidence['tested_skills'] is List)
            'Assessment skill constraints: ${(evidence['tested_skills'] as List).join(', ')}.',
        ];
        return Card(
          color: const Color(0xFF303134),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: assessment.accuracyPct >= 80
                  ? const Color(0xFF34A853)
                  : const Color(0xFFFBBC04),
              foregroundColor: Colors.black,
              child: Text('${assessment.score}/${assessment.questionCount}'),
            ),
            title: Text(
              '${assessment.language}: ${assessment.lessonId}',
              style: const TextStyle(
                color: Color(0xFFE8EAED),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${assessment.accuracyPct.toStringAsFixed(1)}% - Next action: $action - $outcome$skill$assigned$mastery$method$difficulty$question\n${assessment.reason}',
              style: const TextStyle(color: Color(0xFF9AA0A6)),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (assessment.completedAt != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recorded: ${_formatDate(assessment.completedAt!)}',
                    style: const TextStyle(color: Color(0xFF9AA0A6)),
                  ),
                ),
              if (decisionEvidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final line in decisionEvidence)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(line,
                        style: const TextStyle(color: Color(0xFFBDC1C6))),
                  ),
              ],
              if (eligibleScores.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Persisted eligible-skill scores',
                    style: TextStyle(
                      color: Color(0xFFE8EAED),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final score in eligibleScores)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(
                      '${score['skill_id'] ?? 'Unknown skill'} · '
                      'policy score ${_formatEvidenceNumber(score['score'])} · '
                      'information gain ${_formatEvidenceNumber(score['information_gain_bits'])} bits · '
                      'heuristic forgetting risk ${score['forgetting_risk_estimate'] == null ? 'not estimated' : _formatEvidenceNumber(score['forgetting_risk_estimate'])}'
                      '${score['bandit_score'] == null ? '' : ' · LinUCB score ${_formatEvidenceNumber(score['bandit_score'])}'}'
                      '${score['review_due'] == true ? ' · review due' : ''}'
                      '${score['error_count'] == null ? '' : ' · recorded errors ${score['error_count']}'}',
                      style: const TextStyle(color: Color(0xFFBDC1C6)),
                    ),
                  ),
              ],
              if (assessment.remediationSucceeded != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Persisted decision outcome: ${assessment.remediationSucceeded! ? 'successful' : 'not successful'}; this outcome is used as bandit reward evidence.',
                      style: const TextStyle(color: Color(0xFF9AA0A6)),
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatEvidenceNumber(dynamic value) {
    if (value is num) return value.toStringAsFixed(3);
    return 'not recorded';
  }

  Widget _buildEvaluationAvailability() {
    return Card(
      color: const Color(0xFF303134),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Algorithm evaluation',
              style: TextStyle(
                color: Color(0xFFE8EAED),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This profile shows recorded learner outcomes and adaptive decisions. '
              'A baseline-versus-adaptive comparison is unavailable because '
              'counterfactual evaluation results are not persisted for this learner; '
              'no comparative performance metric is inferred here.',
              style: TextStyle(color: Color(0xFF9AA0A6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionList(LearnerDetailData data) {
    if (data.recentPredictions.isEmpty) {
      return const Card(
        color: Color(0xFF303134),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No adaptive prediction records are available. Learning continues with deterministic rules.',
            style: TextStyle(color: Color(0xFF9AA0A6)),
          ),
        ),
      );
    }
    return Column(
      children: data.recentPredictions.map((prediction) {
        final mode = prediction.usedQualifiedModel
            ? 'Qualified Resonant model advice${prediction.modelVersion == null ? '' : ' (${prediction.modelVersion})'}'
            : 'Deterministic cold-start fallback; no trained model changed progression';
        final risk = prediction.usedQualifiedModel
            ? '\nEstimated future error risk: ${(prediction.probabilityIncorrect * 100).toStringAsFixed(1)}%'
            : '';
        final outcome = switch (prediction.observedIncorrect) {
          true => '\nObserved next outcome: incorrect',
          false => '\nObserved next outcome: correct',
          null => '\nObserved next outcome: not available yet',
        };
        final fallback = prediction.fallbackReason == null
            ? ''
            : '\nFallback reason: ${prediction.fallbackReason}';
        return Card(
          color: const Color(0xFF303134),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(
              prediction.usedQualifiedModel
                  ? Icons.insights
                  : Icons.rule_folder,
              color: prediction.usedQualifiedModel
                  ? const Color(0xFF8AB4F8)
                  : const Color(0xFF9FE0B5),
            ),
            title: Text(
              '${prediction.language}: ${prediction.skillId}',
              style: const TextStyle(
                color: Color(0xFFE8EAED),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '$mode$risk$outcome$fallback\nFeature schema: ${prediction.featureSchemaVersion}',
              style: const TextStyle(color: Color(0xFF9AA0A6)),
            ),
            trailing: prediction.predictedAt == null
                ? null
                : Text(
                    _formatDate(prediction.predictedAt!),
                    style: const TextStyle(
                      color: Color(0xFF9AA0A6),
                      fontSize: 12,
                    ),
                  ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAdaptiveQuestionList(LearnerDetailData data) {
    if (data.recentAdaptiveQuestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      color: const Color(0xFF303134),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Validated Adaptive Questions',
              style: TextStyle(
                color: Color(0xFFE8EAED),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (final question in data.recentAdaptiveQuestions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  '${question.language} ${question.skillId}: ${question.questionSource.replaceAll('_', ' ')}, difficulty ${question.difficulty}, ${question.validationStatus.replaceAll('_', ' ')}. Mapping ${question.mappingVersion}; question ${question.questionVersion}.${question.generationFailure == null ? '' : ' Generated phrasing was rejected and the deterministic fallback was used.'}',
                  style: const TextStyle(color: Color(0xFFBDC1C6)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentErrors(LearnerDetailData data) {
    return Card(
      color: const Color(0xFF303134),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Repeated Assessment Errors',
              style: TextStyle(
                color: Color(0xFFE8EAED),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (final error in data.assessmentErrors)
              Text(
                '${error.skillId}: ${error.errorCategory.replaceAll('_', ' ')} (${error.errorCount})',
                style: const TextStyle(color: Color(0xFF9AA0A6)),
              ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
