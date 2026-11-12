import '../core/braille/braille_dispatcher.dart';
import '../core/braille/english_grade1_engine.dart';

class LessonExercise {
  final String id;
  final String skillId;
  final String prompt;
  final List<String> options;
  final String answer;
  final String hint;
  final String explanation;
  final String exerciseType;

  const LessonExercise({
    required this.id,
    required this.skillId,
    required this.prompt,
    required this.options,
    required this.answer,
    required this.hint,
    required this.explanation,
    this.exerciseType = 'letter_recognition',
  });

  bool isCorrect(String choice) => choice == answer;
}

class LessonChapter {
  final String title;
  final List<LessonExercise> exercises;

  const LessonChapter({required this.title, required this.exercises});
}

class WordLearningLesson {
  final String id;
  final String title;
  final String description;
  final List<String> words;
  const WordLearningLesson({
    required this.id,
    required this.title,
    required this.description,
    required this.words,
  });
}

class LessonCatalog {
  static const List<String> cumulativeWords = [
    'AB',
    'BAD',
    'FEED',
    'AMAZE',
    'DECADE',
  ];
  static const List<WordLearningLesson> wordLessons = [
    WordLearningLesson(
      id: 'word-build',
      title: 'Lesson 1: Build your first words',
      description:
          'Review the letters you learned. A word places one Braille cell after another. Hear each word and explore its cells.',
      words: ['CAT', 'BAT', 'MAT'],
    ),
    WordLearningLesson(
      id: 'word-read',
      title: 'Lesson 2: Read familiar words',
      description:
          'Hear each familiar word aloud, follow its letters and cells, then identify it.',
      words: ['SUN', 'DOG', 'HAT', 'PEN'],
    ),
    WordLearningLesson(
      id: 'word-write',
      title: 'Lesson 3: Write the word',
      description: 'Write each spoken word one Braille cell at a time.',
      words: ['CAT', 'BAT', 'MAT'],
    ),
    WordLearningLesson(
      id: 'word-identify',
      title: 'Lesson 4: Read and identify',
      description:
          'Explore Braille cells and identify the word they spell without seeing its printed name.',
      words: ['SUN', 'DOG', 'HAT', 'PEN'],
    ),
    WordLearningLesson(
      id: 'word-mastery',
      title: 'Lesson 5: Word mastery test',
      description: 'Show what you know across familiar words.',
      words: ['CAT', 'SUN', 'BAT', 'DOG', 'HAT'],
    ),
  ];

  /// Ordered, uncontracted cumulative spelling stages required by the course.
  /// Each bank contains only words composed of letters taught by that stage.
  static const List<CurriculumStage> curriculum = [
    CurriculumStage(
      id: 'a-e',
      title: 'Letters A through E',
      first: 0,
      last: 4,
      allowedLetters: 'abcde',
      words: ['BAD', 'CAB', 'BED', 'ACE', 'DECADE'],
    ),
    CurriculumStage(
      id: 'a-j',
      title: 'Letters F through J',
      first: 5,
      last: 9,
      allowedLetters: 'abcdefghij',
      words: ['FEED', 'DECAF', 'JAB', 'FACE', 'CAB'],
    ),
    CurriculumStage(
      id: 'a-o',
      title: 'Letters K through O',
      first: 10,
      last: 14,
      allowedLetters: 'abcdefghijklmno',
      words: ['JAM', 'MOON', 'FAD', 'MAKE', 'CODE'],
    ),
    CurriculumStage(
      id: 'a-t',
      title: 'Letters P through T',
      first: 15,
      last: 19,
      allowedLetters: 'abcdefghijklmnopqrst',
      words: ['TASTE', 'MARKET', 'STEAM', 'THREAD', 'MIST'],
    ),
    CurriculumStage(
      id: 'a-z',
      title: 'Letters U through Z',
      first: 20,
      last: 25,
      allowedLetters: 'abcdefghijklmnopqrstuvwxyz',
      words: ['AMAZE', 'BELL', 'FIZZ', 'WAVE', 'QUIZ'],
    ),
  ];

  static const List<String> alphabet = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  static const List<String> hindiCharacters = [
    'अ', 'आ', 'इ', 'ई', 'उ', 'ऊ', 'ए', 'ऐ', 'ओ', 'औ',
    'क', 'ख', 'ग', 'घ', 'च', 'छ', 'ज', 'झ', 'ट', 'ठ',
    'ड', 'ढ', 'ण', 'त', 'थ', 'द', 'ध', 'न', 'प', 'फ',
    'ब', 'भ', 'म', 'य', 'र', 'ल', 'व', 'श', 'ष', 'स', 'ह',
  ];

