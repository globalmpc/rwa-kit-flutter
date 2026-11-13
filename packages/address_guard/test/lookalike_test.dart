import 'dart:math';

import 'package:address_guard/address_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('flags the generated look-alike of a paid address', () {
    final matches = findLookalikes(poison, [paid]);
    expect(matches, hasLength(1));
    final match = matches.single;
    expect(match.imitated, paid);
    expect(match.source, MatchSource.knownRecipient);
    expect(match.prefix, 'a1b2');
    expect(match.suffix, '5678');
    expect(match.candidateMiddle, 'f' * 32);
    expect(match.imitatedMiddle, paid.substring(6, 38));
  });

  test('an exact match is never a look-alike, whatever the casing', () {
    expect(findLookalikes(paid, [paid]), isEmpty);
    expect(findLookalikes(toChecksumAddress(paid), [paid]), isEmpty);
  });

  test(
    'changing any middle character always flags; changing an end never does',
    () {
      final random = Random(7);
      for (var round = 0; round < 200; round++) {
        final known =
            '0x${List.generate(40, (_) => '0123456789abcdef'[random.nextInt(16)]).join()}';
        // Three at the start and four at the end must match, so index 3 is already middle.
        final middle = 3 + random.nextInt(33);
        expect(
          findLookalikes(mutateAt(known, middle), [known]),
          hasLength(1),
          reason: 'middle index $middle of $known',
        );
        final end = random.nextBool()
            ? random.nextInt(3)
            : 36 + random.nextInt(4);
        expect(
          findLookalikes(mutateAt(known, end), [known]),
          isEmpty,
          reason: 'end index $end of $known',
        );
      }
    },
  );

  test(
    'compares case-insensitively and reports each imitated address once',
    () {
      final matches = findLookalikes(
        poison.toUpperCase().replaceFirst('0X', '0x'),
        [paid, toChecksumAddress(paid)],
      );
      expect(matches, hasLength(1));
    },
  );

  test(
    'the defaults are the measured minimum: three at the start, four at the end',
    () {
      expect(defaultPrefixLength, 3);
      expect(defaultSuffixLength, 4);
      // Three and four: the smallest look-alike seen in the 2025 measurement.
      const threeAndFour = '0xa1bfffffffffffffffffffffffffffffffff5678';
      expect(findLookalikes(threeAndFour, [paid]), hasLength(1));
      // Two at the start, or three at the end, is not enough.
      const twoAndFour = '0xa1ffffffffffffffffffffffffffffffffff5678';
      const threeAndThree = '0xa1bfffffffffffffffffffffffffffffffff0678';
      expect(findLookalikes(twoAndFour, [paid]), isEmpty);
      expect(findLookalikes(threeAndThree, [paid]), isEmpty);
      // 0.1.0 required four at the start; pass that to keep it.
      expect(
        findLookalikes(threeAndFour, [paid], prefixLength: 4, suffixLength: 4),
        isEmpty,
      );
    },
  );

  test('reports every shared character, not only the window', () {
    const sixAndSix = '0xa1b2c3ffffffffffffffffffffffffffff345678';
    final match = findLookalikes(sixAndSix, [paid]).single;
    expect(match.prefix, 'a1b2c3');
    expect(match.suffix, '345678');
    expect(match.sharedLength, 12);
    expect(match.candidateMiddle, 'f' * 28);
    expect(match.imitatedMiddle, paid.substring(8, 36));
  });

  test('two addresses one character apart share everything else', () {
    final match = findLookalikes(mutateAt(paid, 20), [paid]).single;
    expect(match.prefix.length, 20);
    expect(match.suffix.length, 19);
    expect(match.candidateMiddle, hasLength(1));
  });

  test('closest copy first, then in the order given', () {
    const fourAndFour = '0xa1b2ffffffffffffffffffffffffffffffff5678';
    const sixAndSix = '0xa1b2c3eeeeeeeeeeeeeeeeeeeeeeeeeeee345678';
    const otherFourAndFour = '0xa1b2dddddddddddddddddddddddddddddddd5678';
    final matches = findLookalikes(paid, [
      fourAndFour,
      sixAndSix,
      otherFourAndFour,
    ]);
    expect(matches.map((match) => match.imitated), [
      sixAndSix,
      fourAndFour,
      otherFourAndFour,
    ]);
  });

  test('honours a wider window', () {
    final sixAndSix = '0xa1b2c3ffffffffffffffffffffffffffff345678';
    expect(
      findLookalikes(sixAndSix, [paid], prefixLength: 6, suffixLength: 6),
      hasLength(1),
    );
    expect(
      findLookalikes(poison, [paid], prefixLength: 6, suffixLength: 6),
      isEmpty,
    );
  });

  test('records the source it was given', () {
    final match = findLookalikes(poison, [
      paid,
    ], source: MatchSource.sameBatch).single;
    expect(match.source, MatchSource.sameBatch);
  });

  test('refuses a window that leaves no middle or is below one', () {
    expect(
      () => findLookalikes(poison, [paid], prefixLength: 0),
      throwsArgumentError,
    );
    expect(
      () => findLookalikes(poison, [paid], suffixLength: 0),
      throwsArgumentError,
    );
    expect(
      () => findLookalikes(poison, [paid], prefixLength: 20, suffixLength: 20),
      throwsArgumentError,
    );
    expect(
      findLookalikes(poison, [paid], prefixLength: 20, suffixLength: 19),
      isEmpty,
    );
  });

  test('throws FormatException for a non-address on either side', () {
    expect(() => findLookalikes('0x12', [paid]), throwsFormatException);
    expect(() => findLookalikes(poison, ['0x12']), throwsFormatException);
  });
}
