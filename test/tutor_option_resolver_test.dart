import 'package:flutter_test/flutter_test.dart';
import 'package:resonant_braille/tutor/tutor_option_resolver.dart';

void main() {
  const options = ['Dot 1 only', 'Dots 1, 2, and 3', 'Dots 1 and 4'];

  test('resolves visible options by letter and ordinal', () {
    expect(TutorOptionResolver.resolveIndex(options, 'option B'), 1);
    expect(TutorOptionResolver.resolveIndex(options, 'the second one'), 1);
    expect(TutorOptionResolver.resolveIndex(options, 'option 1'), 0);
    expect(TutorOptionResolver.resolveIndex(options, 'option 2'), 1);
    expect(TutorOptionResolver.resolveIndex(options, 'option 3'), 2);
  });

  test('resolves a unique visible option by its text', () {
    expect(TutorOptionResolver.resolveIndex(options, 'dots 1 and 4'), 2);
    expect(
      TutorOptionResolver.resolveIndex(
        options,
        'select the option about dot 4',
      ),
      2,
    );
  });

  test('refuses an ambiguous or unavailable option', () {
    expect(
      TutorOptionResolver.resolveIndex(const [
        'dots 1 and 2',
        'dots 1 and 3',
      ], 'dots 1'),
      isNull,
    );
    expect(TutorOptionResolver.resolveIndex(options, 'option D'), isNull);
    expect(TutorOptionResolver.resolveIndex(const [], 'option A'), isNull);
  });
}
