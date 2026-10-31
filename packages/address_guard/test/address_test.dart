import 'package:address_guard/address_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The test cases published in EIP-55 itself.
  const specification = [
    // All caps
    '0x52908400098527886E0F7030069857D2E4169EE7',
    '0x8617E340B3D01FA5F11F306F4090FD50E238070D',
    // All lower
    '0xde709f2102306220921060314715629080e2fb77',
    '0x27b1fdb04752bbc536007a920d24acb045561c26',
    // Normal
    '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
    '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
    '0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB',
    '0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb',
  ];

  group('isEvmAddress', () {
    test('accepts 0x and 40 hex characters in any casing', () {
      expect(
        isEvmAddress('0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'),
        isTrue,
      );
      expect(isEvmAddress('0x${'A' * 40}'), isTrue);
    });

    test('refuses everything else, including invisible whitespace', () {
      for (final value in [
        '',
        '0x',
        '5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAe',
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAedd',
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeg',
        ' 0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed\n',
        '0X5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      ]) {
        expect(isEvmAddress(value), isFalse, reason: value);
      }
    });
  });

  group('toChecksumAddress', () {
    test('produces every EIP-55 specification spelling from lower case', () {
      for (final address in specification) {
        expect(toChecksumAddress(address.toLowerCase()), address);
        expect(
          toChecksumAddress(address.toUpperCase().replaceFirst('0X', '0x')),
          address,
        );
      }
    });

    test('throws FormatException for a non-address', () {
      expect(() => toChecksumAddress('0x1234'), throwsFormatException);
    });
  });

  group('checksumState', () {
    test('the specification spellings are checksummed', () {
      for (final address in specification) {
        expect(
          checksumState(address),
          ChecksumState.checksummed,
          reason: address,
        );
      }
    });

    test('all lower case with letters is unchecksummed, not wrong', () {
      expect(
        checksumState('0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed'),
        ChecksumState.unchecksummed,
      );
    });

    test('one flipped letter is a mismatch', () {
      expect(
        checksumState('0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'),
        ChecksumState.mismatch,
      );
    });

    test('all upper case carries no checksum, like all lower case', () {
      expect(
        checksumState('0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED'),
        ChecksumState.unchecksummed,
      );
      expect(
        checksumState('0x52908400098527886E0F7030069857D2E4169EE7'),
        ChecksumState.checksummed,
      );
    });
  });

  test(
    'isValidChecksum accepts checksummed and unchecksummed, refuses a mismatch',
    () {
      expect(
        isValidChecksum('0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'),
        isTrue,
      );
      expect(
        isValidChecksum('0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed'),
        isTrue,
      );
      expect(
        isValidChecksum('0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'),
        isFalse,
      );
      expect(
        isValidChecksum('0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED'),
        isTrue,
      );
      expect(isValidChecksum('not an address'), isFalse);
    },
  );

  test('normalizeAddress lower-cases and validates', () {
    expect(
      normalizeAddress('0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'),
      '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed',
    );
    expect(() => normalizeAddress('0xzz'), throwsFormatException);
  });
}
