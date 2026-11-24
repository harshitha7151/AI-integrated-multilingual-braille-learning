import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonant_braille/tutor/http_tutor_intent_interpreter.dart';
import 'package:resonant_braille/tutor/voice_command_parser.dart';
import 'package:resonant_braille/tutor/tutor_action_controller.dart';
import 'package:resonant_braille/learning/chapter_navigation_controller.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';

void main() {
  test(
    'converts validated model intent into an answer-selection candidate',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/interpret');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['language'], 'Kannada');
        expect((body['screen_context'] as Map)['options'], isNotEmpty);
        expect(body['available_actions'], contains('select_answer'));
        expect((body['history'] as List).length, 1);
        return http.Response(
          jsonEncode({
            'intent': 'select_answer',
            'target': null,
            'language_target': null,
            'letter': null,
            'option_index': 1,
            'confidence': 0.9,
            'clarification': null,
            'reasoning_summary':
                'The utterance selects the first visible option.',
          }),
          200,
        );
      });
      final result =
          await HttpTutorIntentInterpreter(
            client: client,
            baseUri: Uri.parse('http://localhost:8000'),
          ).interpret(
            utterance: 'I think the first answer',
            language: 'Kannada',
            screenContext: const {
              'screen': 'assessment',
              'options': ['option A', 'option B'],
            },
            recentTurns: const [
              {'role': 'user', 'content': 'Read my options.'},
            ],
            availableActions: const ['ask_tutor', 'select_answer'],
          );
      expect(result.command?.command, VoiceCommand.selectAnswer);
      expect(result.command?.target, 'option 1');
      expect(result.confidence, 0.9);
    },
  );

  test(
    'routes conceptual questions to the existing tutor without action',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'intent': 'ask_tutor',
            'target': null,
            'language_target': null,
            'letter': null,
            'option_index': null,
            'confidence': 0.88,
            'clarification': null,
            'reasoning_summary': 'This is a conceptual question.',
          }),
          200,
        ),
      );
      final result =
          await HttpTutorIntentInterpreter(
            client: client,
            baseUri: Uri.parse('http://localhost:8000'),
          ).interpret(
            utterance: 'Why are Braille dots numbered?',
            language: 'English',
            screenContext: const {'screen': 'lesson'},
            recentTurns: const [],
            availableActions: const ['ask_tutor', 'read_screen'],
          );
      expect(result.isTutorQuestion, isTrue);
      expect(result.command, isNull);
    },
  );

  test('converts low confidence into clarification, never an action', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'intent': 'go_to_lesson',
          'target': 'C',
          'language_target': null,
          'letter': null,
          'option_index': null,
          'confidence': 0.4,
          'clarification': null,
          'reasoning_summary': 'Possibly a navigation request.',
        }),
        200,
      ),
    );
    final result =
        await HttpTutorIntentInterpreter(
          client: client,
          baseUri: Uri.parse('http://localhost:8000'),
        ).interpret(
          utterance: 'that one',
          language: 'English',
          screenContext: const {'screen': 'assessment'},
          recentTurns: const [],
          availableActions: const ['ask_tutor', 'go_to_lesson'],
        );
    expect(result.command, isNull);
    expect(result.clarification, isNotNull);
  });

  test(
    'semantic interpretation forwards structured context and capabilities',
    () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['utterance'], 'Maybe I should work on vocabulary instead.');
        expect(body['available_actions'], ['ask_tutor', 'open_word_lessons']);
        expect(
          (body['screen_context'] as Map)['state']['assessment_active'],
          true,
        );
        expect(body['history'], [
          {'role': 'assistant', 'content': 'You are practicing letters.'},
        ]);
        return http.Response(
          jsonEncode({
            'intent': 'open_word_lessons',
            'target': null,
            'language_target': null,
            'letter': null,
            'option_index': null,
            'confidence': 0.93,
            'clarification': null,
            'reasoning_summary': 'Learner requests another available activity.',
          }),
          200,
        );
      });
      final result =
          await HttpTutorIntentInterpreter(
            client: client,
            baseUri: Uri.parse('http://localhost:8000'),
          ).interpret(
            utterance: 'Maybe I should work on vocabulary instead.',
            language: 'English',
            screenContext: const {
              'screen': 'assessment',
              'state': {'assessment_active': true},
            },
            recentTurns: const [
              {'role': 'assistant', 'content': 'You are practicing letters.'},
            ],
            availableActions: const ['ask_tutor', 'open_word_lessons'],
          );
      expect(result.command?.command, VoiceCommand.goToChapter);
      expect(result.command?.target, 'words');
    },
  );

  test(
    'semantic activity proposal reaches real navigation validation',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'intent': 'go_to_chapter',
            'target': 'words',
            'language_target': null,
            'letter': null,
            'option_index': null,
            'confidence': 0.91,
            'clarification': null,
            'reasoning_summary': 'The learner requested word practice.',
          }),
          200,
        ),
      );
      final proposal =
          await HttpTutorIntentInterpreter(
            client: client,
            baseUri: Uri.parse('http://localhost:8000'),
          ).interpret(
            utterance: 'Let us work on vocabulary instead.',
            language: 'English',
            screenContext: const {'screen': 'assessment'},
            recentTurns: const [],
            availableActions: const [
              'ask_tutor',
              'go_to_chapter',
              'open_word_lessons',
            ],
          );
      final action = const TutorActionController().resolve(
        proposal.command!,
        const TutorActionContext(
          navigation: LearningNavigationContext(
            language: AppLanguage.english,
            chapterIndex: 1,
            lessonIndex: 2,
            wordChapterIndex: 0,
            englishLetterCourseComplete: false,
          ),
          learningPaused: false,
          assessmentActive: true,
          wordTestAvailable: false,
          moduleTestAvailable: false,
          hasRevisionHistory: false,
          hasTargetedPractice: false,
        ),
      );

      expect(proposal.command?.command, VoiceCommand.goToChapter);
      expect(action.isReady, isTrue);
      expect(action.navigation?.chapterIndex, 2);
      expect(action.navigation?.wordChapterIndex, 0);
    },
  );
}
