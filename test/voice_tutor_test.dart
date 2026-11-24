import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:resonant_braille/tutor/http_tutor_gateway.dart';
import 'package:resonant_braille/tutor/voice_tutor_controller.dart';
import 'package:resonant_braille/tutor/local_braille_tutor.dart';
import 'package:resonant_braille/tutor/voice_tutor_panel.dart';
import 'package:resonant_braille/tutor/voice_command_parser.dart';
import 'package:resonant_braille/tutor/tutor_screen_context.dart';

class FakeSpeech implements SpeechRecognizer {
  bool available = true;
  void Function(String, bool)? onResult;
  int starts = 0;
  int cancels = 0;
  String? locale;
  Duration? listenTimeout;
  bool active = false;
  final List<void Function(String, bool)> callbacks = [];
  @override
  Future<bool> initialize(void Function(String) onError) async => available;
  @override
  Future<void> listen({
    required String locale,
    required Duration listenTimeout,
    required void Function(String, bool) onResult,
  }) async {
    starts++;
    active = true;
    this.locale = locale;
    this.listenTimeout = listenTimeout;
    this.onResult = onResult;
    callbacks.add(onResult);
  }

  @override
  Future<void> stop() async {
    active = false;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    active = false;
  }
}

class LocaleAwareFakeSpeech extends FakeSpeech
    implements SpeechRecognitionLocaleResolver {
  LocaleAwareFakeSpeech(this.availableLocale);
  final String? availableLocale;
  String? requestedLocale;

  @override
  Future<String?> resolveAvailableLocale(String requestedLocale) async {
    this.requestedLocale = requestedLocale;
    return availableLocale;
  }
}

class FakeGateway implements TutorGateway {
  String? question;
  List<TutorMessage> history = [];
  String? language;
  String? lessonContext;
  Object? failure;
  Future<TutorResponse> Function()? pendingResponse;
  int calls = 0;
  @override
  Future<TutorResponse> ask({
    required String question,
    required String language,
    required List<TutorMessage> history,
    required String lessonContext,
    required List<VerifiedBrailleExample> verifiedExamples,
  }) async {
    calls++;
    this.question = question;
    this.language = language;
    this.history = history;
    this.lessonContext = lessonContext;
    if (failure != null) throw failure!;
    if (pendingResponse != null) return pendingResponse!();
    return const TutorResponse(
      'Try the example in your lesson.',
      verifiedExamples: [
        VerifiedBrailleExample('a', [1]),
      ],
    );
  }
}

class FakeOutput implements TutorSpeechOutput {
  final List<String> spoken = [];
  bool holdPlayback = false;
  Completer<void>? playback;
  Future<void> Function()? beforeSpeak;
  @override
  Future<void> speak(String text) async {
    await beforeSpeak?.call();
    spoken.add(text);
    if (!holdPlayback) return;
    playback = Completer<void>();
    await playback!.future;
  }

  @override
  Future<void> stop() async {
    if (playback?.isCompleted == false) playback!.complete();
  }
}

VoiceTutorController makeController({
  FakeSpeech? speech,
  FakeGateway? gateway,
  FakeOutput? output,
}) => VoiceTutorController(
  speech: speech ?? FakeSpeech(),
  gateway: gateway ?? FakeGateway(),
  output: output ?? FakeOutput(),
  lessonContext: 'Chapter 2, letter practice',
  lessonExamples: const [
    VerifiedBrailleExample('a', [1]),
  ],
);

