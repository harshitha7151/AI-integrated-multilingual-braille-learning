import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/accessibility/accessible_action_surface.dart';
import 'package:resonant_braille/learning/role_selection_page.dart';
import 'package:resonant_braille/learning/role_store.dart';
import 'package:resonant_braille/teacher/teacher_dashboard_placeholder.dart';

// ---------------------------------------------------------------------------
// In-memory [RoleStorage] implementation — no disk I/O.
// ---------------------------------------------------------------------------
class _MemoryRoleStore implements RoleStorage {
  AppRole? _role;

  @override
  Future<AppRole?> savedRole() async => _role;

  @override
  Future<void> saveRole(AppRole role) async => _role = role;

  @override
  Future<void> clearRole() async => _role = null;
}

// ---------------------------------------------------------------------------
// Helper: build [RoleGate] in a MaterialApp with a fake store.
// ---------------------------------------------------------------------------
Widget _buildGate({
  required _MemoryRoleStore store,
  List<String> voiceEvents = const [],
}) {
  final controller = StreamController<String>.broadcast();
  for (final e in voiceEvents) {
    controller.add(e);
  }

  return MaterialApp(
    home: RoleGate(
      roleStorage: store,
      onSpeak: (_) async {},
      onStop: () async {},
      learnerHome: const Scaffold(body: Center(child: Text('LearnerHome'))),
      teacherHome: (onSwitch) =>
          TeacherDashboardPlaceholder(onSwitchRole: onSwitch),
      voiceInputStream: controller.stream,
    ),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // Unit-level routing logic (no widgets needed)
  // ---------------------------------------------------------------------------
  group('RoleGate routing logic', () {
    test('no saved role → routes to selection (widget integration below)', () {
      // Verified via widget test below; placeholder unit marker.
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests
  // ---------------------------------------------------------------------------
  group('RoleGate widget routing', () {
    testWidgets('shows RoleSelectionPage when no role is saved', (
      tester,
    ) async {
      final store = _MemoryRoleStore();
      var openedLabConnect = false;
      await tester.pumpWidget(
        MaterialApp(
          home: RoleGate(
            roleStorage: store,
            onSpeak: (_) async {},
            onStop: () async {},
            learnerHome: const Scaffold(body: Text('LearnerHome')),
            teacherHome: (onSwitch) =>
                TeacherDashboardPlaceholder(onSwitchRole: onSwitch),
            onConnectToAimlLab: () => openedLabConnect = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('learner-swipe-zone')), findsOneWidget);
      expect(find.byKey(const ValueKey('teacher-button')), findsOneWidget);
      expect(find.text('Connect to AIML Lab'), findsOneWidget);
      await tester.tap(find.text('Connect to AIML Lab'));
      expect(openedLabConnect, isTrue);
    });

    testWidgets('shows learner home immediately when role=learner is saved', (
      tester,
    ) async {
      final store = _MemoryRoleStore().._role = AppRole.learner;
      await tester.pumpWidget(_buildGate(store: store));
      await tester.pumpAndSettle();

      expect(find.text('LearnerHome'), findsOneWidget);
      expect(find.byKey(const ValueKey('teacher-button')), findsNothing);
    });

    testWidgets(
      'shows teacher dashboard immediately when role=teacher is saved',
      (tester) async {
        final store = _MemoryRoleStore().._role = AppRole.teacher;
        await tester.pumpWidget(_buildGate(store: store));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('teacher-dashboard-title')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('teacher-button')), findsNothing);
      },
    );

    testWidgets(
      'tapping Teacher button saves role and shows teacher dashboard',
      (tester) async {
        final store = _MemoryRoleStore();
        await tester.pumpWidget(_buildGate(store: store));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('teacher-button')));
        await tester.pumpAndSettle();

        expect(store._role, AppRole.teacher);
        expect(
          find.byKey(const ValueKey('teacher-dashboard-title')),
          findsOneWidget,
        );
      },
    );

    testWidgets('swipe up on learner zone saves role and shows learner home', (
      tester,
    ) async {
      final store = _MemoryRoleStore();
      await tester.pumpWidget(_buildGate(store: store));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('learner-swipe-zone')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();

      expect(store._role, AppRole.learner);
      expect(find.text('LearnerHome'), findsOneWidget);
    });

    testWidgets(
      'switch role button on teacher dashboard clears role and shows selection',
      (tester) async {
        final store = _MemoryRoleStore().._role = AppRole.teacher;
        await tester.pumpWidget(_buildGate(store: store));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('switch-role-button')));
        await tester.pumpAndSettle();

        expect(store._role, isNull);
        expect(
          find.byKey(const ValueKey('learner-swipe-zone')),
          findsOneWidget,
        );
      },
    );

    testWidgets('learner can switch role and choose Teacher', (tester) async {
      final store = _MemoryRoleStore().._role = AppRole.learner;
      await tester.pumpWidget(
        MaterialApp(
          home: RoleGate(
            roleStorage: store,
            onSpeak: (_) async {},
            onStop: () async {},
            learnerHome: const Scaffold(body: Text('LearnerHome')),
            learnerHomeBuilder: (onSwitchRole) => Scaffold(
              body: AccessibleActionSurface(
                key: const ValueKey('learner-switch-role'),
                semanticsLabel: 'Log out / switch role',
                actionLabel: 'Log out / switch role',
                onActivate: onSwitchRole,
                child: const Text('Switch role'),
              ),
            ),
            teacherHome: (onSwitch) =>
                TeacherDashboardPlaceholder(onSwitchRole: onSwitch),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('learner-switch-role')));
      await tester.pumpAndSettle();
      expect(store._role, isNull);
      expect(find.byKey(const ValueKey('teacher-button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('teacher-button')));
      await tester.pumpAndSettle();
      expect(store._role, AppRole.teacher);
      expect(
        find.byKey(const ValueKey('teacher-dashboard-title')),
        findsOneWidget,
      );
    });
  });

  group('RoleSelectionPage voice input', () {
    testWidgets('voice "learner" resolves to learner role', (tester) async {
      AppRole? chosen;
      final controller = StreamController<String>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: RoleSelectionPage(
            onSpeak: (_) async {},
            onStop: () async {},
            onRoleSelected: (r) async => chosen = r,
            voiceInputStream: controller.stream,
          ),
        ),
      );
      await tester.pump();

      controller.add('learner');
      await tester.pump();

      expect(chosen, AppRole.learner);
      await controller.close();
    });

    testWidgets('voice "teacher" resolves to teacher role', (tester) async {
      AppRole? chosen;
      final controller = StreamController<String>.broadcast();

      await tester.pumpWidget(
        MaterialApp(
          home: RoleSelectionPage(
            onSpeak: (_) async {},
            onStop: () async {},
            onRoleSelected: (r) async => chosen = r,
            voiceInputStream: controller.stream,
          ),
        ),
      );
      await tester.pump();

      controller.add('teacher');
      await tester.pump();

      expect(chosen, AppRole.teacher);
      await controller.close();
    });
  });
}
