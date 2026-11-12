import 'bharati_hindi_engine.dart';
import 'bharati_kannada_engine.dart';
import 'english_grade1_engine.dart';

enum AppLanguage {
  english('en', 'en-IN', 'English', 'English'),
  hindi('hi', 'hi-IN', 'Hindi', 'हिन्दी'),
  kannada('kn', 'kn-IN', 'Kannada', 'ಕನ್ನಡ');

  final String code;
  final String ttsLocale;
  final String storageName;
  final String nativeLabel;

  const AppLanguage(
    this.code,
    this.ttsLocale,
    this.storageName,
    this.nativeLabel,
  );

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (lang) => lang.code == code || lang.storageName == code,
    orElse: () => AppLanguage.english,
  );
}

class BrailleDispatcher {
  /// Converts NIEPVD dot-number integer (e.g., 134 -> dots 1, 3, 4) to 6-bit cell bitmask.
  static int bitmaskFromDotNumber(int dotNumber) {
    if (dotNumber <= 0) return 0;
    var mask = 0;
    for (final ch in dotNumber.toString().split('')) {
      final dot = int.tryParse(ch);
      if (dot != null && dot >= 1 && dot <= 6) {
        mask |= 1 << (dot - 1);
      }
    }
    return mask;
  }

  /// Encodes [text] in the given [language] into 6-bit cell bitmasks.
  static List<int> encodeToBitmasks(String text, AppLanguage language) {
    switch (language) {
      case AppLanguage.english:
        return EnglishGrade1Engine.encode(text);
      case AppLanguage.hindi:
        return BharatiHindiEngine.encode(
          text,
        ).map(bitmaskFromDotNumber).toList();
      case AppLanguage.kannada:
        return BharatiKannadaEngine.encode(
          text,
        ).map(bitmaskFromDotNumber).toList();
    }
  }

  /// Returns sorted active dot numbers [1..6] from a 6-bit cell bitmask.
  static List<int> dotsForBitmask(int cell) => [
    for (var i = 0; i < 6; i++)
      if ((cell & (1 << i)) != 0) i + 1,
  ];
}