import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';
import 'package:resonant_braille/learning/lesson_progress_store.dart';
import 'package:resonant_braille/learning/onboarding_store.dart';
import 'package:resonant_braille/learning/learner_account_store.dart';
import 'package:resonant_braille/main.dart';

class _DoneOnboarding implements OnboardingProgress {
  @override
  Future<bool> isComplete() async => true;
  @override
  Future<void> markComplete() async {}
  @override
  Future<int> currentStep() async => 10;
  @override
  Future<void> saveStep(int step) async {}
}

class _MemoryResumeStore extends LessonProgressStore {
  _MemoryResumeStore() : super(File('unused-multilingual-test.json'));
  Map<String, dynamic> state = {};
  @override
  Future<List<Map<String, dynamic>>> readEvents() async => [];
  @override
  Future<Map<String, dynamic>> readResumeState() async => state;
  @override
  Future<void> saveResumeState({
    required String languageCode,
    required int chapter,
    required int lessonItem,
    required int wordLessonIndex,
  }) async {
    state = {
      'language': languageCode,
      'chapter': chapter,
      'lesson_item': lessonItem,
      'word_lesson_index': wordLessonIndex,
    };
  }
}

Future<void> swipeIntroduction(
  WidgetTester tester, {
  required bool left,
}) async {
  final surface = find.byKey(const ValueKey('vernacular-introduction-surface'));
  final rect = tester.getRect(surface);
  final y = rect.center.dy;
  final first = await tester.startGesture(
    Offset(rect.left + rect.width * 0.35, y),
    pointer: 71,
  );
  final second = await tester.startGesture(
    Offset(rect.left + rect.width * 0.65, y),
    pointer: 72,
  );
  final delta = left ? -150.0 : 150.0;
  await first.moveBy(Offset(delta, 0));
  await second.moveBy(Offset(delta, 0));
  await tester.pump();
  await first.up();
  await second.up();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('resonant/physical_tutor', (message) async {
        final codec = const StandardMethodCodec();
        codec.decodeMethodCall(message);
        return codec.encodeSuccessEnvelope(null);
      });
  test(
    'BrailleDispatcher converts Hindi and Kannada NIEPVD dot numbers to bitmasks',
    () {
      expect(BrailleDispatcher.bitmaskFromDotNumber(1), 1);
      expect(BrailleDispatcher.bitmaskFromDotNumber(13), 5);
      expect(BrailleDispatcher.dotsForBitmask(5), [1, 3]);
      expect(
        BrailleDispatcher.encodeToBitmasks('\u0905', AppLanguage.hindi),
        isNotEmpty,
      );
      expect(
        BrailleDispatcher.encodeToBitmasks('\u0C85', AppLanguage.kannada),
        isNotEmpty,
      );
    },
  );

  test('LessonCatalog includes Hindi and Kannada curricula', () {
    expect(LessonCatalog.chaptersFor(AppLanguage.hindi).length, 5);
    expect(LessonCatalog.chaptersFor(AppLanguage.kannada).length, 5);
    expect(LessonCatalog.hindi[1].exercises, isNotEmpty);
    expect(LessonCatalog.kannada[1].exercises, isNotEmpty);
  });

  test(
    'vernacular letter courses and word tests use verified encodable content',
    () {
      for (final language in [AppLanguage.hindi, AppLanguage.kannada]) {
        final chapters = LessonCatalog.chaptersFor(language);
        expect(chapters[1].exercises, isNotEmpty);
        expect(chapters[2].exercises, isNotEmpty);
        for (final exercise in [
          ...chapters[1].exercises,
          ...chapters[2].exercises,
        ]) {
          expect(
            () => BrailleDispatcher.encodeToBitmasks(exercise.answer, language),
            returnsNormally,
            reason: '${language.storageName}: ${exercise.answer}',
          );
          expect(
            BrailleDispatcher.encodeToBitmasks(exercise.answer, language),
            isNotEmpty,
          );
        }
      }
    },
  );

  testWidgets(
    'Lesson Navigator switches language to Hindi and Kannada and persists resume state',
    (tester) async {
      final store = _MemoryResumeStore();
      await tester.pumpWidget(
        MaterialApp(
          home: ResonantHome(
            onboardingProgress: _DoneOnboarding(),
            lessonProgressStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-lesson-navigator')));
      await tester.pumpAndSettle();
      final hindi = find
          .textContaining('\u0939\u093F\u0928\u094D\u0926\u0940')
          .first;
      await tester.tap(hindi);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('\u0939\u093F\u0928\u094D\u0926\u0940'),
        findsWidgets,
      );
      expect(store.state['language'], AppLanguage.hindi.code);
      await tester.tap(find.byKey(const ValueKey('open-lesson-navigator')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.textContaining('\u0C95\u0CA8\u0CCD\u0CA8\u0CA1').first,
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(store.state['language'], AppLanguage.kannada.code);
    },
  );

  testWidgets(
    'Hindi introduction advances and reverses with two-finger horizontal swipes only',
    (tester) async {
      final store = _MemoryResumeStore();
      const account = LearnerAccount(
        learnerId: 'learner-hindi',
        learnerCode: '123456',
        name: 'Anu',
        preferredLanguage: 'Hindi',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ResonantHome(
            learnerAccount: account,
            onboardingProgress: _DoneOnboarding(),
            lessonProgressStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('हिन्दी'), findsWidgets);
      expect(
        find.textContaining(LessonCatalog.hindi.first.title),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey('vernacular-introduction-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('advance-braille-introduction')),
        findsNothing,
      );
      expect(find.textContaining('अगला भाग सुनें'), findsNothing);
      expect(find.textContaining('ब्रेल परिचय'), findsOneWidget);
      expect(find.textContaining('बाएं कॉलम'), findsNothing);
      await swipeIntroduction(tester, left: false);
      expect(find.text('परिचय भाग 1 में से 5'), findsOneWidget);
      await swipeIntroduction(tester, left: true);
      expect(find.text('परिचय भाग 2 में से 5'), findsOneWidget);
      await swipeIntroduction(tester, left: false);
      expect(find.text('परिचय भाग 1 में से 5'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await swipeIntroduction(tester, left: true);
      }
      expect(find.text('परिचय भाग 5 में से 5'), findsOneWidget);
      expect(find.textContaining('सटीक हिंदी रूप'), findsOneWidget);
      await swipeIntroduction(tester, left: true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('vernacular-introduction-surface')),
        findsNothing,
      );
      expect(find.text('Learn अ'), findsOneWidget);
      expect(find.textContaining(LessonCatalog.hindi[1].title), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(store.state['chapter'], 1);
      expect(store.state['lesson_item'], 0);
    },
  );

  testWidgets(
    'Kannada introduction uses horizontal swipes and keeps vertical swipes from skipping steps',
    (tester) async {
      final store = _MemoryResumeStore();
      const account = LearnerAccount(
        learnerId: 'learner-kannada',
        learnerCode: '123457',
        name: 'Kavi',
        preferredLanguage: 'Kannada',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ResonantHome(
            learnerAccount: account,
            onboardingProgress: _DoneOnboarding(),
            lessonProgressStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('vernacular-introduction-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('advance-braille-introduction')),
        findsNothing,
      );
      expect(find.textContaining('ಬ್ರೈಲ್ ಪರಿಚಯ'), findsOneWidget);
      expect(find.textContaining('ಎಡ ಕಾಲಂ'), findsNothing);
      final rect = tester.getRect(
        find.byKey(const ValueKey('vernacular-introduction-surface')),
      );
      final upA = await tester.startGesture(
        Offset(rect.left + 130, rect.top + 220),
        pointer: 81,
      );
      final upB = await tester.startGesture(
        Offset(rect.left + 190, rect.top + 220),
        pointer: 82,
      );
      await upA.moveBy(const Offset(0, -150));
      await upB.moveBy(const Offset(0, -150));
      await tester.pump();
      await upA.up();
      await upB.up();
      await tester.pump();
      expect(find.text('ಪರಿಚಯದ ಭಾಗ 1ರಲ್ಲಿ 5'), findsOneWidget);
      await swipeIntroduction(tester, left: true);
      expect(find.text('ಪರಿಚಯದ ಭಾಗ 2ರಲ್ಲಿ 5'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await swipeIntroduction(tester, left: true);
      }
      expect(find.textContaining('ಪರಿಶೀಲಿತ ಭಾರತಿ'), findsOneWidget);
      expect(find.text('ಪರಿಚಯದ ಭಾಗ 5ರಲ್ಲಿ 5'), findsOneWidget);
      await swipeIntroduction(tester, left: true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('vernacular-introduction-surface')),
        findsNothing,
      );
      expect(find.text('Learn ಅ'), findsOneWidget);
      expect(
        find.textContaining(LessonCatalog.kannada[1].title),
        findsOneWidget,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(store.state['chapter'], 1);
      expect(store.state['lesson_item'], 0);
    },
  );

  testWidgets(
    'Hindi and Kannada introductions do not overflow compact screens with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final language in [AppLanguage.hindi, AppLanguage.kannada]) {
        final account = LearnerAccount(
          learnerId: 'learner-${language.code}',
          learnerCode: language == AppLanguage.hindi ? '123456' : '123457',
          name: 'Learner',
          preferredLanguage: language.storageName,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: ResonantHome(
                learnerAccount: account,
                onboardingProgress: _DoneOnboarding(),
                lessonProgressStore: _MemoryResumeStore(),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('vernacular-introduction-surface')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byKey(const ValueKey('vernacular-introduction-surface')),
          const Offset(0, -180),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
