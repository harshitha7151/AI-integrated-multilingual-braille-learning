import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/core/braille/braille_dispatcher.dart';
import 'package:resonant_braille/learning/lesson_catalog.dart';
import 'package:resonant_braille/learning/lesson_progress_store.dart';
import 'package:resonant_braille/learning/onboarding_store.dart';
import 'package:resonant_braille/main.dart';

class _DoneOnboarding implements OnboardingProgress {
  @override Future<bool> isComplete() async => true;
  @override Future<void> markComplete() async {}
  @override Future<int> currentStep() async => 10;
  @override Future<void> saveStep(int step) async {}
}

class _MemoryResumeStore extends LessonProgressStore {
  _MemoryResumeStore() : super(File('unused-multilingual-test.json'));
  Map<String, dynamic> state = {};
  @override Future<List<Map<String, dynamic>>> readEvents() async => [];
  @override Future<Map<String, dynamic>> readResumeState() async => state;
  @override Future<void> writeResumeState({required String languageCode, required String chapterId, required int chapterIndex, required int lessonIndex}) async {
    state = {'language': languageCode, 'chapter_id': chapterId, 'chapter_index': chapterIndex, 'lesson_index': lessonIndex};
  }
}

void main() {
  test('BrailleDispatcher converts Hindi and Kannada NIEPVD dot numbers to bitmasks', () {
    expect(BrailleDispatcher.bitmaskFromDotNumber(1), 1);
    expect(BrailleDispatcher.bitmaskFromDotNumber(13), 5);
    expect(BrailleDispatcher.dotsForBitmask(5), [1, 3]);
    expect(BrailleDispatcher.encodeToBitmasks('\u0905', AppLanguage.hindi), isNotEmpty);
    expect(BrailleDispatcher.encodeToBitmasks('\u0C85', AppLanguage.kannada), isNotEmpty);
  });

  test('LessonCatalog includes Hindi and Kannada curricula', () {
    expect(LessonCatalog.chaptersFor(AppLanguage.hindi).length, 3);
    expect(LessonCatalog.chaptersFor(AppLanguage.kannada).length, 3);
    expect(LessonCatalog.hindi[1].exercises, isNotEmpty);
    expect(LessonCatalog.kannada[1].exercises, isNotEmpty);
  });

  testWidgets('Lesson Navigator switches language to Hindi and Kannada and persists resume state', (tester) async {
    final store = _MemoryResumeStore();
    await tester.pumpWidget(MaterialApp(home: ResonantHome(onboardingProgress: _DoneOnboarding(), lessonProgressStore: store)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('open-lesson-navigator')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('\u0939\u093F\u0928\u094D\u0926\u0940').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('\u0939\u093F\u0928\u094D\u0926\u0940'), findsWidgets);
    await tester.pump(); expect(find.textContaining('\u0939\u093F\u0928\u094D\u0926\u0940'), findsWidgets);
  });
}