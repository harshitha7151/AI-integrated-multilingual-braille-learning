/// Forward Kannada Grade 1 mapping transcribed from NIEPVD's 2025
/// Unicode-mapped Standard Bharati Braille chart. Reverse translation is absent.
class BharatiKannadaEngine {
  static const Map<String, List<int>> _map = {
    'ಂ': [56],
    'ಃ': [6],
    'ಅ': [1],
    'ಆ': [345],
    'ಇ': [24],
    'ಈ': [35],
    'ಉ': [136],
    'ಊ': [1256],
    'ಋ': [5, 1235],
    'ಎ': [26],
    'ಏ': [15],
    'ಐ': [34],
    'ಒ': [1346],
    'ಓ': [135],
    'ಔ': [246],
    'ಕ': [13],
    'ಖ': [46],
    'ಗ': [1245],
    'ಘ': [126],
    'ಙ': [346],
    'ಚ': [14],
    'ಛ': [16],
    'ಜ': [245],
    'ಝ': [356],
    'ಞ': [25],
    'ಟ': [23456],
    'ಠ': [2456],
    'ಡ': [1246],
    'ಢ': [123456],
    'ಣ': [3456],
    'ತ': [2345],
    'ಥ': [1456],
    'ದ': [145],
    'ಧ': [2346],
    'ನ': [1345],
    'ಪ': [1234],
    'ಫ': [124],
    'ಬ': [12],
    'ಭ': [45],
    'ಮ': [134],
    'ಯ': [13456],
    'ರ': [1235],
    'ಱ': [12456],
    'ಲ': [123],
    'ಳ': [456],
    'ವ': [1236],
    'ಶ': [146],
    'ಷ': [12346],
    'ಸ': [234],
    'ಹ': [125],
    '಼': [5],
    'ಾ': [345],
    'ಿ': [24],
    'ೀ': [35],
    'ು': [136],
    'ೂ': [1256],
    'ೃ': [5, 1235],
    'ೄ': [6, 1235],
    'ೆ': [26],
    'ೇ': [15],
    'ೈ': [34],
    'ೊ': [1346],
    'ೋ': [135],
    'ೌ': [246],
    '್': [4],
    'ಕ್ಷ': [12345],
    'ಜ್ಞ': [156],
    'ೞ': [5, 456],
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
      } else if (c.codeUnitAt(0) >= 0x0CE6 && c.codeUnitAt(0) <= 0x0CEF) {
        out.add(MapEntry(c, [60, _digits[c.codeUnitAt(0) - 0x0CE6]]));
      } else if (_punct.containsKey(c)) {
        out.add(MapEntry(c, [_punct[c]!]));
      } else {
        throw UnsupportedError('Unsupported Kannada character: $c');
      }
      i++;
    }
    return out;
  }

  static String decode(Iterable<int> _) => throw UnsupportedError(
    'Kannada reverse translation is not implemented or validated.',
  );
}
