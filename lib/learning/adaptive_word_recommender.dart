import '../core/braille/braille_dispatcher.dart';

typedef LearningEvent = Map<String, dynamic>;

class AdaptiveWordRecommendation {
  final List<String> rankedWords;
  final List<String> focusCharacters;
  final String reason;
  final Map<String, double> characterEvidence;

  const AdaptiveWordRecommendation({
    required this.rankedWords,
    required this.focusCharacters,
    required this.reason,
    required this.characterEvidence,
  });

  String get method => 'deterministic_rules';
}

/// Ranks only already-validated curriculum words using local learning history.
///
/// This is deliberately an explainable cold-start policy, not a trained ML
/// model. It cannot add words, change Braille mappings, or bypass curriculum
/// prerequisites. Incorrect attempts, repeated attempts, and hints increase a
/// character's practice weight; later correct evidence reduces it slightly.
class AdaptiveWordRecommender {
  const AdaptiveWordRecommender();

  AdaptiveWordRecommendation recommend({
    required AppLanguage language,
    required List<String> candidates,
    required List<LearningEvent> history,
  }) {
    final words = List<String>.from(candidates);
    if (words.length < 2) {
      return AdaptiveWordRecommendation(
        rankedWords: words,
        focusCharacters: const [],
        reason: words.isEmpty
            ? 'No verified curriculum word is available.'
            : 'Only one verified curriculum word is eligible.',
        characterEvidence: const {},
      );
    }

    final errorEvidence = <String, double>{};
    final successfulEvidence = <String, int>{};
    for (final event in history) {
      if (!_matchesLanguage(event['language'], language)) continue;

      final submitted = event['submitted_response'];
      final observations = submitted is Map
          ? submitted['skill_observations']
          : null;
      if (observations is List && observations.isNotEmpty) {
        final attempts = (event['attempt_number'] as num?)?.toInt() ?? 1;
        final multiplier = 1.0 + (attempts - 1).clamp(0, 5) * 0.15;
        for (final item in observations.whereType<Map>()) {
          final character = item['character'];
          if (character is! String || character.isEmpty) continue;
          final normalized = _normalizeCharacter(character, language);
          if (item['correct'] == true) {
            successfulEvidence.update(
              normalized,
              (value) => value + 1,
              ifAbsent: () => 1,
            );
          } else if (item['correct'] == false) {
            errorEvidence.update(
              normalized,
              (value) => value + 3.0 * multiplier,
              ifAbsent: () => 3.0 * multiplier,
            );
          }
        }
        continue;
      }

      final target = _eventTarget(event, language, words);
      if (target == null || target.isEmpty) continue;

      final isIncorrect = event['outcome'] == 'incorrect';
      var weight = 3.0;
      final attempts = (event['attempt_number'] as num?)?.toInt() ?? 1;
      if (attempts > 1) weight += (attempts - 1).clamp(0, 5) * 0.4;
      if (event['hint_used'] == true) weight += 0.75;

      for (final character in _learningCharacters(target, language)) {
        if (isIncorrect) {
          errorEvidence.update(
            character,
            (value) => (value + weight).clamp(0.0, 1000.0),
            ifAbsent: () => weight.clamp(0.0, 1000.0),
          );
        } else if (event['outcome'] == 'correct') {
          successfulEvidence.update(
            character,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }

    // Correct practice reduces the priority of a skill, but it never deletes
    // historical error evidence; otherwise one later success erases the fact
    // that remediation was needed.
    final evidence = <String, double>{
      for (final character in errorEvidence.keys)
        character:
            errorEvidence[character]! /
            (1 + (successfulEvidence[character] ?? 0) * 0.5),
    };

    final indexed = words.indexed.toList();
    double score(String word) => _learningCharacters(
      word,
      language,
    ).fold(0.0, (total, character) => total + (evidence[character] ?? 0));
    indexed.sort((left, right) {
      final scoreOrder = score(right.$2).compareTo(score(left.$2));
      return scoreOrder != 0 ? scoreOrder : left.$1.compareTo(right.$1);
    });
    final ranked = indexed.map((entry) => entry.$2).toList(growable: false);
    final focus = evidence.entries.where((entry) => entry.value > 0).toList()
      ..sort((left, right) {
        final weightOrder = right.value.compareTo(left.value);
        return weightOrder != 0 ? weightOrder : left.key.compareTo(right.key);
      });
    final focusCharacters = focus
        .take(3)
        .map((entry) => entry.key)
        .toList(growable: false);
    final hasEvidence = focusCharacters.isNotEmpty && score(ranked.first) > 0;
    return AdaptiveWordRecommendation(
      rankedWords: ranked,
      focusCharacters: focusCharacters,
      reason: hasEvidence
          ? 'Deterministic recommendation: ${ranked.first} is first because recorded errors, repeated attempts, or hints involve ${focusCharacters.join(', ')}. This is rule-based, not trained ML.'
          : 'No learner-specific character error evidence is available yet, so the verified curriculum order is preserved.',
      characterEvidence: Map.unmodifiable(evidence),
    );
  }

  bool _matchesLanguage(Object? value, AppLanguage language) {
    if (value == null) return true;
    final normalized = value.toString().trim().toLowerCase();
    return normalized == language.code ||
        normalized == language.storageName.toLowerCase();
  }

  String? _eventTarget(
    LearningEvent event,
    AppLanguage language,
    List<String> candidates,
  ) {
    final submitted = event['submitted_response'];
    if (event['outcome'] == 'incorrect' && submitted is Map) {
      final targetCharacter = submitted['target_character'];
      if (language == AppLanguage.english &&
          targetCharacter is String &&
          targetCharacter.runes.length == 1 &&
          candidates.any(
            (word) =>
                word.toLowerCase().contains(targetCharacter.toLowerCase()),
          )) {
        return targetCharacter;
      }
    }
    final skill = event['skill_id']?.toString() ?? '';
    final prefix = switch (language) {
      AppLanguage.english => 'english-letter-',
      AppLanguage.hindi => 'hi-bharati-',
      AppLanguage.kannada => 'kn-bharati-',
    };
    if (skill.startsWith(prefix) && skill.length > prefix.length) {
      return skill.substring(prefix.length);
    }

    final expected = event['expected_response'];
    if (expected is Map) {
      final target = expected['text'] ?? expected['choice'];
      if (target is String && target.isNotEmpty) return target;
    }

    final exerciseId = event['exercise_id']?.toString().toLowerCase() ?? '';
    for (final candidate in candidates) {
      if (exerciseId.contains(candidate.toLowerCase())) return candidate;
    }
    return null;
  }

  Iterable<String> _learningCharacters(
    String value,
    AppLanguage language,
  ) sync* {
    Iterable<String> units;
    try {
      units = BrailleDispatcher.encodeUnits(
        value,
        language,
      ).map((unit) => unit.text);
    } on Object {
      // Preserve safe deterministic ranking if an older curriculum word is
      // outside the current encoder's supported subset.
      units = value.runes.map(String.fromCharCode);
    }
    for (var character in units) {
      character = _normalizeCharacter(character, language);
      if (RegExp(r"[\s.,;:?!'\-]").hasMatch(character)) continue;
      yield character;
    }
  }

  String _normalizeCharacter(String character, AppLanguage language) =>
      language == AppLanguage.english ? character.toLowerCase() : character;
}
