/// Resolves a spoken choice only when it identifies one visible option.
///
/// Exact option labels, letters, and ordinals are preferred. Meaning-based
/// matching is conservative and returns null when two choices are equally
/// plausible.
class TutorOptionResolver {
  const TutorOptionResolver._();

  static int? resolveIndex(List<String> options, String? utterance) {
    final normalized = utterance?.toLowerCase().trim().replaceAll(
      RegExp(r'[.!?]+$'),
      '',
    );
    if (normalized == null || normalized.isEmpty || options.isEmpty) {
      return null;
    }

    const aliases = <String, int>{
      'a': 0,
      'option a': 0,
      'option 1': 0,
      'choice a': 0,
      'choice 1': 0,
      'first': 0,
      'the first': 0,
      'first one': 0,
      'first option': 0,
      'first choice': 0,
      '1': 0,
      'one': 0,
      'b': 1,
      'option b': 1,
      'option 2': 1,
      'choice b': 1,
      'choice 2': 1,
      'second': 1,
      'the second': 1,
      'the second one': 1,
      'second one': 1,
      'second option': 1,
      'second choice': 1,
      '2': 1,
      'two': 1,
      'c': 2,
      'option c': 2,
      'option 3': 2,
      'choice c': 2,
      'choice 3': 2,
      'third': 2,
      'the third': 2,
      'the third one': 2,
      'third one': 2,
      'third option': 2,
      'third choice': 2,
      '3': 2,
      'three': 2,
      'd': 3,
      'option d': 3,
      'option 4': 3,
      'choice d': 3,
      'choice 4': 3,
      'fourth': 3,
      'the fourth': 3,
      'the fourth one': 3,
      'fourth one': 3,
      'fourth option': 3,
      'fourth choice': 3,
      '4': 3,
      'four': 3,
      'e': 4,
      'option e': 4,
      'option 5': 4,
      'choice e': 4,
      'choice 5': 4,
      'fifth': 4,
      'the fifth': 4,
      'the fifth one': 4,
      'fifth one': 4,
      'fifth option': 4,
      'fifth choice': 4,
      '5': 4,
      'five': 4,
    };
    final aliasIndex = aliases[normalized];
    if (aliasIndex != null) {
      return aliasIndex < options.length ? aliasIndex : null;
    }

    for (var index = 0; index < options.length; index++) {
      if (options[index].toLowerCase().trim() == normalized) return index;
    }

    final request = normalized
        .replaceFirst(RegExp(r'^(?:select|choose)\s+'), '')
        .replaceFirst(
          RegExp(r'^(?:the\s+)?(?:option|choice)\s+(?:about|that says)\s+'),
          '',
        )
        .trim();
    final requestTokens = _tokens(request);
    if (requestTokens.isEmpty) return null;

    final ranked = <({int index, int overlap})>[];
    for (var index = 0; index < options.length; index++) {
      final overlap = requestTokens
          .intersection(_tokens(options[index]))
          .length;
      if (overlap > 0) ranked.add((index: index, overlap: overlap));
    }
    ranked.sort((a, b) => b.overlap.compareTo(a.overlap));
    if (ranked.isEmpty ||
        ranked.first.overlap < requestTokens.length * 0.6 ||
        (ranked.length > 1 && ranked[0].overlap == ranked[1].overlap)) {
      return null;
    }
    return ranked.first.index;
  }

  static Set<String> _tokens(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.length > 2 || RegExp(r'^[1-6]$').hasMatch(token))
      .map((token) => token == 'dots' ? 'dot' : token)
      .toSet();
}
