import 'package:address_guard/address_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  List<String> addresses(
    Iterable<SentTransaction> transactions, {
    BigInt? minNative,
    BigInt? minToken,
  }) => deriveKnownRecipients(
    owner,
    transactions,
    minNativeValue: minNative,
    minTokenAmount: minToken,
  ).map((recipient) => recipient.address).toList();

  test(
    'a native send and a direct token transfer the owner signed both count',
    () {
      final other = '0x3333333333333333333333333333333333333333';
      final known = deriveKnownRecipients(owner, [
        nativeSend(paid),
        tokenTransfer(other),
      ]);
      expect(known.map((r) => r.address), [paid, other]);
      expect(
        known.every((r) => r.provenance == RecipientProvenance.sentByOwner),
        isTrue,
      );
    },
  );

  test('first-seen order, deduplicated across casing', () {
    expect(
      addresses([
        tokenTransfer(paid),
        nativeSend(toChecksumAddress(paid)),
        nativeSend('0x3333333333333333333333333333333333333333'),
      ]),
      [paid, '0x3333333333333333333333333333333333333333'],
    );
  });

  test('the owner is matched whatever the casing of from', () {
    expect(
      addresses([
        sent(
          from: owner.toUpperCase().replaceFirst('0X', '0x'),
          to: paid,
          value: BigInt.one,
        ),
      ]),
      [paid],
    );
  });

  group('never counts', () {
    test(
      'a transaction someone else signed, such as a poisoning transfer into the account',
      () {
        // The attacker signs transferFrom(owner, poison, 0): the log would read as the owner's own
        // send. The transaction's own signer is the attacker, so it is not evidence.
        final attacker = '0x4444444444444444444444444444444444444444';
        expect(
          addresses([sent(from: attacker, to: poison, value: BigInt.one)]),
          isEmpty,
        );
        expect(
          addresses([
            sent(
              from: attacker,
              to: token,
              input: transferCalldata(poison, BigInt.one),
            ),
          ]),
          isEmpty,
        );
      },
    );

    test('a reverted transaction', () {
      expect(
        addresses([sent(to: paid, value: BigInt.one, succeeded: false)]),
        isEmpty,
      );
    });

    test('a zero-value native send, even with a minimum of zero', () {
      expect(
        addresses([
          nativeSend(paid, value: BigInt.zero),
        ], minNative: BigInt.zero),
        isEmpty,
      );
    });

    test('a zero-amount token transfer, even with a minimum of zero', () {
      expect(
        addresses([
          tokenTransfer(paid, amount: BigInt.zero),
        ], minToken: BigInt.zero),
        isEmpty,
      );
    });

    test('a send below the chosen minimum', () {
      expect(
        addresses([
          nativeSend(paid, value: BigInt.from(99)),
        ], minNative: BigInt.from(100)),
        isEmpty,
      );
      expect(
        addresses([
          tokenTransfer(paid, amount: BigInt.from(99)),
        ], minToken: BigInt.from(100)),
        isEmpty,
      );
      expect(
        addresses([
          nativeSend(paid, value: BigInt.from(100)),
        ], minNative: BigInt.from(100)),
        [paid],
      );
    });

    test('transferFrom, approve and any other contract call', () {
      final word = '${'0' * 24}${paid.substring(2)}';
      final amount = BigInt.from(5).toRadixString(16).padLeft(64, '0');
      for (final input in [
        '0x23b872dd${'0' * 24}${owner.substring(2)}$word$amount', // transferFrom
        '0x095ea7b3$word$amount', // approve
        '0xdeadbeef$word$amount', // something else
      ]) {
        expect(
          addresses([sent(to: token, input: input)]),
          isEmpty,
          reason: input,
        );
      }
    });

    test('a native value attached to a contract call', () {
      // The contract decides where that value goes; `to` is not the recipient.
      expect(
        addresses([sent(to: token, value: BigInt.one, input: '0xd0e30db0')]),
        isEmpty,
      );
    });

    test(
      'a contract creation and malformed records, without hiding the rest',
      () {
        expect(
          addresses([
            sent(value: BigInt.one), // to: null
            sent(to: 'not-an-address', value: BigInt.one),
            sent(from: 'not-an-address', to: paid, value: BigInt.one),
            nativeSend(paid),
          ]),
          [paid],
        );
      },
    );
  });

  group('decodeErc20Transfer', () {
    test('decodes a well-formed call, in any casing', () {
      final call = decodeErc20Transfer(
        transferCalldata(paid, BigInt.parse('1000000000000000000')),
      )!;
      expect(call.recipient, paid);
      expect(call.amount, BigInt.parse('1000000000000000000'));
      expect(
        decodeErc20Transfer(
          transferCalldata(
            paid,
            BigInt.one,
          ).toUpperCase().replaceFirst('0X', '0x'),
        ),
        isNotNull,
      );
    });

    test('refuses anything that only resembles one', () {
      final good = transferCalldata(paid, BigInt.one);
      for (final input in [
        good.substring(0, good.length - 2), // short
        '${good}00', // trailing bytes
        good.replaceFirst('a9059cbb', 'a9059cbc'), // other selector
        '0xa9059cbb${'0' * 23}1${paid.substring(2)}${'0' * 63}1', // dirty upper address bytes
        good.replaceFirst('0x', ''), // no prefix
      ]) {
        expect(decodeErc20Transfer(input), isNull, reason: input);
      }
    });
  });

  test('recipientNamedBy explains a single record', () {
    expect(recipientNamedBy(nativeSend(paid), owner: owner), paid);
    expect(recipientNamedBy(nativeSend(paid), owner: paid), isNull);
  });

  test('KnownRecipient lower-cases and validates', () {
    final recipient = KnownRecipient(
      toChecksumAddress(paid),
      RecipientProvenance.confirmedByUser,
      label: 'Supplier',
    );
    expect(recipient.address, paid);
    expect(
      recipient,
      KnownRecipient(
        paid,
        RecipientProvenance.confirmedByUser,
        label: 'Supplier',
      ),
    );
    expect(
      () => KnownRecipient('0x12', RecipientProvenance.confirmedByUser),
      throwsFormatException,
    );
  });

  test('throws FormatException for an owner that is not an address', () {
    expect(() => deriveKnownRecipients('owner', []), throwsFormatException);
  });
}
