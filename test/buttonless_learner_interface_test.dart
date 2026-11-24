import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/accessibility/accessible_action_surface.dart';

void main() {
  test('learner-facing sources do not reintroduce conventional buttons', () {
    const learnerSources = <String>[
      'lib/main.dart',
      'lib/learning/adaptive_recommendation_status.dart',
      'lib/learning/learner_registration_page.dart',
      'lib/learning/role_selection_page.dart',
      'lib/learning/welcome_onboarding.dart',
      'lib/tutor/voice_tutor_panel.dart',
    ];
    final forbidden = <RegExp>[
      RegExp(r'\bElevatedButton\s*(?:\.|\()'),
      RegExp(r'\bFilledButton\s*(?:\.|\()'),
      RegExp(r'\bOutlinedButton\s*(?:\.|\()'),
      RegExp(r'\bTextButton\s*(?:\.|\()'),
      RegExp(r'\bIconButton\s*\('),
      RegExp(r'\bFloatingActionButton\s*\('),
      RegExp(r'\bCupertinoButton\s*(?:\.|\()'),
      RegExp(r'\bMaterialButton\s*(?:\.|\()'),
      RegExp(r'\bRawMaterialButton\s*\('),
      RegExp(r'\bbutton\s*:\s*true\b'),
    ];

    for (final path in learnerSources) {
      final source = File(path).readAsStringSync();
      for (final pattern in forbidden) {
        expect(
          pattern.hasMatch(source),
          isFalse,
          reason: '$path contains forbidden learner control ${pattern.pattern}',
        );
      }
    }
  });

  testWidgets('action surfaces are focusable without button semantics', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    var activated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccessibleActionSurface(
            key: const ValueKey('buttonless-action'),
            semanticsLabel: 'Continue lesson',
            semanticsHint: 'Double tap to continue.',
            actionLabel: 'Continue lesson',
            onActivate: () => activated = true,
            child: const Text('Continue lesson'),
          ),
        ),
      ),
    );

    final surface = find.byKey(const ValueKey('buttonless-action'));
    final semanticSurface = find.bySemanticsLabel('Continue lesson');
    final semantics = tester.getSemantics(semanticSurface).getSemanticsData();
    expect(semantics.hasFlag(SemanticsFlag.isFocusable), isTrue);
    expect(semantics.hasFlag(SemanticsFlag.isButton), isFalse);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(surface);
    expect(activated, isTrue);
    semanticsHandle.dispose();
  });
}
