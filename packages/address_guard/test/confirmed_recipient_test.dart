import 'package:address_guard/address_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final confirmed = ConfirmedRecipient(
    address: paid,
    chainId: 56,
    verdict: RecipientVerdict.known,
  );

  test('stores the checksummed spelling', () {
    expect(confirmed.address, toChecksumAddress(paid));
  });

  test('matches the same address on the same chain, whatever the casing', () {
    expect(confirmed.matches(paid, 56), isTrue);
    expect(confirmed.matches(toChecksumAddress(paid), 56), isTrue);
  });

  test('does not match another address, another chain, or a non-address', () {
    expect(confirmed.matches(poison, 56), isFalse);
    expect(confirmed.matches(paid, 1), isFalse);
    expect(confirmed.matches('not an address', 56), isFalse);
  });

  test('refuses a non-address', () {
    expect(
      () => ConfirmedRecipient(
        address: '0x12',
        chainId: 56,
        verdict: RecipientVerdict.known,
      ),
      throwsFormatException,
    );
  });
}