  static const List<String> kannadaCharacters = [
    'ಅ', 'ಆ', 'ಇ', 'ಈ', 'ಉ', 'ಊ', 'ಎ', 'ಏ', 'ಐ', 'ಒ', 'ಓ', 'ಔ',
    'ಕ', 'ಖ', 'ಗ', 'ಘ', 'ಚ', 'ಛ', 'ಜ', 'ಝ', 'ಟ', 'ಠ',
    'ಡ', 'ಢ', 'ಣ', 'ತ', 'ಥ', 'ದ', 'ಧ', 'ನ', 'ಪ', 'ಫ',
    'ಬ', 'ಭ', 'ಮ', 'ಯ', 'ರ', 'ಲ', 'ವ', 'ಶ', 'ಷ', 'ಸ', 'ಹ', 'ಳ',
  ];

  static List<LessonChapter> chaptersFor(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.english:
        return english;
      case AppLanguage.hindi:
        return hindi;
      case AppLanguage.kannada:
        return kannada;
    }
  }

  static bool wordUsesOnly(String word, String allowedLetters) =>
      word.isNotEmpty &&
      word.toLowerCase().split('').every(allowedLetters.contains);

  static CurriculumStage stageForIndex(int index) => curriculum.firstWhere(
    (stage) => index >= stage.first && index <= stage.last,
  );

  static final List<LessonChapter> english = [
    LessonChapter(
      title: 'Chapter 1: Braille Basics',
      exercises: [
        LessonExercise(
          id: 'dot-top-left',
          skillId: 'dot-position-1',
          exerciseType: 'dot_recognition',
          prompt: 'Which dot is at the top of the left column?',
          options: ['Dot 1', 'Dot 2', 'Dot 4', 'Dot 5'],
          answer: 'Dot 1',
          hint: 'The standard numbering starts at the top of the left column.',
          explanation: 'Dot 1 is at the top of the left column.',
        ),
        LessonExercise(
          id: 'dot-top-right',
          skillId: 'dot-position-4',
          exerciseType: 'dot_recognition',
          prompt: 'Which dot is at the top of the right column?',
          options: ['Dot 1', 'Dot 3', 'Dot 4', 'Dot 6'],
          answer: 'Dot 4',
          hint: 'The right column uses dots 4, 5, and 6 from top to bottom.',
          explanation: 'Dot 4 is at the top of the right column.',
        ),
        LessonExercise(
          id: 'cell-count',
          skillId: 'braille-cell',
          exerciseType: 'dot_recognition',
          prompt: 'How many dots are in one standard Braille cell?',
          options: ['Four', 'Five', 'Six', 'Eight'],
          answer: 'Six',
          hint: 'A standard cell has two columns with three positions each.',
          explanation: 'A standard Braille cell has six dot positions.',
        ),
      ],
    ),
    LessonChapter(
      title: 'Chapter 2: English Letters',
      exercises: [for (final letter in alphabet) _letterExercise(letter)],
    ),
    LessonChapter(
      title: 'Chapter 3: English Words',
      exercises: [
        for (
          var lessonIndex = 0;
          lessonIndex < wordLessons.length;
          lessonIndex++
        )
          for (final word in wordLessons[lessonIndex].words)
            LessonExercise(
              id: 'word-chapter-lesson-${lessonIndex + 1}-${word.toLowerCase()}',
              skillId: 'word-chapter-${lessonIndex + 1}-${word.toLowerCase()}',
              exerciseType: lessonIndex == 2 || lessonIndex == 4
                  ? 'word_transcription'
                  : 'listening',
              prompt: wordLessons[lessonIndex].description,
              options: [
                word,
                ...wordLessons[lessonIndex].words
                    .where((other) => other != word)
                    .take(3),
              ],
              answer: word,
              hint:
                  'Listen to the word again and explore each Braille cell in order.',
              explanation:
                  '$word is spelled as separate uncontracted English Braille letter cells.',
            ),
      ],
    ),
  ];

  static final List<LessonChapter> hindi = [
    LessonChapter(
      title: 'अध्याय 1: ब्रेल परिचय (Braille Basics)',
      exercises: [
        LessonExercise(
          id: 'hi-dot-top-left',
          skillId: 'hi-dot-position-1',
          exerciseType: 'dot_recognition',
          prompt: 'बाएं कॉलम में सबसे ऊपर कौन सा बिंदु होता है?',
          options: ['बिंदु 1', 'बिंदु 2', 'बिंदु 4', 'बिंदु 5'],
          answer: 'बिंदु 1',
          hint: 'मानक ब्रेल सेल में बाएं कॉलम में ऊपर से नीचे बिंदु 1, 2, 3 होते हैं।',
          explanation: 'बिंदु 1 बाएं कॉलम में सबसे ऊपर होता है।',
        ),
        LessonExercise(
          id: 'hi-dot-top-right',
          skillId: 'hi-dot-position-4',
          exerciseType: 'dot_recognition',
          prompt: 'दाएं कॉलम में सबसे ऊपर कौन सा बिंदु होता है?',
          options: ['बिंदु 1', 'बिंदु 3', 'बिंदु 4', 'बिंदु 6'],
          answer: 'बिंदु 4',
          hint: 'दाएं कॉलम में ऊपर से नीचे बिंदु 4, 5, 6 होते हैं।',
          explanation: 'बिंदु 4 दाएं कॉलम में सबसे ऊपर होता है।',
        ),
      ],
    ),
    LessonChapter(
      title: 'अध्याय 2: हिंदी वर्णमाला (भारती ब्रेल)',
      exercises: [
        for (final ch in hindiCharacters)
          _vernacularExercise(ch, AppLanguage.hindi),
      ],
    ),
    LessonChapter(
      title: 'अध्याय 3: सरल हिंदी शब्द',
      exercises: [
        for (final word in ['अब', 'कमल', 'जल', 'घर', 'मन'])
          LessonExercise(
            id: 'hi-word-$word',
            skillId: 'hi-word-$word',
            exerciseType: 'word_transcription',
            prompt: 'शब्द "$word" के भारती ब्रेल बिंदु लिखें।',
            options: [word, 'अब', 'कमल', 'जल'],
            answer: word,
            hint: 'प्रत्येक अक्षर के भारती ब्रेल बिंदु क्रम से दर्ज करें।',
            explanation: 'शब्द $word भारती ब्रेल में अक्षर दर अक्षर लिखा जाता है।',
          ),
      ],
    ),
  ];

  static final List<LessonChapter> kannada = [
    LessonChapter(
      title: 'ಅಧ್ಯಾಯ 1: ಬ್ರೈಲ್ ಪರಿಚಯ (Braille Basics)',
      exercises: [
        LessonExercise(
          id: 'kn-dot-top-left',
          skillId: 'kn-dot-position-1',
          exerciseType: 'dot_recognition',
          prompt: 'ಎಡ ಕಾಲಂನ ಮೇಲ್ಭಾಗದಲ್ಲಿ ಯಾವ ಚುಕ್ಕೆ ಇರುತ್ತದೆ?',
          options: ['ಚುಕ್ಕೆ 1', 'ಚುಕ್ಕೆ 2', 'ಚುಕ್ಕೆ 4', 'ಚುಕ್ಕೆ 5'],
          answer: 'ಚುಕ್ಕೆ 1',
          hint: 'ಎಡ ಕಾಲಂನಲ್ಲಿ ಮೇಲಿನಿಂದ ಕೆಳಗೆ 1, 2, 3 ಚುಕ್ಕೆಗಳಿರುತ್ತವೆ.',
          explanation: 'ಚುಕ್ಕೆ 1 ಎಡ ಕಾಲಂನ ಮೇಲ್ಭಾಗದಲ್ಲಿದೆ.',
        ),
        LessonExercise(
          id: 'kn-dot-top-right',
          skillId: 'kn-dot-position-4',
          exerciseType: 'dot_recognition',
          prompt: 'ಬಲ ಕಾಲಂನ ಮೇಲ್ಭಾಗದಲ್ಲಿ ಯಾವ ಚುಕ್ಕೆ ಇರುತ್ತದೆ?',
          options: ['ಚುಕ್ಕೆ 1', 'ಚುಕ್ಕೆ 3', 'ಚುಕ್ಕೆ 4', 'ಚುಕ್ಕೆ 6'],
          answer: 'ಚುಕ್ಕೆ 4',
          hint: 'ಬಲ ಕಾಲಂನಲ್ಲಿ ಮೇಲಿನಿಂದ ಕೆಳಗೆ 4, 5, 6 ಚುಕ್ಕೆಗಳಿರುತ್ತವೆ.',
          explanation: 'ಚುಕ್ಕೆ 4 ಬಲ ಕಾಲಂನ ಮೇಲ್ಭಾಗದಲ್ಲಿದೆ.',
        ),
      ],
    ),
    LessonChapter(
      title: 'ಅಧ್ಯಾಯ 2: ಕನ್ನಡ ವರ್ಣಮಾಲೆ (ಭಾರತಿ ಬ್ರೈಲ್)',
      exercises: [
        for (final ch in kannadaCharacters)
          _vernacularExercise(ch, AppLanguage.kannada),
      ],
    ),
    LessonChapter(
      title: 'ಅಧ್ಯಾಯ 3: ಸರಳ ಕನ್ನಡ ಪದಗಳು',
      exercises: [
        for (final word in ['ಅಮ್ಮ', 'ಕಮಲ', 'ಮನೆ', 'ಜಲ', 'ನಮನ'])
          LessonExercise(
            id: 'kn-word-$word',
            skillId: 'kn-word-$word',
            exerciseType: 'word_transcription',
            prompt: '"$word" ಪದದ ಭಾರತಿ ಬ್ರೈಲ್ ಚುಕ್ಕೆಗಳನ್ನು ಬರೆಯಿರಿ.',
            options: [word, 'ಅಮ್ಮ', 'ಕಮಲ', 'ಮನೆ'],
            answer: word,
            hint: 'ಪ್ರತಿ ಅಕ್ಷರದ ಭಾರತಿ ಬ್ರೈಲ್ ಚುಕ್ಕೆಗಳನ್ನು ಕ್ರಮವಾಗಿ ನಮೂದಿಸಿ.',
            explanation: '$word ಪದವನ್ನು ಭಾರತಿ ಬ್ರೈಲ್‌ನಲ್ಲಿ ಅಕ್ಷರಗಳಾಗಿ ಬರೆಯಲಾಗುತ್ತದೆ.',
          ),
      ],
    ),
  ];

  static LessonExercise _letterExercise(String letter) {
    final dots = EnglishGrade1Engine.dotsForCell(
      EnglishGrade1Engine.encode(letter.toLowerCase()).single,
    );
    final answer = letter.toLowerCase();
    return LessonExercise(
      id: 'letter-$answer',
      skillId: 'english-letter-$answer',
      exerciseType: 'letter_recognition',
      prompt:
          'Which letter uses ${dots.length == 1 ? 'dot' : 'dots'} ${dots.join(', ')}?',
      options: [
        answer,
        ...alphabet
            .map((item) => item.toLowerCase())
            .where((item) => item != answer)
            .take(3),
      ],
      answer: answer,
      hint:
          'Explore the active dots in the lesson explanation, then choose the matching letter.',
      explanation:
          '${dots.length == 1 ? 'Dot' : 'Dots'} ${dots.join(', ')} ${dots.length == 1 ? 'is' : 'are'} the uncontracted letter $answer.',
    );
  }

  static LessonExercise _vernacularExercise(String char, AppLanguage lang) {
    final masks = BrailleDispatcher.encodeToBitmasks(char, lang);
    final dots = BrailleDispatcher.dotsForBitmask(masks.first);
    final isHindi = lang == AppLanguage.hindi;
    final pool = isHindi ? hindiCharacters : kannadaCharacters;
    return LessonExercise(
      id: '${lang.code}-char-$char',
      skillId: '${lang.code}-bharati-$char',
      exerciseType: 'letter_recognition',
      prompt: isHindi
          ? 'भारती ब्रेल में बिंदु ${dots.join(', ')} किस अक्षर के लिए हैं?'
          : 'ಭಾರತಿ ಬ್ರೈಲ್‌ನಲ್ಲಿ ಚುಕ್ಕೆಗಳು ${dots.join(', ')} ಯಾವ ಅಕ್ಷರವನ್ನು ಸೂಚಿಸುತ್ತವೆ?',
      options: [
        char,
        ...pool.where((item) => item != char).take(3),
      ],
      answer: char,
      hint: isHindi
          ? 'अक्षर $char के लिए बिंदु ${dots.join(', ')} दबाएं।'
          : '$char ಅಕ್ಷರಕ್ಕಾಗಿ ಚುಕ್ಕೆಗಳು ${dots.join(', ')} ಒತ್ತಿರಿ.',
      explanation: isHindi
          ? 'अक्षर $char के लिए भारती ब्रेल बिंदु ${dots.join(', ')} हैं।'
          : '$char ಅಕ್ಷರಕ್ಕೆ ಭಾರತಿ ಬ್ರೈಲ್ ಚುಕ್ಕೆಗಳು ${dots.join(', ')} ಆಗಿವೆ.',
    );
  }
}

class CurriculumStage {
  final String id;
  final String title;
  final int first;
  final int last;
  final String allowedLetters;
  final List<String> words;
  const CurriculumStage({
    required this.id,
    required this.title,
    required this.first,
    required this.last,
    required this.allowedLetters,
    required this.words,
  });
  bool allows(String word) => LessonCatalog.wordUsesOnly(word, allowedLetters);
}