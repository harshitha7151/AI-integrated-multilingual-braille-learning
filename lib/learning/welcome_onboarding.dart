import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class WelcomeOnboarding extends StatefulWidget {
  final Future<void> Function() onComplete;
  final Future<void> Function(String) onSpeak;
  final Future<void> Function() onStop;
  final int initialStep;
  final Future<void> Function(int step)? onStepChanged;

  const WelcomeOnboarding({
    super.key,
    required this.onComplete,
    required this.onSpeak,
    required this.onStop,
    this.initialStep = 0,
    this.onStepChanged,
  });

  @override
  State<WelcomeOnboarding> createState() => _WelcomeOnboardingState();
}

class _WelcomeOnboardingState extends State<WelcomeOnboarding> {
  late int step;
  bool completing = false;
  bool changingStep = false;
  double _footerSwipeDistance = 0;
  int? _lessonSwipePointer;
  Offset? _lessonSwipeStart;

  static const _titles = [
    'Welcome to Resonant',
    'How lessons work',
    'The six-dot cell',
    'Dot numbers and positions',
    'Using the Braille keyboard',
    'Selecting and clearing dots',
    'Listening and vibration',
    'Talk with your tutor',
    'Navigate safely',
    'Practice and tests',
  ];

  static const _lessons = [
    "Welcome to Resonant. I'm your Braille learning companion. I'll guide you step by step. You can learn through spoken instructions, touch and vibration. Let's begin.",
    'Lessons teach one idea or letter at a time. You will hear an explanation, explore the Braille pattern, practise on the six-dot keyboard, and then take word tests using only letters already taught.',
    'A standard Braille cell has six possible raised-dot positions arranged in two columns and three rows. Different combinations represent letters and other symbols.',
    'Braille dots are numbered 1, 2, 3 down the left side of a standard cell and 4, 5, 6 down the right side. On the practice keyboard, screen-left shows dots 1, 2, 3 and screen-right shows dots 4, 5, 6.',
    'During letter lessons, the shared six-dot keyboard fills the landscape screen. Touch one dot or several dots together to enter a cell.',
    'The selected dots are announced aloud. A short vibration can confirm a touch when vibration is enabled. Clear a pattern before entering another one.',
    'Ask Resonant to repeat instructions or say stop speaking to interrupt audio. With TalkBack, use the custom actions announced for the current control. Swipe right or left as usual to move TalkBack focus.',
    'On the learning screen, double press the phone volume down button to open Resonant Tutor. Wait for the spoken ready message, then press volume up once to start speaking. The microphone stays off until you press volume up. Double press volume down again to cancel tutor mode. You can also open the tutor with its on-screen Talk to Resonant control. If speech recognition is unavailable, type your question and submit it with the send key.',
    'Volume button activation works only while Resonant is open in the foreground. A single volume press keeps its normal function. Android Back closes the tutor and returns to your lesson.',
    'Practice asks you to enter one letter at a time. Word tests ask for a whole word made only from letters you have learned. You can correct a cell before checking. An answer is accepted only when every cell matches the verified Braille engine.',
  ];

  @override
  void initState() {
    super.initState();
    step = widget.initialStep.clamp(0, 9);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSpeak(_lessons[step]);
    });
  }

  Future<void> repeat() => widget.onSpeak(_lessons[step]);

  Future<void> next() async {
    if (changingStep || completing) return;
    changingStep = true;
    try {
      if (step < _titles.length - 1) {
        setState(() => step++);
        await widget.onStepChanged?.call(step);
        changingStep = false;
        await repeat();
      } else {
        setState(() => completing = true);
        await widget.onComplete();
      }
    } finally {
      changingStep = false;
    }
  }

  Future<void> previous() async {
    if (step == 0 || changingStep || completing) return;
    changingStep = true;
    setState(() {
      step--;
    });
    try {
      await widget.onStepChanged?.call(step);
      changingStep = false;
      await repeat();
    } finally {
      changingStep = false;
    }
  }

  void _onLessonPointerDown(PointerDownEvent event) {
    _lessonSwipePointer = event.pointer;
    _lessonSwipeStart = event.position;
  }

  void _onLessonPointerUp(PointerUpEvent event) {
    if (event.pointer != _lessonSwipePointer || _lessonSwipeStart == null) {
      return;
    }
    final distance = event.position.dy - _lessonSwipeStart!.dy;
    _lessonSwipePointer = null;
    _lessonSwipeStart = null;
    if (distance < -48) {
      unawaited(next());
    } else if (distance > 48) {
      unawaited(previous());
    }
  }

  void _onLessonPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _lessonSwipePointer) {
      _lessonSwipePointer = null;
      _lessonSwipeStart = null;
    }
  }

  Widget _buildLessonNavigation(BuildContext context) => Semantics(
    container: true,
    label: step == _titles.length - 1
        ? 'Final Lesson 1 step. Swipe up to begin letter A. Swipe down to review the prior step.'
        : 'Lesson 1 step navigation. Swipe up to continue. Swipe down to review the prior step.',
    customSemanticsActions: {
      CustomSemanticsAction(
        label: step == _titles.length - 1
            ? 'Begin letter A'
            : 'Continue lesson',
      ): () {
        if (!completing) next();
      },
      if (step > 0)
        CustomSemanticsAction(label: 'Previous lesson step'): previous,
      CustomSemanticsAction(label: 'Repeat instructions'): repeat,
      CustomSemanticsAction(label: 'Stop speaking'): widget.onStop,
    },
    child: GestureDetector(
      key: const ValueKey('lesson-swipe-navigation'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _footerSwipeDistance = 0,
      onVerticalDragUpdate: (details) =>
          _footerSwipeDistance += details.delta.dy,
      onVerticalDragEnd: (details) {
        if (completing || changingStep) return;
        if (_footerSwipeDistance < -40 ||
            (details.primaryVelocity ?? 0) < -250) {
          next();
        } else if (_footerSwipeDistance > 40 ||
            (details.primaryVelocity ?? 0) > 250) {
          previous();
        }
      },
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: Center(
          child: Text(
            step == _titles.length - 1
                ? 'Swipe up to begin letter A · Swipe down to review'
                : 'Swipe up to continue · Swipe down to review',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Lesson 1: Learn Resonant'),
      automaticallyImplyLeading: false,
    ),
    body: Listener(
      key: const ValueKey('onboarding-swipe-surface'),
      onPointerDown: _onLessonPointerDown,
      onPointerUp: _onLessonPointerUp,
      onPointerCancel: _onLessonPointerCancel,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          key: const ValueKey('onboarding-title'),
                          _titles[step],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Lesson 1 · Step ${step + 1} of ${_titles.length}.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        container: true,
                        child: Text(
                          _lessons[step],
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      if (step == 3) ...[
                        const SizedBox(height: 18),
                        Semantics(
                          label:
                              'Six-dot Braille cell. Standard dot numbering: 1, 2, 3 down the left and 4, 5, 6 down the right. Practice keyboard: screen-left dots 1, 2, 3; screen-right dots 4, 5, 6.',
                          child: ExcludeSemantics(child: _DotDiagram()),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: _buildLessonNavigation(context),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DotDiagram extends StatelessWidget {
  const _DotDiagram();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final dots in const [
        [1, 2, 3],
        [4, 5, 6],
      ])
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              for (final dot in dots)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: CircleAvatar(radius: 20, child: Text('$dot')),
                ),
            ],
          ),
        ),
    ],
  );
}
