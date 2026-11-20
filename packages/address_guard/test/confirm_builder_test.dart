import 'package:address_guard/address_guard.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final known = [KnownRecipient(paid, RecipientProvenance.sentByOwner)];
  const firstTimeAddress = '0x9999999999999999999999999999999999999999';

  /// Pumps the builder with no Material ancestor at all, the way an app with its own design
  /// system uses it, and returns a reader for the latest state and the confirmations.
  Future<(RecipientConfirmState Function(), List<ConfirmedRecipient>)> pump(
    WidgetTester tester, {
    required RecipientCheck check,
    int chainId = 56,
    bool allowOverride = false,
  }) async {
    final confirmed = <ConfirmedRecipient>[];
    late RecipientConfirmState latest;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RecipientConfirmBuilder(
          check: check,
          chainId: chainId,
          allowOverride: allowOverride,
          onConfirm: confirmed.add,
          builder: (context, state) {
            latest = state;
            return const SizedBox();
          },
        ),
      ),
    );
    return (() => latest, confirmed);
  }

  testWidgets('a known recipient can be confirmed at once, and only once', (
    tester,
  ) async {
    final (state, confirmed) = await pump(
      tester,
      check: assessRecipient(paid, known: known),
    );
    expect(state().showsConfirm, isTrue);
    expect(state().acknowledgement, isNull);
    expect(state().onAcknowledgedChanged, isNull);
    expect(state().canConfirm, isTrue);

    final confirm = state().onConfirm!;
    confirm();
    confirm();
    await tester.pump();

    expect(confirmed, hasLength(1));
    expect(confirmed.single.address, toChecksumAddress(paid));
    expect(confirmed.single.chainId, 56);
    expect(state().confirmed, isTrue);
    expect(state().canConfirm, isFalse);
  });

  testWidgets(
    'a first-time recipient needs the tick, and the tick locks once confirmed',
    (tester) async {
      final (state, confirmed) = await pump(
        tester,
        check: assessRecipient(firstTimeAddress, known: known),
      );
      expect(
        state().acknowledgement,
        RecipientAcknowledgement.checkedFullAddress,
      );
      expect(state().canConfirm, isFalse);

      state().onAcknowledgedChanged!(true);
      await tester.pump();
      expect(state().acknowledged, isTrue);
      expect(state().canConfirm, isTrue);

      final untick = state().onAcknowledgedChanged!;
      state().onConfirm!();
      await tester.pump();
      expect(state().onAcknowledgedChanged, isNull);
      // A callback kept from before confirming cannot undo the tick behind the confirmation.
      untick(false);
      await tester.pump();
      expect(state().acknowledged, isTrue);
      expect(confirmed, hasLength(1));
    },
  );

  testWidgets('a look-alike offers no confirm, and shows what it imitates', (
    tester,
  ) async {
    final (state, confirmed) = await pump(
      tester,
      check: assessRecipient(poison, known: known),
    );
    expect(state().showsConfirm, isFalse);
    expect(state().onConfirm, isNull);
    expect(state().acknowledgement, isNull);
    expect(state().imitated.single.imitated, paid);
    expect(state().imitatedCharacters, hasLength(1));

    // a1b2ffff…ffff5678 against a1b2c3d4…12345678: the shared ends are plain, the rest differs.
    final candidate = state().candidateCharacters!;
    expect(candidate.take(4).any((c) => c.inMiddle || c.differs), isFalse);
    expect(candidate.skip(36).any((c) => c.inMiddle || c.differs), isFalse);
    expect(
      candidate[4],
      const AddressCharacter('f', inMiddle: true, differs: true),
    );
    expect(confirmed, isEmpty);
  });

  testWidgets('an override is a separate, dangerous tick', (tester) async {
    final (state, confirmed) = await pump(
      tester,
      check: assessRecipient(poison, known: known),
      allowOverride: true,
    );
    expect(state().showsConfirm, isTrue);
    expect(state().overridesStop, isTrue);
    expect(state().acknowledgement, RecipientAcknowledgement.override);
    expect(state().canConfirm, isFalse);

    state().onAcknowledgedChanged!(true);
    await tester.pump();
    state().onConfirm!();
    expect(confirmed.single.verdict, RecipientVerdict.lookalike);
  });

  testWidgets('invalid input has no characters and never confirms', (
    tester,
  ) async {
    final (state, _) = await pump(
      tester,
      check: assessRecipient('0x12', known: known),
      allowOverride: true,
    );
    expect(state().candidateCharacters, isNull);
    expect(state().showsConfirm, isFalse);
    expect(state().acknowledgement, isNull);
    expect(state().onConfirm, isNull);
  });

  testWidgets(
    'a swapped recipient clears the tick; the same check rebuilt keeps it',
    (tester) async {
      var check = assessRecipient(firstTimeAddress, known: known);
      late StateSetter rebuild;
      late RecipientConfirmState latest;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return RecipientConfirmBuilder(
                check: check,
                chainId: 56,
                onConfirm: (_) {},
                builder: (context, state) {
                  latest = state;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      latest.onAcknowledgedChanged!(true);
      await tester.pump();

      rebuild(() => check = assessRecipient(firstTimeAddress, known: known));
      await tester.pump();
      expect(latest.acknowledged, isTrue);

      rebuild(
        () => check = assessRecipient(
          '0x8888888888888888888888888888888888888888',
          known: known,
        ),
      );
      await tester.pump();
      expect(latest.acknowledged, isFalse);
      expect(latest.canConfirm, isFalse);
    },
  );

  testWidgets(
    'a callback kept from an earlier recipient cannot tick or confirm the next',
    (tester) async {
      // A sheet built once from the state of A, still open when the parent swaps in B.
      var check = assessRecipient(firstTimeAddress, known: known);
      const swapped = '0x8888888888888888888888888888888888888888';
      final confirmed = <ConfirmedRecipient>[];
      late StateSetter rebuild;
      late RecipientConfirmState latest;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return RecipientConfirmBuilder(
                check: check,
                chainId: 56,
                onConfirm: confirmed.add,
                builder: (context, state) {
                  latest = state;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      final tickA = latest.onAcknowledgedChanged!;
      tickA(true);
      await tester.pump();
      final confirmA = latest.onConfirm!;

      rebuild(() => check = assessRecipient(swapped, known: known));
      await tester.pump();
      tickA(true);
      await tester.pump();
      expect(latest.acknowledged, isFalse);
      confirmA();
      await tester.pump();
      expect(confirmed, isEmpty);

      // The current callbacks still work, for the recipient now shown.
      latest.onAcknowledgedChanged!(true);
      await tester.pump();
      latest.onConfirm!();
      expect(confirmed.single.address, toChecksumAddress(swapped));
    },
  );

  testWidgets('a new window redraws the characters and keeps the tick', (
    tester,
  ) async {
    var check = assessRecipient(firstTimeAddress, known: known);
    late StateSetter rebuild;
    late RecipientConfirmState latest;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return RecipientConfirmBuilder(
              check: check,
              chainId: 56,
              onConfirm: (_) {},
              builder: (context, state) {
                latest = state;
                return const SizedBox();
              },
            );
          },
        ),
      ),
    );
    latest.onAcknowledgedChanged!(true);
    await tester.pump();
    expect(latest.candidateCharacters![3].inMiddle, isTrue);

    rebuild(
      () => check = assessRecipient(
        firstTimeAddress,
        known: known,
        prefixLength: 4,
      ),
    );
    await tester.pump();
    expect(latest.candidateCharacters![3].inMiddle, isFalse);
    expect(latest.acknowledged, isTrue);
  });

  testWidgets('a change that fails to draw still retires the earlier callbacks', (
    tester,
  ) async {
    // A ticked first-time recipient, then a hand-built look-alike whose imitated address cannot
    // be drawn. The tick must not carry over to it, even though drawing it throws.
    RecipientCheck check = assessRecipient(firstTimeAddress, known: known);
    final confirmed = <ConfirmedRecipient>[];
    late StateSetter rebuild;
    late RecipientConfirmState latest;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return RecipientConfirmBuilder(
              check: check,
              chainId: 56,
              allowOverride: true,
              onConfirm: confirmed.add,
              builder: (context, state) {
                latest = state;
                return const SizedBox();
              },
            );
          },
        ),
      ),
    );
    latest.onAcknowledgedChanged!(true);
    await tester.pump();
    final confirmEarlier = latest.onConfirm!;

    rebuild(
      () => check = const RecipientCheck(
        candidate: poison,
        verdict: RecipientVerdict.lookalike,
        reasons: [RecipientReason.imitatesKnownRecipient],
        lookalikes: [
          LookalikeMatch(
            imitated: 'not an address',
            source: MatchSource.knownRecipient,
            prefix: 'a1b2',
            suffix: '5678',
            candidateMiddle: '',
            imitatedMiddle: '',
          ),
        ],
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isFormatException);

    confirmEarlier();
    expect(confirmed, isEmpty);
  });

  testWidgets('a check changed in place still clears the tick', (tester) async {
    // A hand-built check whose reasons list the app later changes in place.
    final reasons = [RecipientReason.unlikeKnownRecipients];
    final check = RecipientCheck(
      candidate: firstTimeAddress,
      verdict: RecipientVerdict.firstTime,
      reasons: reasons,
    );
    late StateSetter rebuild;
    late RecipientConfirmState latest;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return RecipientConfirmBuilder(
              check: check,
              chainId: 56,
              onConfirm: (_) {},
              builder: (context, state) {
                latest = state;
                return const SizedBox();
              },
            );
          },
        ),
      ),
    );
    latest.onAcknowledgedChanged!(true);
    await tester.pump();

    rebuild(() => reasons.add(RecipientReason.othersShareEnds));
    await tester.pump();
    expect(latest.acknowledged, isFalse);
  });

  testWidgets(
    'a check changed in place is caught before a callback acts, even with no rebuild',
    (tester) async {
      final reasons = [RecipientReason.unlikeKnownRecipients];
      final (state, confirmed) = await pump(
        tester,
        check: RecipientCheck(
          candidate: firstTimeAddress,
          verdict: RecipientVerdict.firstTime,
          reasons: reasons,
        ),
      );
      final tick = state().onAcknowledgedChanged!;

      // Changed in place, and nothing rebuilds the parent before the user taps.
      reasons.add(RecipientReason.othersShareEnds);
      tick(true);
      await tester.pump();
      expect(state().acknowledged, isFalse);
      expect(confirmed, isEmpty);
    },
  );

  testWidgets(
    'a label that changes from none to the text "null" is still a change',
    (tester) async {
      String? label;
      late StateSetter rebuild;
      late RecipientConfirmState latest;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return RecipientConfirmBuilder(
                check: RecipientCheck(
                  candidate: firstTimeAddress,
                  verdict: RecipientVerdict.firstTime,
                  reasons: const [RecipientReason.unlikeKnownRecipients],
                  knownRecipient: label == null
                      ? null
                      : KnownRecipient(
                          firstTimeAddress,
                          RecipientProvenance.confirmedByUser,
                          label: label,
                        ),
                ),
                chainId: 56,
                onConfirm: (_) {},
                builder: (context, state) {
                  latest = state;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      latest.onAcknowledgedChanged!(true);
      await tester.pump();
      rebuild(() => label = 'null');
      await tester.pump();
      expect(latest.acknowledged, isFalse);
    },
  );

  testWidgets('a new label on the known recipient clears the tick', (
    tester,
  ) async {
    // The checksummed spelling with one letter's case flipped: an altered address.
    final checksummed = toChecksumAddress(paid);
    final letter = checksummed.indexOf(RegExp('[a-fA-F]'), 2);
    final flipped = checksummed[letter] == checksummed[letter].toUpperCase()
        ? checksummed[letter].toLowerCase()
        : checksummed[letter].toUpperCase();
    final altered = checksummed.replaceRange(letter, letter + 1, flipped);
    var label = 'Treasury';
    RecipientCheck check() => assessRecipient(
      altered,
      known: [
        KnownRecipient(paid, RecipientProvenance.confirmedByUser, label: label),
      ],
    );
    late StateSetter rebuild;
    late RecipientConfirmState latest;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return RecipientConfirmBuilder(
              check: check(),
              chainId: 56,
              allowOverride: true,
              onConfirm: (_) {},
              builder: (context, state) {
                latest = state;
                return const SizedBox();
              },
            );
          },
        ),
      ),
    );
    expect(latest.check.verdict, RecipientVerdict.badChecksum);
    latest.onAcknowledgedChanged!(true);
    await tester.pump();
    expect(latest.canConfirm, isTrue);

    rebuild(() => label = 'Payroll');
    await tester.pump();
    expect(latest.acknowledged, isFalse);
    expect(latest.canConfirm, isFalse);
  });

  testWidgets('callbacks kept across a rebuild of the same check still work', (
    tester,
  ) async {
    var check = assessRecipient(paid, known: known);
    final confirmed = <ConfirmedRecipient>[];
    late StateSetter rebuild;
    late RecipientConfirmState latest;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return RecipientConfirmBuilder(
              check: check,
              chainId: 56,
              onConfirm: confirmed.add,
              builder: (context, state) {
                latest = state;
                return const SizedBox();
              },
            );
          },
        ),
      ),
    );
    final confirm = latest.onConfirm!;
    rebuild(() => check = assessRecipient(paid, known: known));
    await tester.pump();
    confirm();
    expect(confirmed, hasLength(1));
  });

  testWidgets('a callback called after the step is gone does nothing', (
    tester,
  ) async {
    final (state, confirmed) = await pump(
      tester,
      check: assessRecipient(paid, known: known),
    );
    final confirm = state().onConfirm!;
    await tester.pumpWidget(const SizedBox());
    confirm();
    expect(confirmed, isEmpty);
  });

  testWidgets('an app can test its own sheet with a state it builds', (
    tester,
  ) async {
    var confirmed = false;
    final state = RecipientConfirmState(
      check: assessRecipient(paid, known: known),
      chainId: 56,
      imitated: const [],
      candidateCharacters: addressCharacters(paid),
      imitatedCharacters: const [],
      showsConfirm: true,
      overridesStop: false,
      acknowledgement: null,
      acknowledged: false,
      confirmed: false,
      onAcknowledgedChanged: null,
      onConfirm: () => confirmed = true,
    );
    expect(state.canConfirm, isTrue);
    state.onConfirm!();
    expect(confirmed, isTrue);
  });

  test('the card keeps the public type 0.2.0 shipped', () {
    expect(
      RecipientConfirmCard(
        check: assessRecipient(paid, known: known),
        chainId: 56,
        onConfirm: (_) {},
      ),
      isA<StatefulWidget>(),
    );
  });

  group('addressCharacters', () {
    test('marks the middle and keeps the casing', () {
      const checksummed = '0xA1B2c3d4E5F60718293a4b5c6D7e8f9012345678';
      final characters = addressCharacters(checksummed);
      expect(characters, hasLength(40));
      expect(
        characters.map((c) => c.character).join(),
        checksummed.substring(2),
      );
      expect(characters.take(3).any((c) => c.inMiddle), isFalse);
      expect(characters.skip(3).take(33).every((c) => c.inMiddle), isTrue);
      expect(characters.skip(36).any((c) => c.inMiddle), isFalse);
      expect(characters.any((c) => c.differs), isFalse);
    });

    test('compares without regard to case', () {
      final characters = addressCharacters(
        paid,
        compareWith: paid.toUpperCase().replaceFirst('0X', '0x'),
      );
      expect(characters.any((c) => c.differs), isFalse);
    });

    test('any lengths are accepted, as AddressText always took them', () {
      expect(
        addressCharacters(paid, prefixLength: -5, suffixLength: 50),
        addressCharacters(paid, prefixLength: 0, suffixLength: 40),
      );
      // Even an extreme length cannot overflow into a different answer.
      expect(
        addressCharacters(paid, suffixLength: -9223372036854775807),
        addressCharacters(paid, suffixLength: 0),
      );
      expect(
        addressCharacters(
          paid,
          prefixLength: 20,
          suffixLength: 20,
        ).any((c) => c.inMiddle),
        isFalse,
      );
    });

    test('throws unless both are addresses', () {
      expect(() => addressCharacters('0x12'), throwsFormatException);
      expect(
        () => addressCharacters(paid, compareWith: 'nope'),
        throwsFormatException,
      );
    });
  });

  test('each acknowledgement has its text', () {
    const strings = AddressGuardStrings();
    expect(
      strings.acknowledgement(RecipientAcknowledgement.checkedFullAddress),
      strings.firstTimeAcknowledgement,
    );
    expect(
      strings.acknowledgement(RecipientAcknowledgement.override),
      strings.overrideAcknowledgement,
    );
  });
}
