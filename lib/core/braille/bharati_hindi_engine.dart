/// Forward Hindi (Devanagari) Grade 1 mapping from NIEPVD's 2025 Unicode
/// mapped Standard Bharati Braille Codes chart. This is not a reverse translator.
class BharatiHindiEngine {
  static const Map<String, List<int>> _map = {
    'ँ': [3],
    'ं': [56],
    'ः': [6],
    'अ': [1],
    'आ': [345],
    'इ': [24],
    'ई': [35],
    'उ': [136],
    'ऊ': [1256],
    'ऋ': [5, 1235],
    'ऌ': [5, 123],
    'ए': [15],
    'ऐ': [34],
    'ऑ': [1346],
    'ओ': [135],
    'औ': [246],
    'क': [13],
    'ख': [46],
    'ग': [1245],
    'घ': [126],
    'ङ': [346],
    'च': [14],
    'छ': [16],
    'ज': [245],
    'झ': [356],
    'ञ': [25],
    'ट': [23456],
    'ठ': [2456],
    'ड': [1246],
    'ढ': [123456],
    'ण': [3456],
    'त': [2345],
    'थ': [1456],
    'द': [145],
    'ध': [2346],
    'न': [1345],
    'प': [1234],
    'फ': [124],
    'ब': [12],
    'भ': [45],
    'म': [134],
    'य': [13456],
    'र': [1235],
    'ल': [123],
    'ळ': [456],
    'व': [1236],
    'श': [146],
    'ष': [12346],
    'स': [234],
    'ह': [125],
    '़': [5],
    'ऽ': [2],
    'ा': [345],
    'ि': [24],
    'ी': [35],
    'ु': [136],
    'ू': [1256],
    'ृ': [5, 1235],
    'ॄ': [6, 1235],
    'ॅ': [1346],
    'े': [15],
    'ै': [34],
    'ॉ': [1346],
    'ो': [135],
    'ौ': [246],
    '्': [4],
    'ॐ': [5, 1256],
    'ड़': [12456],
    'ढ़': [5, 12456],
    'ॠ': [6, 1235],
    'ॡ': [6, 123],
    'ॢ': [5, 123],
    'ॣ': [6, 123],
    'क्ष': [12345],
    'ज्ञ': [156],
    'त्र': [4, 2345, 1235],
    'श्र': [4, 146, 1235],
    'ऩ': [5, 1345],
    'ऱ': [5, 1235],
  };
  static const List<int> _digits = [
    245,
    1,
    12,
    14,
    145,
    15,
    124,
    1245,
    125,
    24,
  ];
  static const Map<String, int> _punct = {
    ',': 1,
    ':': 3,
    '!': 6,
    '-': 36,
    '.': 4,
    '?': 8,
    ';': 2,
    ' ': 0,
  };

  static List<int> encode(String text) => [
    for (final unit in encodeUnits(text)) ...unit.value,
  ];

  /// Returns the exact greedy text units used by [encode], with each unit's
  /// complete ordered cell sequence. This supports letter-level feedback for
  /// conjuncts and other multi-cell mappings without changing the mapping.
  static List<MapEntry<String, List<int>>> encodeUnits(String text) {
    final chars = text.runes.map(String.fromCharCode).toList();
    final out = <MapEntry<String, List<int>>>[];
    for (var i = 0; i < chars.length;) {
      final pair = i + 1 < chars.length ? chars[i] + chars[i + 1] : '';
      final triple = i + 2 < chars.length ? pair + chars[i + 2] : '';
      final special = _map.containsKey(triple)
          ? triple
          : (_map.containsKey(pair) ? pair : null);
      if (special != null) {
        out.add(MapEntry(special, _map[special]!));
        i += special.runes.length;
        continue;
      }
      final c = chars[i];
      if (_map.containsKey(c)) {
        out.add(MapEntry(c, _map[c]!));
      } else if (c.codeUnitAt(0) >= 0x0966 && c.codeUnitAt(0) <= 0x096F) {
        out.add(MapEntry(c, [60, _digits[c.codeUnitAt(0) - 0x0966]]));
      } else if (_punct.containsKey(c)) {
        out.add(MapEntry(c, [_punct[c]!]));
      } else {
        throw UnsupportedError('Unsupported Hindi character: $c');
      }
      i++;
    }
    return out;
  }

  static String decode(Iterable<int> _) => throw UnsupportedError(
    'Hindi reverse translation is not implemented or validated.',
  );
}
