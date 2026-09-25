import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

import 'support.dart';

void main() {
  group('MnemonicWords.generate', () {
    for (final count in [12, 15, 18, 21, 24]) {
      test('makes a valid $count-word phrase', () {
        final words = MnemonicWords.generate(wordCount: count);
        expect(words.length, count);
        expect(words.words.every(Language.english.list.contains), isTrue);
        expect(MnemonicWords.parse(words.sentence), words);
      });
    }

    test('makes a different phrase each time', () {
      expect(MnemonicWords.generate(), isNot(MnemonicWords.generate()));
    });

    test('rejects a word count BIP39 does not define', () {
      expect(() => MnemonicWords.generate(wordCount: 13), throwsArgumentError);
    });
  });

  group('MnemonicWords.parse', () {
    test('accepts the specification vector', () {
      final words = MnemonicWords.parse(specVector12);
      expect(words.length, 12);
      expect(words.words.last, 'about');
    });

    test('ignores surrounding whitespace, line breaks, and letter case', () {
      final messy =
          '  Abandon\n abandon\tabandon abandon abandon abandon abandon abandon abandon abandon abandon  ABOUT \n';
      expect(MnemonicWords.parse(messy), MnemonicWords.parse(specVector12));
    });

    test('reports a wrong word count with the count entered', () {
      expect(
        () => MnemonicWords.parse('abandon abandon abandon'),
        throwsA(
          isA<MnemonicFormatException>()
              .having(
                (e) => e.problem,
                'problem',
                MnemonicFormatProblem.wordCount,
              )
              .having((e) => e.wordCount, 'wordCount', 3),
        ),
      );
    });

    test('reports the first word that is not in the word list', () {
      final withTypo = specVector12.replaceFirst('abandon', 'abandom');
      expect(
        () => MnemonicWords.parse(withTypo),
        throwsA(
          isA<MnemonicFormatException>()
              .having(
                (e) => e.problem,
                'problem',
                MnemonicFormatProblem.unknownWord,
              )
              .having((e) => e.word, 'word', 'abandom'),
        ),
      );
    });

    test(
      'fromList lower-cases and trims each word as parse does, and holds the normalised words',
      () {
        final asScanned = [
          for (final word in specVector12.split(' '))
            ' ${word[0].toUpperCase()}${word.substring(1)}\t',
        ];
        final words = MnemonicWords.fromList(asScanned);
        expect(words, MnemonicWords.parse(specVector12));
        expect(words.words.first, 'abandon');
      },
    );

    test(
      'fromList reports an unknown word as given, without its surrounding whitespace',
      () {
        final given = specVector12.split(' ')..[3] = ' Abandom\t';
        expect(
          () => MnemonicWords.fromList(given),
          throwsA(
            isA<MnemonicFormatException>().having(
              (e) => e.word,
              'word',
              'Abandom',
            ),
          ),
        );
      },
    );

    test('fromList ignores blank entries, as parse does', () {
      final withBlanks = ['', ...specVector12.split(' '), ' \n'];
      expect(
        MnemonicWords.fromList(withBlanks),
        MnemonicWords.parse(specVector12),
      );
    });

    test('reports a checksum mismatch when every word is valid', () {
      expect(
        () => MnemonicWords.parse(specVector12BadChecksum),
        throwsA(
          isA<MnemonicFormatException>().having(
            (e) => e.problem,
            'problem',
            MnemonicFormatProblem.checksum,
          ),
        ),
      );
    });
  });

  group('secrecy', () {
    test('toString never contains a word', () {
      final words = MnemonicWords.parse(specVector12);
      expect(words.toString(), 'MnemonicWords(12 words)');
      expect('$words', isNot(contains('abandon')));
    });

    test('the exception never contains the offending word in its text', () {
      const exception = MnemonicFormatException.unknownWord('abandom');
      expect(exception.toString(), isNot(contains('abandom')));
      expect(
        const MnemonicFormatException.wordCount(3).toString(),
        'MnemonicFormatException(wordCount, 3 words)',
      );
    });

    test('words cannot be modified through the list', () {
      final words = MnemonicWords.parse(specVector12);
      expect(() => words.words[0] = 'zoo', throwsUnsupportedError);
    });
  });
}
