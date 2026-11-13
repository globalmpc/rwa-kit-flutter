import 'package:address_guard/address_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final known = [KnownRecipient(paid, RecipientProvenance.sentByOwner)];

  /// The real token the owner pays with, and a counterfeit that copies its name.
  const usdt = token;
  const fakeUsdt = '0x3333333333333333333333333333333333333333';

  HistoryTransfer transfer(
    String from,
    String to, {
    int amount = 0,
    String? token = usdt,
  }) => HistoryTransfer(
    from: from,
    to: to,
    amount: BigInt.from(amount),
    token: token,
  );

  test('flags the three kinds of poisoning transfer, with their signs', () {
    final suspects = screenHistory(
      owner,
      [
        // 0: the owner's real payment. Never a suspect.
        transfer(owner, paid, amount: 250000000),
        // 1: zero-value transferFrom(owner, poison, 0): the log names the owner as sender.
        transfer(owner, poison),
        // 2: a counterfeit token "sent" to the owner from the look-alike.
        transfer(poison, owner, amount: 5000000, token: fakeUsdt),
        // 3: a tiny amount of the real token from the look-alike.
        transfer(poison, owner, amount: 1),
      ],
      known: known,
      listedTokens: [usdt],
      isDust: (entry) => entry.amount < BigInt.from(1000000),
    );

    expect(suspects.map((suspect) => suspect.index), [1, 2, 3]);
    expect(suspects[0].signs, [
      PoisoningSign.zeroValue,
      PoisoningSign.namesOwnerAsSender,
    ]);
    expect(suspects[1].signs, [PoisoningSign.unlistedToken]);
    expect(suspects[2].signs, [PoisoningSign.dust]);
    for (final suspect in suspects) {
      expect(suspect.counterparty, poison);
      expect(suspect.imitates.single.imitated, paid);
    }
  });

  test('a look-alike is suspect on its own, with no other sign', () {
    final suspects = screenHistory(owner, [
      transfer(poison, owner, amount: 5000000),
    ], known: known);
    expect(suspects.single.signs, isEmpty);
  });

  test('the signs that need app data are off without it', () {
    final suspects = screenHistory(owner, [
      transfer(poison, owner, amount: 1, token: fakeUsdt),
    ], known: known);
    expect(suspects.single.signs, isEmpty);
  });

  test('a zero amount is never also called dust', () {
    final suspects = screenHistory(
      owner,
      [transfer(poison, owner)],
      known: known,
      isDust: (_) => true,
    );
    expect(suspects.single.signs, [PoisoningSign.zeroValue]);
  });

  test('a known counterparty is never a suspect, whatever it sent', () {
    final suspects = screenHistory(
      owner,
      [transfer(paid, owner), transfer(owner, paid, token: fakeUsdt)],
      known: known,
      listedTokens: [usdt],
    );
    expect(suspects, isEmpty);
  });

  test('a look-alike the owner only saved is still a suspect', () {
    // Copying the look-alike from the history into the address book is the attack succeeding.
    final suspects = screenHistory(
      owner,
      [transfer(poison, owner)],
      known: [
        ...known,
        KnownRecipient(poison, RecipientProvenance.confirmedByUser),
      ],
    );
    expect(suspects.single.counterparty, poison);
  });

  test('two saved addresses that resemble each other flag each other', () {
    // Nothing says which one is real, and a false alarm is the safe mistake.
    const real = '0x7777aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9999';
    const copy = '0x7777bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb9999';
    final suspects = screenHistory(
      owner,
      [transfer(real, owner, amount: 5), transfer(copy, owner)],
      known: [
        ...known,
        KnownRecipient(real, RecipientProvenance.confirmedByUser),
        KnownRecipient(copy, RecipientProvenance.confirmedByUser),
      ],
    );
    expect(suspects.map((suspect) => suspect.counterparty), [real, copy]);
  });

  test('a saved look-alike of a saved-only address stays flagged', () {
    // The supplier was paid through a contract, so it is only saved. The user then saved the
    // look-alike copied from the history. Screening again must still flag it.
    final saved = [
      KnownRecipient(paid, RecipientProvenance.confirmedByUser),
      KnownRecipient(poison, RecipientProvenance.confirmedByUser),
    ];
    final suspects = screenHistory(owner, [
      transfer(owner, poison),
    ], known: saved);
    expect(suspects.single.counterparty, poison);
    final check = assessRecipient(poison, known: saved, suspects: suspects);
    expect(check.verdict, RecipientVerdict.lookalike);
  });

  test(
    'a native send from the owner is never a suspect: the owner signed it',
    () {
      final suspects = screenHistory(owner, [
        transfer(owner, poison, amount: 10, token: null),
        transfer(owner, poison, token: null),
      ], known: known);
      expect(suspects, isEmpty);
    },
  );

  test('an address the owner really paid is never a suspect', () {
    final suspects = screenHistory(
      owner,
      [transfer(poison, owner)],
      known: [
        ...known,
        KnownRecipient(poison, RecipientProvenance.sentByOwner),
      ],
    );
    expect(suspects, isEmpty);
  });

  test('a mistyped token list throws instead of calling every token fake', () {
    expect(
      () => screenHistory(
        owner,
        [transfer(poison, owner)],
        known: known,
        listedTokens: [' $usdt'],
      ),
      throwsFormatException,
    );
  });

  test('an unrelated counterparty is not a suspect, even for zero', () {
    final suspects = screenHistory(owner, [
      transfer('0x9999999999999999999999999999999999999999', owner),
    ], known: known);
    expect(suspects, isEmpty);
  });

  test('with no known recipients there is nothing to imitate', () {
    expect(
      screenHistory(owner, [transfer(owner, poison)], known: const []),
      isEmpty,
    );
  });

  test('matches native-coin transfers too', () {
    final suspects = screenHistory(
      owner,
      [transfer(poison, owner, amount: 10, token: null)],
      known: known,
      listedTokens: [usdt],
    );
    expect(suspects.single.signs, isEmpty);
  });

  test('compares case-insensitively', () {
    final suspects = screenHistory(
      toChecksumAddress(owner),
      [transfer(toChecksumAddress(owner), toChecksumAddress(poison))],
      known: known,
      listedTokens: [toChecksumAddress(usdt)],
    );
    expect(suspects.single.counterparty, poison);
  });

  test('skips entries it cannot read, and entries without the owner', () {
    final suspects = screenHistory(owner, [
      transfer('0x12', owner),
      transfer(poison, '0x12'),
      HistoryTransfer(from: poison, to: owner, amount: BigInt.from(-1)),
      transfer(owner, owner),
      transfer(poison, paid),
      transfer(poison, owner),
    ], known: known);
    expect(suspects.map((suspect) => suspect.index), [5]);
  });

  test(
    'a malformed token field still raises the alarm, as an unlisted token',
    () {
      // Indexers give "" or a symbol here. The look-alike must not slip through on that.
      final suspects = screenHistory(
        owner,
        [
          transfer(poison, owner, amount: 5, token: 'USDT'),
          transfer(poison, owner, amount: 5, token: ''),
        ],
        known: known,
        listedTokens: [usdt],
      );
      expect(suspects, hasLength(2));
      for (final suspect in suspects) {
        expect(suspect.signs, contains(PoisoningSign.unlistedToken));
      }
    },
  );

  test('honours the window, and throws for a bad owner or window', () {
    expect(
      screenHistory(
        owner,
        [transfer(poison, owner)],
        known: known,
        prefixLength: 6,
        suffixLength: 6,
      ),
      isEmpty,
    );
    expect(
      () => screenHistory('0x12', const [], known: known),
      throwsFormatException,
    );
    expect(
      () => screenHistory(owner, const [], known: known, prefixLength: 0),
      throwsArgumentError,
    );
  });

  test('the flagged counterparties stop the confirm card verdict', () {
    final suspects = screenHistory(owner, [
      transfer(owner, poison),
    ], known: known);
    final check = assessRecipient(
      toChecksumAddress(poison),
      known: known,
      suspects: suspects,
    );
    expect(check.verdict, RecipientVerdict.lookalike);
    expect(check.reasons, [
      RecipientReason.imitatesKnownRecipient,
      RecipientReason.plantedInHistory,
    ]);
  });

  test('the results cannot be changed by the caller', () {
    final suspect = screenHistory(owner, [
      transfer(owner, poison),
    ], known: known).single;
    expect(() => suspect.signs.add(PoisoningSign.dust), throwsUnsupportedError);
    expect(() => suspect.imitates.clear(), throwsUnsupportedError);
  });
}
