import 'package:address_guard/address_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final known = [KnownRecipient(paid, RecipientProvenance.sentByOwner)];

  test('the look-alike of a paid address is a look-alike, with evidence', () {
    final check = assessRecipient(poison, known: known);
    expect(check.verdict, RecipientVerdict.lookalike);
    expect(check.shouldStop, isTrue);
    expect(check.reasons, [
      RecipientReason.noChecksum,
      RecipientReason.imitatesKnownRecipient,
    ]);
    expect(check.lookalikes.single.imitated, paid);
    expect(check.normalized, poison);
  });

  test('an exact known recipient is known, and keeps its record', () {
    final labelled = [
      KnownRecipient(
        paid,
        RecipientProvenance.confirmedByUser,
        label: 'Supplier',
      ),
    ];
    final check = assessRecipient(toChecksumAddress(paid), known: labelled);
    expect(check.verdict, RecipientVerdict.known);
    expect(check.shouldStop, isFalse);
    expect(check.knownRecipient?.label, 'Supplier');
    expect(check.checksum, ChecksumState.checksummed);
    expect(check.reasons, [RecipientReason.savedRecipient]);
  });

  test(
    'a known recipient stays known when other known addresses share its ends',
    () {
      final both = [
        ...known,
        KnownRecipient(poison, RecipientProvenance.confirmedByUser),
      ];
      final check = assessRecipient(paid, known: both);
      expect(check.verdict, RecipientVerdict.known);
      expect(check.reasons, [
        RecipientReason.noChecksum,
        RecipientReason.knownRecipient,
        RecipientReason.othersShareEnds,
      ]);
      expect(check.lookalikes, hasLength(1));
    },
  );

  test(
    'a known address with altered casing is not known: it was edited by hand',
    () {
      final altered = flipFirstLetter(toChecksumAddress(paid));
      expect(checksumState(altered), ChecksumState.mismatch);
      final check = assessRecipient(altered, known: known);
      expect(check.verdict, RecipientVerdict.badChecksum);
      expect(check.reasons, [RecipientReason.checksumMismatch]);
    },
  );

  test('a look-alike outranks a checksum complaint', () {
    final flipped = flipFirstLetter(toChecksumAddress(poison));
    expect(checksumState(flipped), ChecksumState.mismatch);
    final check = assessRecipient(flipped, known: known);
    expect(check.verdict, RecipientVerdict.lookalike);
    expect(check.reasons.first, RecipientReason.checksumMismatch);
  });

  test('an unrelated address is a first-time recipient', () {
    final check = assessRecipient(
      '0x9999999999999999999999999999999999999999',
      known: known,
    );
    expect(check.verdict, RecipientVerdict.firstTime);
    expect(check.reasons.last, RecipientReason.unlikeKnownRecipients);
    expect(check.shouldStop, isFalse);
  });

  test('with no known recipients, says nothing could be compared', () {
    final check = assessRecipient(paid, known: const []);
    expect(check.verdict, RecipientVerdict.firstTime);
    expect(check.reasons.last, RecipientReason.nothingToCompare);
  });

  test('invalid input is invalid, and keeps the input as given', () {
    final check = assessRecipient(' 0x12 ', known: known);
    expect(check.verdict, RecipientVerdict.invalid);
    expect(check.candidate, ' 0x12 ');
    expect(check.normalized, isNull);
    expect(check.reasons, [RecipientReason.notAnAddress]);
  });

  test('a batch match flags a look-alike but never makes an address known', () {
    final check = assessRecipient(poison, known: const [], batch: [paid]);
    expect(check.verdict, RecipientVerdict.lookalike);
    expect(check.reasons.last, RecipientReason.imitatesBatchEntry);
    expect(check.lookalikes.single.source, MatchSource.sameBatch);
    expect(
      assessRecipient(paid, known: const [], batch: [paid]).verdict,
      RecipientVerdict.firstTime,
    );
  });

  test('the window is applied and recorded', () {
    final check = assessRecipient(
      poison,
      known: known,
      prefixLength: 6,
      suffixLength: 6,
    );
    expect(check.verdict, RecipientVerdict.firstTime);
    expect(check.prefixLength, 6);
    expect(
      () => assessRecipient(poison, known: known, prefixLength: 0),
      throwsArgumentError,
    );
  });

  test('end to end: the poisoned history never makes the look-alike known', () {
    // The owner paid `paid` once. The attacker then sent the owner a zero-value token transfer
    // from `poison`, so `poison` sits in the history. Only the owner's own sends are replayed.
    final attacker = '0x4444444444444444444444444444444444444444';
    final mine = deriveKnownRecipients(owner, [
      tokenTransfer(paid),
      sent(
        from: attacker,
        to: token,
        input: transferCalldata(owner, BigInt.zero),
      ),
    ]);
    expect(
      assessRecipient(poison, known: mine).verdict,
      RecipientVerdict.lookalike,
    );
    expect(assessRecipient(paid, known: mine).verdict, RecipientVerdict.known);
  });

  test('an address both paid and saved shows the address-book label', () {
    final both = [
      KnownRecipient(paid, RecipientProvenance.sentByOwner),
      KnownRecipient(
        paid,
        RecipientProvenance.confirmedByUser,
        label: 'Supplier',
      ),
    ];
    expect(
      assessRecipient(paid, known: both).knownRecipient?.label,
      'Supplier',
    );
  });

  test('a malformed batch row is skipped, not thrown on', () {
    final check = assessRecipient(
      poison,
      known: const [],
      batch: ['0x12 typo', paid],
    );
    expect(check.verdict, RecipientVerdict.lookalike);
    expect(check.lookalikes.single.imitated, paid);
  });

  test(
    'a batch row that imitates a known recipient does not claim to be known',
    () {
      final check = assessRecipient(paid, known: known, batch: [poison]);
      expect(check.verdict, RecipientVerdict.known);
      expect(check.reasons, isNot(contains(RecipientReason.othersShareEnds)));
    },
  );

  test('an all-capitals spelling of a known address is known', () {
    final capitals = '0x${paid.substring(2).toUpperCase()}';
    expect(
      assessRecipient(capitals, known: known).verdict,
      RecipientVerdict.known,
    );
  });

  test(
    'a known address with altered casing is badChecksum even when others share its ends',
    () {
      final both = [
        ...known,
        KnownRecipient(poison, RecipientProvenance.sentByOwner),
      ];
      final check = assessRecipient(
        flipFirstLetter(toChecksumAddress(paid)),
        known: both,
      );
      expect(check.verdict, RecipientVerdict.badChecksum);
    },
  );

  test(
    'a saved address that was never paid is known, with the saved reason',
    () {
      final saved = [KnownRecipient(paid, RecipientProvenance.confirmedByUser)];
      final check = assessRecipient(paid, known: saved);
      expect(check.verdict, RecipientVerdict.known);
      expect(check.reasons, contains(RecipientReason.savedRecipient));
      expect(check.reasons, isNot(contains(RecipientReason.knownRecipient)));
    },
  );

  test('a known address that is also a batch row is reported once', () {
    final check = assessRecipient(poison, known: known, batch: [paid]);
    expect(check.lookalikes, hasLength(1));
    expect(check.lookalikes.single.source, MatchSource.knownRecipient);
  });

  test('altered casing of a saved address keeps its label', () {
    final saved = [
      KnownRecipient(
        paid,
        RecipientProvenance.confirmedByUser,
        label: 'Landlord',
      ),
    ];
    final check = assessRecipient(
      flipFirstLetter(toChecksumAddress(paid)),
      known: saved,
    );
    expect(check.verdict, RecipientVerdict.badChecksum);
    expect(check.knownRecipient?.label, 'Landlord');
  });
}
