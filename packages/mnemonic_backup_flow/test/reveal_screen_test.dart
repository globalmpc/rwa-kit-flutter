import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

import 'support.dart';

const failedText =
    'Screen protection could not be enabled. Go back and try again.';

void main() {
  final words = MnemonicWords.parse(specVector12);

  Widget reveal(
    ScreenProtection protection, {
    Key? key,
    Duration? timeout = const Duration(seconds: 15),
  }) => MnemonicRevealScreen(
    key: key,
    words: words,
    screenProtection: protection,
    onConfirmed: () {},
    protectionTimeout: timeout,
  );

  testWidgets(
    'shows nothing until the screen protection is active, then the numbered words',
    (tester) async {
      final protection = RecordingScreenProtection(holdProtect: true);
      await tester.pumpWidget(wrap(reveal(protection)));

      expect(protection.events, ['protect']);
      expect(find.text('Preparing a protected screen.'), findsOneWidget);
      expect(find.textContaining('abandon'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      protection.completeProtect();
      await tester.pumpAndSettle();

      expect(find.text('1. abandon'), findsOneWidget);
      expect(find.text('12. about'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('hides the words while the app is not in the foreground', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(reveal(RecordingScreenProtection())));
    await tester.pumpAndSettle();
    expect(find.text('1. abandon'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('1. abandon'), findsNothing);
    expect(
      find.text('Hidden while the app is not in the foreground.'),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('1. abandon'), findsOneWidget);
  });

  testWidgets('releases the protection when the screen goes away', (
    tester,
  ) async {
    final protection = RecordingScreenProtection();
    await tester.pumpWidget(wrap(reveal(protection)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(const SizedBox()));
    await tester.pumpAndSettle();

    expect(protection.events, ['protect', 'release']);
  });

  testWidgets(
    'releases only after a protect that was still running has settled',
    (tester) async {
      final protection = RecordingScreenProtection(holdProtect: true);
      await tester.pumpWidget(wrap(reveal(protection)));
      await tester.pump();

      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pumpAndSettle();
      expect(protection.events, ['protect']);

      protection.completeProtect();
      await tester.pumpAndSettle();
      expect(protection.events, ['protect', 'release']);
    },
  );

  testWidgets(
    'a protect that throws is reported, shows the failure text, never shows the words, and is still released',
    (tester) async {
      for (final synchronously in [false, true]) {
        final protection = RecordingScreenProtection(
          failProtect: true,
          throwSynchronously: synchronously,
        );
        await tester.pumpWidget(wrap(reveal(protection)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isA<StateError>());
        expect(find.text(failedText), findsOneWidget);
        expect(find.textContaining('abandon'), findsNothing);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );

        await tester.pumpWidget(wrap(const SizedBox()));
        await tester.pumpAndSettle();
        expect(protection.events, ['protect', 'release']);
      }
    },
  );

  testWidgets(
    'a protect that never answers times out into the failure state, is released protectionTimeout after the screen goes away, and is released again when it answers',
    (tester) async {
      final protection = RecordingScreenProtection(holdProtect: true);
      await tester.pumpWidget(
        wrap(reveal(protection, timeout: const Duration(seconds: 2))),
      );
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isA<TimeoutException>());
      expect(find.text(failedText), findsOneWidget);

      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pump(const Duration(seconds: 1));
      expect(protection.events, ['protect']);
      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      expect(protection.events, ['protect', 'release']);

      protection.completeProtect();
      await tester.pumpAndSettle();
      expect(protection.events, ['protect', 'release', 'release']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a timeout after the screen has gone is not reported', (
    tester,
  ) async {
    final protection = RecordingScreenProtection(holdProtect: true);
    await tester.pumpWidget(
      wrap(reveal(protection, timeout: const Duration(seconds: 2))),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(wrap(const SizedBox()));
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    expect(protection.events, ['protect', 'release']);
  });

  testWidgets('a screen after a failed protect tries again on its own', (
    tester,
  ) async {
    final protection = RecordingScreenProtection(failProtect: true);
    await tester.pumpWidget(wrap(reveal(protection, key: const Key('a'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(protection.events, ['protect', 'release']);

    final working = RecordingScreenProtection();
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(child: reveal(protection, key: const Key('a'))),
            Expanded(child: reveal(working, key: const Key('b'))),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(protection.events, ['protect', 'release', 'protect', 'release']);
    expect(working.events, ['protect']);
    expect(find.text('1. abandon'), findsOneWidget);
  });

  testWidgets(
    'a protect that throws while its own release hangs settles at once and is released once',
    (tester) async {
      final protection = RecordingScreenProtection(
        failProtect: true,
        holdRelease: true,
      );
      await tester.pumpWidget(
        wrap(reveal(protection, timeout: const Duration(seconds: 2))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<StateError>());
      expect(find.text(failedText), findsOneWidget);

      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pump(const Duration(seconds: 3));
      expect(protection.events, ['protect', 'release']);
      expect(
        tester.takeException(),
        isNull,
        reason: 'no timeout is reported for a protect that failed',
      );

      protection.completeRelease();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a release that fails is reported, not lost', (tester) async {
    final protection = RecordingScreenProtection(failRelease: true);
    await tester.pumpWidget(wrap(reveal(protection)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(const SizedBox()));
    await tester.pumpAndSettle();

    expect(protection.events, ['protect', 'release']);
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('a copy that fails tells the user and is reported', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    await tester.pumpWidget(
      wrap(
        MnemonicRevealScreen(
          words: words,
          screenProtection: RecordingScreenProtection(),
          onConfirmed: () {},
          allowCopy: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    clipboard.failNextSetData = true;
    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(
      find.text('Could not copy. Write the words down instead.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isA<PlatformException>());
    expect(clipboard.text, isNull);
  });

  testWidgets('each screen protects and releases on its own', (tester) async {
    final protection = RecordingScreenProtection();
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(child: reveal(protection, key: const Key('a'))),
            Expanded(child: reveal(protection, key: const Key('b'))),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(protection.events, ['protect', 'protect']);
    expect(find.text('1. abandon'), findsNWidgets(2));

    await tester.pumpWidget(wrap(const SizedBox()));
    await tester.pumpAndSettle();
    expect(protection.events, ['protect', 'protect', 'release', 'release']);
  });

  testWidgets(
    'a protect that answers after the timeout makes the screen active after all',
    (tester) async {
      final protection = RecordingScreenProtection(holdProtect: true);
      await tester.pumpWidget(
        wrap(reveal(protection, timeout: const Duration(seconds: 2))),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNotNull);
      expect(find.text(failedText), findsOneWidget);

      protection.completeProtect();
      await tester.pumpAndSettle();
      expect(find.text('1. abandon'), findsOneWidget);

      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pumpAndSettle();
      expect(protection.events, ['protect', 'release']);
    },
  );

  testWidgets("a plugin's own timeout is reported once, not twice", (
    tester,
  ) async {
    final protection = ScreenProtection.callbacks(
      protect: () => Future<void>.error(TimeoutException('plugin gave up')),
      release: () async {},
    );
    await tester.pumpWidget(wrap(reveal(protection)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<TimeoutException>());
    expect(tester.takeException(), isNull);
    expect(find.text(failedText), findsOneWidget);
  });

  testWidgets('confirms through the button', (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      wrap(
        MnemonicRevealScreen(
          words: words,
          screenProtection: RecordingScreenProtection(),
          onConfirmed: () => confirmed++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('I wrote it down'));

    expect(confirmed, 1);
  });

  testWidgets(
    'offers no copy button unless allowed, and copies with timed clearing when it is',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      await tester.pumpWidget(
        wrap(
          MnemonicRevealScreen(
            words: words,
            screenProtection: RecordingScreenProtection(),
            onConfirmed: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);

      await tester.pumpWidget(
        wrap(
          MnemonicRevealScreen(
            words: words,
            screenProtection: RecordingScreenProtection(),
            onConfirmed: () {},
            allowCopy: true,
            clipboardClearAfter: const Duration(seconds: 5),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(clipboard.text, specVector12);
      expect(
        find.text('Copied. The clipboard clears in 5 seconds.'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 6));
      expect(clipboard.text, '');
    },
  );

  testWidgets('uses the strings it is given', (tester) async {
    const strings = MnemonicBackupStrings(
      revealTitle: 'Deine Wiederherstellungsphrase',
      revealConfirm: 'Aufgeschrieben',
    );
    await tester.pumpWidget(
      wrap(
        MnemonicRevealScreen(
          words: words,
          screenProtection: RecordingScreenProtection(),
          onConfirmed: () {},
          strings: strings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Deine Wiederherstellungsphrase'), findsOneWidget);
    expect(find.text('Aufgeschrieben'), findsOneWidget);
  });
}
