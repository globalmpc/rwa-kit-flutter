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
        final middle = 4 + random.nextInt(32);
        expect(
          findLookalikes(mutateAt(known, middle), [known]),
          hasLength(1),
          reason: 'middle index $middle of $known',
        );
        final end = random.nextBool()
            ? random.nextInt(4)
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
