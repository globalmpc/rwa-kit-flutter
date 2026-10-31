import 'package:address_guard/address_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final known = [KnownRecipient(paid, RecipientProvenance.sentByOwner)];
  const firstTimeAddress = '0x9999999999999999999999999999999999999999';
  const strings = AddressGuardStrings();

  Future<List<ConfirmedRecipient>> pumpCard(
    WidgetTester tester, {
    required RecipientCheck check,
    int chainId = 56,
    bool allowOverride = false,
    VoidCallback? onCancel,
    double textScale = 1,
  }) async {
    final confirmed = <ConfirmedRecipient>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: RecipientConfirmCard(
                check: check,
                chainId: chainId,
                networkName: 'BNB Smart Chain',
                allowOverride: allowOverride,
                onCancel: onCancel,
                onConfirm: confirmed.add,
              ),
            ),
          ),
        ),
      ),
    );
    return confirmed;
  }

  Finder confirmButton() => find.widgetWithText(FilledButton, strings.confirm);

  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(confirmButton()).onPressed != null;

  testWidgets('a known recipient can be confirmed at once, and only once', (
    tester,
  ) async {
    final confirmed = await pumpCard(
      tester,
      check: assessRecipient(paid, known: known),
    );
    expect(find.text(strings.titleKnown), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(enabled(tester), isTrue);

    await tester.tap(confirmButton());
    await tester.tap(confirmButton(), warnIfMissed: false);
    await tester.pump();

    expect(confirmed, hasLength(1));
    expect(confirmed.single.address, toChecksumAddress(paid));
    expect(confirmed.single.chainId, 56);
    expect(confirmed.single.verdict, RecipientVerdict.known);
    expect(enabled(tester), isFalse);
  });

  testWidgets('a first-time recipient needs the full-address tick first', (
    tester,
  ) async {
    final confirmed = await pumpCard(
      tester,
      check: assessRecipient(firstTimeAddress, known: known),
    );
    expect(find.text(strings.titleFirstTime), findsOneWidget);
    expect(enabled(tester), isFalse);

    await tester.tap(find.text(strings.firstTimeAcknowledgement));
    await tester.pump();
    expect(enabled(tester), isTrue);

    await tester.tap(confirmButton());
    await tester.pump();
    expect(confirmed.single.verdict, RecipientVerdict.firstTime);
  });

  testWidgets(
    'a look-alike cannot be confirmed, and shows the address it imitates',
    (tester) async {
      final confirmed = await pumpCard(
        tester,
        check: assessRecipient(poison, known: known),
      );
      expect(find.text(strings.titleLookalike), findsOneWidget);
      expect(find.text(strings.imitatedLabel), findsOneWidget);
      expect(find.text(strings.highlightHint), findsOneWidget);
      expect(find.text(strings.reasonImitatesKnownRecipient), findsOneWidget);
      expect(confirmButton(), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(AddressText), findsNWidgets(2));
      expect(confirmed, isEmpty);
    },
  );

  testWidgets(
    'with allowOverride, a look-alike needs the explicit override tick',
    (tester) async {
      final confirmed = await pumpCard(
        tester,
        check: assessRecipient(poison, known: known),
        allowOverride: true,
      );
      expect(enabled(tester), isFalse);
      await tester.tap(find.text(strings.overrideAcknowledgement));
      await tester.pump();
      await tester.tap(confirmButton());
      await tester.pump();
      expect(confirmed.single.verdict, RecipientVerdict.lookalike);
    },
  );

  testWidgets('an altered address cannot be confirmed', (tester) async {
    final altered = flipFirstLetter(
      toChecksumAddress(firstTimeAddress.replaceAll('9', 'a')),
    );
    await pumpCard(tester, check: assessRecipient(altered, known: known));
    expect(find.text(strings.titleBadChecksum), findsOneWidget);
    expect(confirmButton(), findsNothing);
  });

  testWidgets('invalid input is shown as typed, with no confirm button', (
    tester,
  ) async {
    await pumpCard(tester, check: assessRecipient('0x12', known: known));
    expect(find.text(strings.titleInvalid), findsOneWidget);
    expect(find.text('0x12'), findsOneWidget);
    expect(confirmButton(), findsNothing);
  });

  testWidgets('a recipient swapped while the card is open clears the tick', (
    tester,
  ) async {
    final confirmed = <ConfirmedRecipient>[];
    var check = assessRecipient(firstTimeAddress, known: known);
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return RecipientConfirmCard(
                  check: check,
                  chainId: 56,
                  onConfirm: confirmed.add,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(strings.firstTimeAcknowledgement));
    await tester.pump();
    expect(enabled(tester), isTrue);

    rebuild(
      () => check = assessRecipient(
        '0x8888888888888888888888888888888888888888',
        known: known,
      ),
    );
    await tester.pump();

    expect(enabled(tester), isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(confirmed, isEmpty);
  });

  testWidgets('cancel calls back', (tester) async {
    var cancelled = 0;
    await pumpCard(
      tester,
      check: assessRecipient(paid, known: known),
      onCancel: () => cancelled++,
    );
    await tester.tap(find.text(strings.cancel));
    expect(cancelled, 1);
  });

  testWidgets('the network line names the chain', (tester) async {
    await pumpCard(
      tester,
      check: assessRecipient(paid, known: known),
      chainId: 97,
    );
    expect(find.text('Network: BNB Smart Chain (chain 97)'), findsOneWidget);
  });

  testWidgets('the address is spelled out for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester, check: assessRecipient(paid, known: known));
    expect(
      find.bySemanticsLabel(RegExp(r'^Address 0x, a 1 b 2, c 3 d 4, ')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('lays out at double text size on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpCard(
      tester,
      check: assessRecipient(poison, known: known),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every text can be replaced', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecipientConfirmCard(
              check: assessRecipient(paid, known: known),
              chainId: 56,
              onConfirm: (_) {},
              strings: AddressGuardStrings(
                titleKnown: 'Bereits bezahlt',
                confirm: 'Bestätigen',
                network: (name, chainId) => 'Netzwerk $chainId',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Bereits bezahlt'), findsOneWidget);
    expect(find.text('Bestätigen'), findsOneWidget);
    expect(find.text('Netzwerk 56'), findsOneWidget);
  });

  group('AddressText', () {
    TextStyle? styleOf(WidgetTester tester, String char, int occurrence) {
      final spans = <TextSpan>[];
      for (final rich in tester.widgetList<Text>(find.byType(Text))) {
        final span = rich.textSpan;
        if (span is TextSpan) {
          span.visitChildren((child) {
            if (child is TextSpan && child.text == char) spans.add(child);
            return true;
          });
        }
      }
      return spans[occurrence].style;
    }

    testWidgets(
      'highlights the characters that differ from the compared address',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AddressText(address: poison, compareWith: paid),
            ),
          ),
        );
        final theme = Theme.of(tester.element(find.byType(AddressText)));
        // 'a1b2' and '5678' match; the middle 'f's all differ.
        expect(
          styleOf(tester, 'f', 0)?.backgroundColor,
          theme.colorScheme.errorContainer,
        );
        expect(styleOf(tester, '1', 0)?.backgroundColor, isNull);
      },
    );

    testWidgets('keeps the casing it was given', (tester) async {
      final checksummed = toChecksumAddress(paid);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AddressText(address: checksummed)),
        ),
      );
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.textSpan?.toPlainText() ?? text.data ?? '')
          .join();
      expect(shown, checksummed);
    });
  });

  testWidgets(
    'titles say what is true: saved, and a look-alike of a list row',
    (tester) async {
      final saved = [KnownRecipient(paid, RecipientProvenance.confirmedByUser)];
      await pumpCard(tester, check: assessRecipient(paid, known: saved));
      expect(find.text(strings.titleSaved), findsOneWidget);
      expect(find.text(strings.titleKnown), findsNothing);

      await pumpCard(
        tester,
        check: assessRecipient(poison, known: const [], batch: [paid]),
      );
      expect(find.text(strings.titleLookalikeBatch), findsOneWidget);
      expect(find.text(strings.titleLookalike), findsNothing);
    },
  );

  testWidgets('an override tick clears when the imitated address changes', (
    tester,
  ) async {
    final other = '0xa1b2000000000000000000000000000000005678';
    var check = assessRecipient(poison, known: known);
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return RecipientConfirmCard(
                  check: check,
                  chainId: 56,
                  allowOverride: true,
                  onConfirm: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(strings.overrideAcknowledgement));
    await tester.pump();
    expect(enabled(tester), isTrue);

    // An equal check rebuilt by the parent keeps the tick.
    rebuild(() => check = assessRecipient(poison, known: known));
    await tester.pump();
    expect(enabled(tester), isTrue);

    rebuild(
      () => check = assessRecipient(
        poison,
        known: [KnownRecipient(other, RecipientProvenance.sentByOwner)],
      ),
    );
    await tester.pump();
    expect(enabled(tester), isFalse);
  });

  testWidgets(
    'more than three imitated addresses are counted, not dropped silently',
    (tester) async {
      final many = [
        for (var i = 0; i < 5; i++)
          KnownRecipient(
            '0xa1b2${'$i' * 32}5678',
            RecipientProvenance.sentByOwner,
          ),
      ];
      await pumpCard(tester, check: assessRecipient(poison, known: many));
      expect(find.byType(AddressText), findsNWidgets(4));
      expect(find.text(strings.moreImitated(2)), findsOneWidget);
    },
  );

  testWidgets(
    'an override tick clears when a list-row match becomes a known one',
    (tester) async {
      var check = assessRecipient(poison, known: const [], batch: [paid]);
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return RecipientConfirmCard(
                    check: check,
                    chainId: 56,
                    allowOverride: true,
                    onConfirm: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(strings.overrideAcknowledgement));
      await tester.pump();
      expect(enabled(tester), isTrue);

      rebuild(() => check = assessRecipient(poison, known: known));
      await tester.pump();
      expect(enabled(tester), isFalse);
    },
  );
}
