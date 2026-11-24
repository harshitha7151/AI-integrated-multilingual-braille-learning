import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/learning/adaptive_word_recommender.dart';

void main() {
  const recommender = AdaptiveWordRecommender();

  test('preserves verified curriculum order without learner evidence', () {
    final result = recommender.recommend(
      language: AppLanguage.english,
      candidates: const ['CAT', 'BAT', 'MAT'],
      history: const [],
    );

    expect(result.rankedWords, ['CAT', 'BAT', 'MAT']);
    expect(result.focusCharacters, isEmpty);
    expect(result.method, 'deterministic_rules');
    expect(result.reason, isNot(contains('not trained ML')));
  });

  test('moves words containing a repeatedly weak character first', () {
    final result = recommender.recommend(
      language: AppLanguage.english,
      candidates: const ['SUN', 'DOG', 'HAT', 'PEN'],
      history: const [
        {
          'language': 'English',
          'skill_id': 'english-letter-p',
          'outcome': 'incorrect',
          'attempt_number': 3,
          'hint_used': true,
        },
        {
          'language': 'English',
          'skill_id': 'english-letter-p',
          'outcome': 'incorrect',
          'attempt_number': 2,
          'hint_used': false,
        },
      ],
    );

    expect(result.rankedWords.first, 'PEN');
    expect(result.focusCharacters, contains('p'));
    expect(result.reason, contains('rule-based, not trained ML'));
  });

  test(
    'uses the identified English error character for contextual remediation',
    () {
      final result = const AdaptiveWordRecommender().recommend(
        language: AppLanguage.english,
        candidates: ['DOG', 'CAB'],
        history: [
          {
            'language': 'English',
            'outcome': 'incorrect',
            'skill_id': 'en-word-test',
            'expected_response': {'text': 'CAT'},
            'submitted_response': {'target_character': 'c'},
            'attempt_number': 1,
            'hint_used': false,
          },
        ],
      );
      expect(result.rankedWords.first, 'CAB');
      expect(result.focusCharacters, contains('c'));
    },
  );

  test('supports script-specific Hindi evidence without inventing words', () {
    const candidates = ['अब', 'कमल', 'जल', 'घर', 'मन'];
    final result = recommender.recommend(
      language: AppLanguage.hindi,
      candidates: candidates,
      history: const [
        {
          'language': 'Hindi',
          'skill_id': 'hi-bharati-घ',
          'outcome': 'incorrect',
          'attempt_number': 2,
          'hint_used': false,
        },
      ],
    );

    expect(result.rankedWords.first, 'घर');
    expect(result.rankedWords.toSet(), candidates.toSet());
  });

  test(
    'word observations target only the failed letter and retain history',
    () {
      final history = [
        {
          'language': 'English',
          'outcome': 'incorrect',
          'expected_response': {'text': 'CAT'},
          'attempt_number': 1,
          'submitted_response': {
            'skill_observations': [
              {
                'character': 'c',
                'skill_id': 'english-letter-c',
                'correct': true,
              },
              {
                'character': 'a',
                'skill_id': 'english-letter-a',
                'correct': true,
              },
              {
                'character': 't',
                'skill_id': 'english-letter-t',
                'correct': false,
              },
            ],
          },
        },
        {
          'language': 'English',
          'outcome': 'incorrect',
          'expected_response': {'text': 'DOG'},
          'attempt_number': 1,
          'submitted_response': {
            'skill_observations': [
              {
                'character': 'd',
                'skill_id': 'english-letter-d',
                'correct': false,
              },
              {
                'character': 'o',
                'skill_id': 'english-letter-o',
                'correct': true,
              },
              {
                'character': 'g',
                'skill_id': 'english-letter-g',
                'correct': true,
              },
            ],
          },
        },
        {
          'language': 'English',
          'outcome': 'correct',
          'attempt_number': 2,
          'submitted_response': {
            'skill_observations': [
              {
                'character': 't',
                'skill_id': 'english-letter-t',
                'correct': true,
              },
            ],
          },
        },
      ];

      final result = recommender.recommend(
        language: AppLanguage.english,
        candidates: const ['CAT', 'DOG', 'BAT', 'DOT'],
        history: history,
      );

      expect(result.rankedWords.first, 'DOT');
      expect(result.focusCharacters, ['d', 't']);
      expect(result.characterEvidence['t'], greaterThan(0));
      expect(result.characterEvidence.containsKey('c'), isFalse);
    },
  );

  test('Bharati conjunct errors prioritize verified words containing them', () {
    final result = recommender.recommend(
      language: AppLanguage.hindi,
      candidates: const ['ज्ञान', 'कमल', 'जल'],
      history: const [
        {
          'language': 'Hindi',
          'outcome': 'incorrect',
          'submitted_response': {
            'skill_observations': [
              {
                'character': 'ज्ञ',
                'skill_id': 'hi-bharati-ज्ञ',
                'correct': false,
              },
            ],
          },
        },
      ],
    );

    expect(result.rankedWords.first, 'ज्ञान');
    expect(result.focusCharacters, ['ज्ञ']);
  });
}
