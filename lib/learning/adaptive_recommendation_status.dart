import 'package:flutter/material.dart';

import '../accessibility/accessible_action_surface.dart';
import 'adaptive_decision_controller.dart';

/// Plain-language, screen-reader-first status for the active adaptive action.
class AdaptiveRecommendationStatus extends StatelessWidget {
  final AdaptiveDecision decision;

  const AdaptiveRecommendationStatus({super.key, required this.decision});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '${decision.learnerActivityMessage} ${decision.learnerModelStatusMessage}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(
              decision.learnerActivityMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9FE0B5),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              decision.learnerModelStatusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB8D1FF), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared accessible prompt and choices for catalog or adaptive questions.
class AccessibleLessonQuestion extends StatelessWidget {
  final String prompt;
  final List<String> options;
  final String? selectedOption;
  final bool enabled;
  final ValueChanged<String> onSelected;

  const AccessibleLessonQuestion({
    super.key,
    required this.prompt,
    required this.options,
    required this.selectedOption,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          container: true,
          label: prompt,
          child: ExcludeSemantics(
            child: Text(
              prompt,
              key: const ValueKey('lesson-question-prompt'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 19),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              for (var index = 0; index < options.length; index++)
                AccessibleActionSurface(
                  key: ValueKey('lesson-answer-${options[index]}'),
                  semanticsLabel:
                      'Answer ${index + 1}: ${options[index]}. '
                      '${selectedOption == options[index] ? 'Selected.' : 'Not selected.'}',
                  semanticsHint: enabled
                      ? 'Double tap to select this answer.'
                      : 'Answer selection is unavailable.',
                  actionLabel: 'Select answer ${options[index]}',
                  onActivate: enabled ? () => onSelected(options[index]) : null,
                  selected: selectedOption == options[index],
                  inMutuallyExclusiveGroup: true,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${index + 1}.',
                          style: const TextStyle(color: Color(0xFFB8D1FF)),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          options[index],
                          style: TextStyle(
                            color: selectedOption == options[index]
                                ? Colors.white
                                : const Color(0xFFB8D1FF),
                            fontSize: 18,
                            fontWeight: selectedOption == options[index]
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (selectedOption == options[index])
                        const Icon(Icons.check, color: Color(0xFF9FE0B5)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