void main() {
  test(
    'app voice commands are parsed deterministically while questions are left for the tutor',
    () {
      expect(
        VoiceCommandParser.parse('Teach me the letter B')?.command,
        VoiceCommand.teachLetter,
      );
      expect(VoiceCommandParser.parse('Teach me the letter B')?.letter, 'B');
      expect(
        VoiceCommandParser.parse('Go to the next lesson')?.command,
        VoiceCommand.nextLesson,
      );
      expect(
        VoiceCommandParser.parse('Can you teach me about contractions?'),
        isNull,
      );
    },
  );

  test(
    'handled voice commands bypass the AI gateway and close only after spoken feedback',
    () async {
      final gateway = FakeGateway();
      final output = FakeOutput();
      var completed = false;
      final controller = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: gateway,
        output: output,
        lessonContext: 'Letter practice',
        localCommandHandler: (question) async =>
            question.toLowerCase() == 'start learning'
            ? 'Opening your next lesson.'
            : null,
        onLocalCommandComplete: () async => completed = true,
      );
      await controller.send('Start learning');
      expect(gateway.question, isNull);
      expect(output.spoken.single, 'Opening your next lesson.');
      expect(completed, isTrue);
      controller.dispose();
    },
  );

  test(
    'contextual command handler receives recent conversational turns',
    () async {
      final received = <List<TutorMessage>>[];
      final controller = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: FakeGateway(),
        output: FakeOutput(),
        lessonContext: 'Learning session',
        contextualCommandHandler: (question, turns) async {
          received.add(List<TutorMessage>.from(turns));
          return question == 'First request' ? 'First response.' : null;
        },
      );

      await controller.send('First request');
      await controller.send('Can you explain that differently?');

      expect(received.first, isEmpty);
      expect(received.last, hasLength(2));
      expect(received.last[0].text, 'First request');
      expect(received.last[1].text, 'First response.');
      expect(controller.reply, 'Try the example in your lesson.');
      controller.dispose();
    },
  );

  test(
    'Tutor sends a fresh structured screen snapshot with each question',
    () async {
      final gateway = FakeGateway();
      var activeQuestion = 'Question one';
      final controller = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: gateway,
        output: FakeOutput(),
        lessonContext: 'Initial context',
        screenContextProvider: () => TutorScreenContext(
          screenName: 'Lessons',
          language: 'Hindi',
          question: activeQuestion,
          options: const ['पहला', 'दूसरा'],
        ),
      );

      await controller.send('Explain this.');
      expect(gateway.lessonContext, contains('Question one'));
      expect(gateway.lessonContext, contains('Selected language: Hindi'));

      activeQuestion = 'Question two';
      await controller.send('Read my screen.');
      expect(gateway.lessonContext, contains('Question two'));
      expect(gateway.lessonContext, isNot(contains('Question one')));
      controller.dispose();
    },
  );

  test(
    'recognized navigation is dispatched to the active state callback',
    () async {
      var exerciseIndex = 1;
      final gateway = FakeGateway();
      final controller = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: gateway,
        output: FakeOutput(),
        lessonContext: 'Lesson state',
        localCommandHandler: (input) async {
          if (VoiceCommandParser.parse(input)?.command !=
              VoiceCommand.nextLesson) {
            return null;
          }
          exerciseIndex++;
          return 'Exercise $exerciseIndex.';
        },
      );

      await controller.send('Next.');
      expect(exerciseIndex, 2);
      expect(controller.reply, 'Exercise 2.');
      expect(gateway.question, isNull);
      controller.dispose();
    },
  );

  test(
    'demo pipeline distinguishes local commands from real backend calls',
    () async {
      final localEvents = <String>[];
      final local = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: FakeGateway(),
        output: FakeOutput(),
        lessonContext: 'Lesson',
        localCommandHandler: (_) async => 'Moving to the next lesson.',
        onDemoEvent: (type, _) => localEvents.add(type),
      );
      await local.send('Next lesson');
      expect(localEvents, contains('tutor_input_received'));
      expect(localEvents, contains('tutor_action_response_ready'));
      expect(localEvents, isNot(contains('tutor_backend_request_started')));
      local.dispose();

      final backendEvents = <String>[];
      final remote = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: FakeGateway(),
        output: FakeOutput(),
        lessonContext: 'Lesson',
        localCommandHandler: (_) async => null,
        onDemoEvent: (type, _) => backendEvents.add(type),
      );
      await remote.send('What is Braille?');
      expect(backendEvents, contains('tutor_backend_request_started'));
      expect(backendEvents, contains('tutor_response_generated'));
      remote.dispose();
    },
  );

  test('speech permission failure leaves typed questions available', () async {
    final speech = FakeSpeech()..available = false;
    final controller = makeController(speech: speech);
    await controller.startListening();
    expect(controller.state, VoiceTutorState.error);
    await controller.send('Explain a Braille cell');
    expect(controller.reply, 'Try the example in your lesson.');
    expect(controller.state, VoiceTutorState.idle);
    controller.dispose();
  });

  test('speech recognizer receives the selected learner locale', () async {
    final speech = FakeSpeech();
    final controller = VoiceTutorController(
      speech: speech,
      gateway: FakeGateway(),
      output: FakeOutput(),
      lessonContext: 'Kannada lesson',
      language: 'Kannada',
      locale: 'kn-IN',
    );

    await controller.startListening();

    expect(speech.locale, 'kn-IN');
    controller.dispose();
  });

  test('unavailable selected speech locale stops before listening', () async {
    final speech = LocaleAwareFakeSpeech(null);
    final statuses = <String>[];
    final controller = VoiceTutorController(
      speech: speech,
      gateway: FakeGateway(),
      output: FakeOutput(),
      lessonContext: 'Kannada lesson',
      language: 'Kannada',
      locale: 'kn-IN',
      onStatusAnnouncement: (message) async {
        statuses.add(message);
      },
    );

    await controller.startListening();

    expect(speech.requestedLocale, 'kn-IN');
    expect(speech.starts, 0);
    expect(controller.isListening, isFalse);
    expect(controller.errorMessage, contains('Kannada'));
    expect(controller.errorMessage, contains('English'));
    expect(statuses, isNot(contains('Listening. Speak now.')));
    controller.dispose();
  });

  test(
    'assessment TTS pause cancels listening and rejects stale speech callbacks',
    () async {
      final speech = FakeSpeech();
      final gateway = FakeGateway();
      final controller = makeController(speech: speech, gateway: gateway);
      await controller.startListening();
      final staleCallback = speech.callbacks.single;
      expect(speech.active, isTrue);

      await controller.pauseListeningForSpeech();
      staleCallback('Read the question', true);

      expect(speech.active, isFalse);
      expect(controller.state, VoiceTutorState.idle);
      expect(gateway.calls, 0);
      expect(controller.messages, isEmpty);
      controller.dispose();
    },
  );

  test('speech transcript submits a question and speaks the reply', () async {
    final speech = FakeSpeech();
    final gateway = FakeGateway();
    final output = FakeOutput();
    final controller = makeController(
      speech: speech,
      gateway: gateway,
      output: output,
    );
    await controller.startListening();
    expect(controller.state, VoiceTutorState.listening);
    speech.onResult!('Can you give me a hint?', true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.question, 'Can you give me a hint?');
    expect(output.spoken.single, contains('dots 1'));
    expect(controller.messages.map((message) => message.role), [
      'user',
      'assistant',
    ]);
    controller.dispose();
  });

  test('Kannada recognition transcript reaches tutor unchanged', () async {
    final speech = FakeSpeech();
    final gateway = FakeGateway();
    final controller = VoiceTutorController(
      speech: speech,
      gateway: gateway,
      output: FakeOutput(),
      lessonContext: 'Kannada lesson',
      language: 'Kannada',
      locale: 'kn-IN',
    );

    await controller.startListening();
    const transcript = 'ಬ್ರೈಲ್ ಎಂದರೇನು?';
    speech.onResult!(transcript, true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(speech.locale, 'kn-IN');
    expect(gateway.question, transcript);
    expect(gateway.language, 'Kannada');
    expect(controller.transcript, transcript);
    controller.dispose();
  });

  test('Hindi recognition transcript reaches tutor unchanged', () async {
    final speech = FakeSpeech();
    final gateway = FakeGateway();
    final controller = VoiceTutorController(
      speech: speech,
      gateway: gateway,
      output: FakeOutput(),
      lessonContext: 'Hindi lesson',
      language: 'Hindi',
      locale: 'hi-IN',
    );

    await controller.startListening();
    const transcript = 'ब्रेल क्या है?';
    speech.onResult!(transcript, true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(speech.locale, 'hi-IN');
    expect(gateway.question, transcript);
    expect(gateway.language, 'Hindi');
    expect(controller.transcript, transcript);
    controller.dispose();
  });

  test(
    'TTS finishes before microphone opens and never overlaps tutor speech',
    () async {
      final speech = FakeSpeech();
      final output = FakeOutput();
      final statuses = <String>[];
      final promptFinished = Completer<void>();
      output.beforeSpeak = () async {
        expect(speech.active, isFalse);
      };
      final controller = VoiceTutorController(
        speech: speech,
        gateway: FakeGateway(),
        output: output,
        lessonContext: 'Lesson',
        onStatusAnnouncement: (message) async {
          statuses.add(message);
          if (message == 'Listening. Speak now.') {
            expect(speech.active, isFalse);
            await promptFinished.future;
          }
        },
      );

      final start = controller.startListening();
      await Future<void>.delayed(Duration.zero);
      expect(speech.starts, 0);
      expect(controller.state, VoiceTutorState.preparingListening);
      promptFinished.complete();
      await start;
      expect(controller.isListening, isTrue);
      speech.onResult!('What is Braille?', true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(speech.active, isFalse);
      expect(controller.isListening, isFalse);
      expect(statuses, contains('Resonant is thinking.'));
      controller.dispose();
    },
  );

  test(
    'duplicate final and stale recognition callbacks submit only once',
    () async {
      final speech = FakeSpeech();
      final gateway = FakeGateway();
      final controller = makeController(speech: speech, gateway: gateway);
      await controller.startListening();
      final callback = speech.onResult!;

      callback('Explain the six-dot cell', true);
      callback('Explain the six-dot cell again', true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(gateway.calls, 1);
      expect(
        controller.messages.where((message) => message.role == 'user'),
        hasLength(1),
      );
      expect(controller.messages.first.text, 'Explain the six-dot cell');
      controller.dispose();
    },
  );

  test(
    'unsupported tutor language is stated instead of being spoken as English',
    () async {
      final gateway = FakeGateway()
        ..pendingResponse = () async => const TutorResponse(
          'Hindi tutor support is not validated yet.',
          source: 'unsupported_language',
        );
      final output = FakeOutput();
      final controller = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: gateway,
        output: output,
        lessonContext: 'Hindi lesson',
        language: 'Hindi',
      );

      await controller.send('मुझे मदद चाहिए');

      expect(gateway.language, 'Hindi');
      expect(controller.state, VoiceTutorState.error);
      expect(controller.errorMessage, contains('not validated'));
      expect(output.spoken, isEmpty);
      controller.dispose();
    },
  );

  test(
    'listening, thinking, and recognition errors produce spoken status messages',
    () async {
      final speech = FakeSpeech();
      final status = <String>[];
      final controller = VoiceTutorController(
        speech: speech,
        gateway: FakeGateway(),
        output: FakeOutput(),
        lessonContext: 'Current lesson',
        onStatusAnnouncement: (message) async {
          status.add(message);
        },
      );
      await controller.startListening();
      expect(speech.starts, 1);
      expect(status.first, 'Listening. Speak now.');
      speech.onResult!('What is Braille?', true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(status, contains('Resonant is thinking.'));
      controller.dispose();

      final deniedStatus = <String>[];
      final denied = VoiceTutorController(
        speech: FakeSpeech()..available = false,
        gateway: FakeGateway(),
        output: FakeOutput(),
        lessonContext: 'Current lesson',
        onStatusAnnouncement: (message) async {
          deniedStatus.add(message);
        },
      );
      await denied.startListening();
      expect(
        deniedStatus.last,
        contains('permission or speech recognition is unavailable'),
      );
      denied.dispose();
    },
  );

  test(
    'empty speech results are announced as errors without sending',
    () async {
      final speech = FakeSpeech();
      final gateway = FakeGateway();
      final controller = makeController(speech: speech, gateway: gateway);
      await controller.startListening();
      speech.onResult!('', true);
      expect(controller.state, VoiceTutorState.error);
      expect(controller.errorMessage, contains('No speech was recognized'));
      expect(gateway.question, isNull);
      controller.dispose();
    },
  );

  test('typed follow-up, reply replay, stop, and clear work', () async {
    final output = FakeOutput();
    final controller = makeController(output: output);
    await controller.send('Explain the six dot positions');
    expect(controller.reply, isNotEmpty);
    await controller.replay();
    expect(output.spoken, hasLength(2));
    await controller.stopSpeaking();
    expect(controller.state, VoiceTutorState.idle);
    await controller.clearConversation();
    expect(controller.messages, isEmpty);
    expect(controller.reply, isEmpty);
    controller.dispose();
  });

  test('stop speaking interrupts active playback', () async {
    final output = FakeOutput()..holdPlayback = true;
    final controller = makeController(output: output);
    final request = controller.send('Explain Braille');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, VoiceTutorState.speaking);
    await controller.stopSpeaking();
    await request;
    expect(output.playback!.isCompleted, isTrue);
    expect(controller.state, VoiceTutorState.idle);
    controller.dispose();
  });

  test('typed stop speaking command interrupts tutor playback', () async {
    final output = FakeOutput()..holdPlayback = true;
    final controller = makeController(output: output);
    final response = controller.send('Explain Braille');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, VoiceTutorState.speaking);
    await controller.send('Stop speaking');
    await response;
    expect(output.playback!.isCompleted, isTrue);
    expect(controller.state, VoiceTutorState.idle);
    controller.dispose();
  });

  test(
    'backend failure preserves the question and shows typed retry guidance',
    () async {
      final gateway = FakeGateway()
        ..failure = StateError('network unavailable');
      final controller = makeController(gateway: gateway);
      await controller.send('What is a Braille cell?');
      expect(controller.state, VoiceTutorState.error);
      expect(controller.messages.first.text, 'What is a Braille cell?');
      expect(controller.errorMessage, contains('try again'));
      controller.dispose();
    },
  );

  test(
    'Hindi and Kannada backend failures produce localized safe errors',
    () async {
      final cases = [
        ('Hindi', 'ब्रेल क्या है?', 'ऑनलाइन ट्यूटर से संपर्क नहीं हो पाया'),
        ('Kannada', 'ಬ್ರೈಲ್ ಎಂದರೇನು?', 'ಆನ್‌ಲೈನ್ ಟ್ಯೂಟರ್ ಸಂಪರ್ಕವಾಗಲಿಲ್ಲ'),
      ];
      for (final (language, question, expectedError) in cases) {
        final gateway = FakeGateway()
          ..failure = StateError('network unavailable');
        var offlineCalled = false;
        final announcements = <String>[];
        final controller = VoiceTutorController(
          speech: FakeSpeech(),
          gateway: gateway,
          output: FakeOutput(),
          lessonContext: '$language Braille introduction',
          language: language,
          offlineTutorHandler: (_, __, ___, ____) {
            offlineCalled = true;
            return const TutorResponse('Unverified English answer');
          },
          onStatusAnnouncement: (message) async => announcements.add(message),
        );

        await controller.send(question);

        expect(controller.state, VoiceTutorState.error);
        expect(controller.errorMessage, contains(expectedError));
        expect(controller.reply, isEmpty);
        expect(offlineCalled, isFalse);
        expect(announcements, contains(contains(expectedError)));
        controller.dispose();
      }
    },
  );

  test(
    'HTTP tutor gateway response flows through controller and speech output',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'answer': 'ब्रेल स्पर्श से पढ़ने की प्रणाली है।',
              'source': 'ollama_rag',
              'verified_examples': [],
              'sources': [],
            }),
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final output = FakeOutput();
      final controller = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: HttpTutorGateway(
          client: client,
          baseUri: Uri.parse('http://resonant.test'),
        ),
        output: output,
        lessonContext: 'Hindi Braille introduction',
        language: 'Hindi',
        locale: 'hi-IN',
      );

      await controller.send('ब्रेल क्या है?');

      final payload = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(captured.method, 'POST');
      expect(captured.url.path, '/ask');
      expect(payload['language'], 'Hindi');
      expect(
        controller.reply,
        'ब्रेल स्पर्श से पढ़ने की प्रणाली है।',
        reason: 'state=${controller.state}; error=${controller.errorMessage}',
      );
      expect(output.spoken.single, contains(controller.reply));
      expect(controller.state, VoiceTutorState.idle);
      client.close();
      controller.dispose();
    },
  );

  test(
    'backend failure falls back to verified offline word teaching',
    () async {
      final gateway = FakeGateway()
        ..failure = StateError('network unavailable');
      final output = FakeOutput();
      final controller = VoiceTutorController(
        speech: FakeSpeech(),
        gateway: gateway,
        output: output,
        lessonContext: 'Word lesson CAT',
        offlineTutorHandler: (question, history, context, examples) =>
            LocalBrailleTutor.answer(
              question: question,
              history: history,
              lessonContext: context,
              lessonExamples: examples,
            ),
      );
      await controller.send('How do I write CAT in Braille?');
      expect(controller.state, VoiceTutorState.idle);
      expect(controller.errorMessage, isNull);
      expect(controller.reply, contains('capital-word indicator'));
      expect(controller.verifiedExamples.single.cells, [32, 32, 9, 1, 30]);
      expect(output.spoken.single, contains('dot 1'));
      controller.dispose();
    },
  );

  test('tutor network timeout returns a usable retry state', () async {
    final gateway = FakeGateway()
      ..pendingResponse = () => Completer<TutorResponse>().future;
    final controller = VoiceTutorController(
      speech: FakeSpeech(),
      gateway: gateway,
      output: FakeOutput(),
      lessonContext: 'Current lesson',
      requestTimeout: const Duration(milliseconds: 5),
    );
    await controller.send('Please explain');
    expect(controller.state, VoiceTutorState.error);
    expect(controller.errorMessage, contains('too long'));
    controller.dispose();
  });

  testWidgets(
    'voice tutor starts by gesture and offers accessible typed input',
    (tester) async {
      final controller = makeController();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VoiceTutorPanel(controller: controller)),
        ),
      );
      expect(find.byKey(const ValueKey('tutor-talk-button')), findsNothing);
      expect(find.byKey(const ValueKey('tutor-state-gesture')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tutor-typed-question')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Raw audio and this conversation are not saved'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('tutor-typed-question')),
        'Tell me about Braille',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Resonant: Try the example'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'opening tutor for voice begins listening without a talk button',
    (tester) async {
      final speech = FakeSpeech();
      final controller = makeController(speech: speech);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceTutorPanel(
              controller: controller,
              startListeningOnOpen: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(speech.starts, 1);
      expect(controller.state, VoiceTutorState.listening);
      expect(find.byKey(const ValueKey('tutor-talk-button')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('tutor dialog fits a short landscape phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = makeController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceTutorPanel(controller: controller)),
      ),
    );
    expect(find.byKey(const ValueKey('tutor-typed-question')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
