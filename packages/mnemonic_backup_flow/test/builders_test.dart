import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

import 'support.dart';

/// No MaterialApp anywhere: the builders must work in an app with its own design system.
Widget plain(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

/// Not in the foreground, with frames still drawn so the builder's state can be read; the screen
/// tests check hidden content the same way.
void leaveForeground(WidgetTester tester) =>
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);

void returnToForeground(WidgetTester tester) =>
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

/// The latest state a builder handed over.
class Latest<T> {
  late T value;
}

void main() {
  final words = MnemonicWords.parse(specVector12);
  const strings = MnemonicBackupStrings();

  group('MnemonicRevealBuilder', () {
    Widget reveal(
      Latest<MnemonicRevealState> latest,
      ScreenProtection protection, {
      VoidCallback? onConfirmed,
      bool allowCopy = false,
      bool obscureUntilShown = true,
    }) => plain(
      MnemonicRevealBuilder(
        words: words,
        screenProtection: protection,
        onConfirmed: onConfirmed ?? () {},
        allowCopy: allowCopy,
        obscureUntilShown: obscureUntilShown,
        builder: (context, state) {
          latest.value = state;
          return const SizedBox();
        },
      ),
    );

    testWidgets(
      'hands the words over only once protected, uncovered and in the foreground',
      (tester) async {
        final protection = RecordingScreenProtection(holdProtect: true);
        final latest = Latest<MnemonicRevealState>();
        await tester.pumpWidget(reveal(latest, protection));
        expect(latest.value.phase, MnemonicSecretPhase.preparing);
        expect(latest.value.words, isNull);
        expect(latest.value.onShow, isNull);
        expect(latest.value.onConfirmed, isNull);

        protection.completeProtect();
        await tester.pumpAndSettle();
        expect(latest.value.phase, MnemonicSecretPhase.visible);
        expect(latest.value.covered, isTrue);
        expect(latest.value.words, isNull);
        expect(latest.value.onConfirmed, isNull);

        latest.value.onShow!();
        await tester.pump();
        expect(latest.value.words, words.words);
        expect(latest.value.covered, isFalse);
        expect(latest.value.onConfirmed, isNotNull);

        leaveForeground(tester);
        await tester.pump();
        expect(latest.value.phase, MnemonicSecretPhase.hidden);
        expect(latest.value.words, isNull);
        expect(latest.value.onConfirmed, isNull);

        returnToForeground(tester);
        await tester.pump();
        expect(latest.value.covered, isTrue, reason: 'covered again');
        expect(latest.value.words, isNull);
      },
    );

    testWidgets(
      'a callback kept from when the words were on screen does nothing once they are covered',
      (tester) async {
        var confirmed = 0;
        final latest = Latest<MnemonicRevealState>();
        await tester.pumpWidget(
          reveal(
            latest,
            RecordingScreenProtection(),
            onConfirmed: () => confirmed++,
          ),
        );
        await tester.pumpAndSettle();
        final show = latest.value.onShow!;
        show();
        await tester.pump();
        final confirm = latest.value.onConfirmed!;

        leaveForeground(tester);
        await tester.pump();
        confirm();
        // Shown while hidden: nothing, and the words stay covered on return.
        show();
        returnToForeground(tester);
        await tester.pump();
        confirm();
        expect(confirmed, 0);
        expect(latest.value.covered, isTrue);

        latest.value.onShow!();
        await tester.pump();
        latest.value.onConfirmed!();
        expect(confirmed, 1);
      },
    );

    testWidgets('a new phrase takes the old one off the clipboard at once', (
      tester,
    ) async {
      final clipboard = FakeClipboard()..install(tester);
      final latest = Latest<MnemonicRevealState>();
      var phrase = words;
      late StateSetter rebuild;
      await tester.pumpWidget(
        plain(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MnemonicRevealBuilder(
                words: phrase,
                screenProtection: RecordingScreenProtection(),
                onConfirmed: () {},
                allowCopy: true,
                builder: (context, state) {
                  latest.value = state;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      latest.value.onShow!();
      await tester.pump();
      expect(await latest.value.onCopy!(), isTrue);
      expect(clipboard.text, words.sentence);

      rebuild(() => phrase = MnemonicWords.generate());
      await tester.pumpAndSettle();
      expect(clipboard.text, isNot(words.sentence));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a callback kept from the old phrase does nothing for a new one shown at once',
      (tester) async {
        final clipboard = FakeClipboard()..install(tester);
        var confirmed = 0;
        final latest = Latest<MnemonicRevealState>();
        var phrase = words;
        late StateSetter rebuild;
        await tester.pumpWidget(
          plain(
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return MnemonicRevealBuilder(
                  words: phrase,
                  screenProtection: RecordingScreenProtection(),
                  onConfirmed: () => confirmed++,
                  allowCopy: true,
                  obscureUntilShown: false,
                  builder: (context, state) {
                    latest.value = state;
                    return const SizedBox();
                  },
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final (oldConfirm, oldCopy) = (
          latest.value.onConfirmed!,
          latest.value.onCopy!,
        );

        final other = MnemonicWords.generate();
        rebuild(() => phrase = other);
        await tester.pump();
        expect(latest.value.words, other.words, reason: 'shown at once');

        oldConfirm();
        expect(confirmed, 0);
        expect(await oldCopy(), isNull);
        expect(clipboard.text, isNull);

        latest.value.onConfirmed!();
        expect(confirmed, 1);
      },
    );

    testWidgets(
      'a copy overtaken by a new phrase says nothing, whether it worked or not',
      (tester) async {
        final clipboard = FakeClipboard()..install(tester);
        final latest = Latest<MnemonicRevealState>();
        var phrase = words;
        late StateSetter rebuild;
        await tester.pumpWidget(
          plain(
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return MnemonicRevealBuilder(
                  words: phrase,
                  screenProtection: RecordingScreenProtection(),
                  onConfirmed: () {},
                  allowCopy: true,
                  obscureUntilShown: false,
                  builder: (context, state) {
                    latest.value = state;
                    return const SizedBox();
                  },
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final fail in [false, true]) {
          final gate = clipboard.gateNextSetData = Completer<void>();
          // Fails after the gate, so the failure lands after the phrase was swapped.
          clipboard.failNextSetDataAfterWrite = fail;
          final copying = latest.value.onCopy!();
          rebuild(() => phrase = MnemonicWords.generate());
          await tester.pump();
          gate.complete();
          expect(await copying, isNull, reason: fail ? 'failed' : 'worked');
          tester.takeException();
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a new phrase is covered again, though the old one was shown', (
      tester,
    ) async {
      final latest = Latest<MnemonicRevealState>();
      var phrase = words;
      late StateSetter rebuild;
      await tester.pumpWidget(
        plain(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MnemonicRevealBuilder(
                words: phrase,
                screenProtection: RecordingScreenProtection(),
                onConfirmed: () {},
                builder: (context, state) {
                  latest.value = state;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      latest.value.onShow!();
      await tester.pump();
      expect(latest.value.words, words.words);

      rebuild(() => phrase = MnemonicWords.generate());
      await tester.pump();
      expect(latest.value.covered, isTrue);
      expect(latest.value.words, isNull);
    });

    testWidgets('obscureUntilShown false hands the words over at once', (
      tester,
    ) async {
      final latest = Latest<MnemonicRevealState>();
      await tester.pumpWidget(
        reveal(latest, RecordingScreenProtection(), obscureUntilShown: false),
      );
      await tester.pumpAndSettle();
      expect(latest.value.words, words.words);
      expect(latest.value.covered, isFalse);
    });

    testWidgets(
      'a copy goes through the timed clipboard and says whether it worked',
      (tester) async {
        final clipboard = FakeClipboard()..install(tester);
        final latest = Latest<MnemonicRevealState>();
        await tester.pumpWidget(
          reveal(latest, RecordingScreenProtection(), allowCopy: true),
        );
        await tester.pumpAndSettle();
        expect(latest.value.allowCopy, isTrue);
        expect(latest.value.onCopy, isNull, reason: 'words still covered');

        latest.value.onShow!();
        await tester.pump();
        expect(await latest.value.onCopy!(), isTrue);
        expect(clipboard.text, words.sentence);

        clipboard.failNextSetData = true;
        expect(await latest.value.onCopy!(), isFalse);
        expect(tester.takeException(), isA<PlatformException>());

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a copy kept from before the words were covered tries nothing and says so',
      (tester) async {
        final clipboard = FakeClipboard()..install(tester);
        final latest = Latest<MnemonicRevealState>();
        await tester.pumpWidget(
          reveal(latest, RecordingScreenProtection(), allowCopy: true),
        );
        await tester.pumpAndSettle();
        latest.value.onShow!();
        await tester.pump();
        final copy = latest.value.onCopy!;

        leaveForeground(tester);
        await tester.pump();
        expect(await copy(), isNull);
        expect(clipboard.text, isNull);
      },
    );

    testWidgets('no copy is offered unless the app allows it', (tester) async {
      final latest = Latest<MnemonicRevealState>();
      await tester.pumpWidget(reveal(latest, RecordingScreenProtection()));
      await tester.pumpAndSettle();
      latest.value.onShow!();
      await tester.pump();
      expect(latest.value.allowCopy, isFalse);
      expect(latest.value.onCopy, isNull);
    });

    testWidgets('a failed protection never hands the words over', (
      tester,
    ) async {
      final latest = Latest<MnemonicRevealState>();
      await tester.pumpWidget(
        reveal(latest, RecordingScreenProtection(failProtect: true)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<StateError>());
      expect(latest.value.phase, MnemonicSecretPhase.protectionFailed);
      expect(latest.value.words, isNull);
      expect(latest.value.onShow, isNull);
    });
  });

  group('MnemonicVerifyBuilder', () {
    const challenges = [
      VerificationChallenge(
        position: 1,
        answer: 'abandon',
        choices: ['zoo', 'abandon', 'ability', 'able'],
      ),
      VerificationChallenge(
        position: 12,
        answer: 'about',
        choices: ['about', 'zebra', 'zone', 'zero'],
      ),
    ];

    Widget verify(
      Latest<MnemonicVerifyState> latest,
      ScreenProtection protection, {
      VoidCallback? onVerified,
      void Function(int position)? onWrongAnswer,
    }) => plain(
      MnemonicVerifyBuilder(
        words: words,
        screenProtection: protection,
        challenges: challenges,
        onVerified: onVerified ?? () {},
        onWrongAnswer: onWrongAnswer,
        builder: (context, state) {
          latest.value = state;
          return const SizedBox();
        },
      ),
    );

    testWidgets(
      'hands the choices over only while visible, and asks them in order',
      (tester) async {
        final protection = RecordingScreenProtection(holdProtect: true);
        final latest = Latest<MnemonicVerifyState>();
        final wrongAt = <int>[];
        var verified = 0;
        await tester.pumpWidget(
          verify(
            latest,
            protection,
            onVerified: () => verified++,
            onWrongAnswer: wrongAt.add,
          ),
        );
        expect(latest.value.phase, MnemonicSecretPhase.preparing);
        expect(latest.value.challenge, isNull);
        expect(latest.value.onAnswer, isNull);
        expect((latest.value.step, latest.value.stepCount), (1, 2));

        protection.completeProtect();
        await tester.pumpAndSettle();
        expect(latest.value.challenge!.position, 1);

        latest.value.onAnswer!('zoo');
        await tester.pump();
        expect(latest.value.wrong, isTrue);
        expect(wrongAt, [1]);

        latest.value.onAnswer!('abandon');
        await tester.pump();
        expect(latest.value.step, 2);
        expect(latest.value.wrong, isFalse);

        latest.value.onAnswer!('about');
        await tester.pump();
        expect(latest.value.verified, isTrue);
        expect(latest.value.onAnswer, isNull);
        expect(verified, 1);
      },
    );

    testWidgets(
      'an answer kept from an earlier challenge, or a second tap on the last, does nothing',
      (tester) async {
        final latest = Latest<MnemonicVerifyState>();
        var verified = 0;
        await tester.pumpWidget(
          verify(
            latest,
            RecordingScreenProtection(),
            onVerified: () => verified++,
          ),
        );
        await tester.pumpAndSettle();
        final firstStep = latest.value.onAnswer!;
        firstStep('abandon');
        await tester.pump();
        // The second challenge's answer, through the first challenge's callback.
        firstStep('about');
        await tester.pump();
        expect(latest.value.step, 2);
        expect(latest.value.verified, isFalse);

        final lastStep = latest.value.onAnswer!;
        lastStep('about');
        lastStep('about');
        await tester.pump();
        expect(verified, 1);
      },
    );

    testWidgets(
      'a right answer after a wrong one on the last challenge is not wrong',
      (tester) async {
        final latest = Latest<MnemonicVerifyState>();
        await tester.pumpWidget(verify(latest, RecordingScreenProtection()));
        await tester.pumpAndSettle();
        latest.value.onAnswer!('abandon');
        await tester.pump();
        latest.value.onAnswer!('zebra');
        await tester.pump();
        expect(latest.value.wrong, isTrue);
        latest.value.onAnswer!('about');
        await tester.pump();
        expect(latest.value.verified, isTrue);
        expect(latest.value.wrong, isFalse);
      },
    );

    testWidgets(
      'only a new phrase starts over, and an answer kept from the old phrase is ignored',
      (tester) async {
        final latest = Latest<MnemonicVerifyState>();
        var phrase = words;
        List<VerificationChallenge>? given = [...challenges];
        late StateSetter rebuild;
        await tester.pumpWidget(
          plain(
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return MnemonicVerifyBuilder(
                  words: phrase,
                  screenProtection: RecordingScreenProtection(),
                  challenges: given,
                  onVerified: () {},
                  builder: (context, state) {
                    latest.value = state;
                    return const SizedBox();
                  },
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        latest.value.onAnswer!('abandon');
        await tester.pump();
        expect(latest.value.step, 2);

        // New questions for the same phrase are not a new phrase: progress is kept, as in 0.3.0,
        // so an app that makes challenges on every rebuild does not send the user back.
        rebuild(() => given = [challenges.last, challenges.first]);
        await tester.pump();
        expect(latest.value.step, 2);
        expect(latest.value.challenge!.position, 12);

        // A new phrase with generated questions: back to the first, and an answer kept from the
        // old phrase's first question answers nothing.
        final oldFirst = latest.value.onAnswer!;
        final spanish = MnemonicWords.generate(language: Language.spanish);
        rebuild(() {
          phrase = spanish;
          given = null;
        });
        await tester.pump();
        expect((latest.value.step, latest.value.stepCount), (1, 3));
        final list = Language.spanish.list.toSet();
        expect(latest.value.challenge!.choices.every(list.contains), isTrue);
        oldFirst(latest.value.challenge!.answer);
        await tester.pump();
        expect(latest.value.step, 1);
      },
    );

    testWidgets('the choices are withheld while the app is in the background', (
      tester,
    ) async {
      final latest = Latest<MnemonicVerifyState>();
      await tester.pumpWidget(verify(latest, RecordingScreenProtection()));
      await tester.pumpAndSettle();
      final answer = latest.value.onAnswer!;

      leaveForeground(tester);
      await tester.pump();
      expect(latest.value.phase, MnemonicSecretPhase.hidden);
      expect(latest.value.challenge, isNull);
      expect(latest.value.onAnswer, isNull);
      answer('abandon');
      await tester.pump();
      expect(latest.value.step, 1, reason: 'answered while hidden: ignored');
    });
  });

  group('MnemonicImportBuilder', () {
    Widget import(
      Latest<MnemonicImportState> latest,
      ScreenProtection protection, {
      void Function(MnemonicWords words)? onImported,
      bool allowPaste = true,
    }) => plain(
      MnemonicImportBuilder(
        screenProtection: protection,
        onImported: onImported ?? (_) {},
        allowPaste: allowPaste,
        builder: (context, state) {
          latest.value = state;
          return const SizedBox();
        },
      ),
    );

    testWidgets(
      'hands the input over only while visible, and keeps its text while hidden',
      (tester) async {
        final protection = RecordingScreenProtection(holdProtect: true);
        final latest = Latest<MnemonicImportState>();
        await tester.pumpWidget(import(latest, protection));
        expect(latest.value.phase, MnemonicSecretPhase.preparing);
        expect(latest.value.controller, isNull);
        expect(latest.value.onSubmit, isNull);
        expect(latest.value.onPaste, isNull);

        protection.completeProtect();
        await tester.pumpAndSettle();
        latest.value.controller!.text = 'abandon';

        leaveForeground(tester);
        await tester.pump();
        expect(latest.value.controller, isNull);

        returnToForeground(tester);
        await tester.pump();
        expect(latest.value.controller!.text, 'abandon');
      },
    );

    testWidgets(
      'a refused phrase sets the error; an edit clears it, a cursor move does not',
      (tester) async {
        final imported = Captured<MnemonicWords>();
        final latest = Latest<MnemonicImportState>();
        await tester.pumpWidget(
          import(
            latest,
            RecordingScreenProtection(),
            onImported: (words) => imported.value = words,
          ),
        );
        await tester.pumpAndSettle();
        final controller = latest.value.controller!;

        controller.text = 'abandon abandon abandon';
        latest.value.onSubmit!();
        await tester.pump();
        expect(latest.value.error!.problem, MnemonicFormatProblem.wordCount);
        expect(
          strings.importError(latest.value.error!),
          strings.importWrongCount(3),
        );

        controller.selection = const TextSelection.collapsed(offset: 2);
        await tester.pump();
        expect(latest.value.error, isNotNull);

        controller.text = specVector12;
        await tester.pump();
        expect(latest.value.error, isNull);

        latest.value.onSubmit!();
        expect(imported.value!.sentence, specVector12);
      },
    );

    testWidgets(
      'the error is withheld with the input: it can name a misspelled word of the phrase',
      (tester) async {
        final latest = Latest<MnemonicImportState>();
        await tester.pumpWidget(import(latest, RecordingScreenProtection()));
        await tester.pumpAndSettle();
        latest.value.controller!.text = specVector12.replaceFirst(
          'about',
          'abuot',
        );
        latest.value.onSubmit!();
        await tester.pump();
        expect(latest.value.error!.word, 'abuot');

        leaveForeground(tester);
        await tester.pump();
        expect(latest.value.error, isNull);

        returnToForeground(tester);
        await tester.pump();
        expect(latest.value.error!.word, 'abuot');
      },
    );

    testWidgets(
      'a paste fills the input and empties the clipboard; a failed read says so',
      (tester) async {
        final clipboard = FakeClipboard()..install(tester);
        final latest = Latest<MnemonicImportState>();
        await tester.pumpWidget(import(latest, RecordingScreenProtection()));
        await tester.pumpAndSettle();

        clipboard.text = specVector12;
        expect(await latest.value.onPaste!(), isTrue);
        await tester.pump();
        expect(latest.value.controller!.text, specVector12);
        expect(clipboard.text, '');

        clipboard.failNextGetData = true;
        expect(await latest.value.onPaste!(), isFalse);
        expect(tester.takeException(), isA<PlatformException>());
      },
    );

    testWidgets('a phrase can be submitted again, for an app that stayed', (
      tester,
    ) async {
      var imported = 0;
      final latest = Latest<MnemonicImportState>();
      await tester.pumpWidget(
        import(
          latest,
          RecordingScreenProtection(),
          onImported: (_) => imported++,
        ),
      );
      await tester.pumpAndSettle();
      latest.value.controller!.text = specVector12;
      latest.value.onSubmit!();
      latest.value.onSubmit!();
      expect(imported, 2);
    });

    testWidgets('no paste is offered unless the app allows it', (tester) async {
      final latest = Latest<MnemonicImportState>();
      await tester.pumpWidget(
        import(latest, RecordingScreenProtection(), allowPaste: false),
      );
      await tester.pumpAndSettle();
      expect(latest.value.allowPaste, isFalse);
      expect(latest.value.onPaste, isNull);
      expect(latest.value.onSubmit, isNotNull);
    });
  });

  group('MnemonicBackupFlowBuilder', () {
    testWidgets('holds the protection once across both steps', (tester) async {
      final protection = RecordingScreenProtection(holdProtect: true);
      final waiting = <MnemonicSecretPhase>[];
      final reveal = Latest<MnemonicRevealState>();
      final verify = Latest<MnemonicVerifyState>();
      var verified = 0;
      await tester.pumpWidget(
        plain(
          MnemonicBackupFlowBuilder(
            words: words,
            screenProtection: protection,
            onVerified: () => verified++,
            waitingBuilder: (context, phase) {
              waiting.add(phase);
              return const SizedBox();
            },
            revealBuilder: (context, state) {
              reveal.value = state;
              return const SizedBox();
            },
            verifyBuilder: (context, state) {
              verify.value = state;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(waiting.last, MnemonicSecretPhase.preparing);

      protection.completeProtect();
      await tester.pumpAndSettle();
      reveal.value.onShow!();
      await tester.pump();
      reveal.value.onConfirmed!();
      await tester.pump();

      for (var step = 0; step < 3; step++) {
        verify.value.onAnswer!(verify.value.challenge!.answer);
        await tester.pump();
      }
      expect(verified, 1);
      expect(protection.events, ['protect'], reason: 'held once, not per step');

      await tester.pumpWidget(plain(const SizedBox()));
      await tester.pumpAndSettle();
      expect(protection.events, ['protect', 'release']);
    });

    testWidgets('the verify step draws its decoys from the phrase language', (
      tester,
    ) async {
      // No language given: the phrase remembers its own.
      final spanish = MnemonicWords.generate(language: Language.spanish);
      expect(spanish.language, Language.spanish);
      final reveal = Latest<MnemonicRevealState>();
      final verify = Latest<MnemonicVerifyState>();
      await tester.pumpWidget(
        plain(
          MnemonicBackupFlowBuilder(
            words: spanish,
            screenProtection: RecordingScreenProtection(),
            onVerified: () {},
            waitingBuilder: (context, phase) => const SizedBox(),
            revealBuilder: (context, state) {
              reveal.value = state;
              return const SizedBox();
            },
            verifyBuilder: (context, state) {
              verify.value = state;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      reveal.value.onShow!();
      await tester.pump();
      reveal.value.onConfirmed!();
      await tester.pump();

      final list = Language.spanish.list.toSet();
      expect(verify.value.challenge!.choices.every(list.contains), isTrue);
    });

    testWidgets('a new phrase starts the flow over from the reveal step', (
      tester,
    ) async {
      final reveal = Latest<MnemonicRevealState>();
      final verify = Latest<MnemonicVerifyState>();
      var phrase = words;
      var step = '';
      late StateSetter rebuild;
      await tester.pumpWidget(
        plain(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MnemonicBackupFlowBuilder(
                words: phrase,
                screenProtection: RecordingScreenProtection(),
                onVerified: () {},
                waitingBuilder: (context, phase) => const SizedBox(),
                revealBuilder: (context, state) {
                  step = 'reveal';
                  reveal.value = state;
                  return const SizedBox();
                },
                verifyBuilder: (context, state) {
                  step = 'verify';
                  verify.value = state;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      reveal.value.onShow!();
      await tester.pump();
      reveal.value.onConfirmed!();
      await tester.pump();
      expect(step, 'verify');

      final other = MnemonicWords.generate();
      rebuild(() => phrase = other);
      await tester.pump();
      expect(step, 'reveal');
      expect(reveal.value.covered, isTrue);
    });

    testWidgets(
      'an unusable challenge count is refused before anything is shown or protected',
      (tester) async {
        final protection = RecordingScreenProtection();
        await tester.pumpWidget(
          plain(
            MnemonicBackupFlowBuilder(
              words: words,
              screenProtection: protection,
              challengeCount: 13,
              onVerified: () {},
              waitingBuilder: (context, phase) => const SizedBox(),
              revealBuilder: (context, state) => const SizedBox(),
              verifyBuilder: (context, state) => const SizedBox(),
            ),
          ),
        );
        expect(tester.takeException(), isArgumentError);
        expect(protection.events, isEmpty);
      },
    );

    testWidgets('a failed protection is drawn by the waiting builder', (
      tester,
    ) async {
      final waiting = <MnemonicSecretPhase>[];
      await tester.pumpWidget(
        plain(
          MnemonicBackupFlowBuilder(
            words: words,
            screenProtection: RecordingScreenProtection(failProtect: true),
            onVerified: () {},
            waitingBuilder: (context, phase) {
              waiting.add(phase);
              return const SizedBox();
            },
            revealBuilder: (context, state) => const SizedBox(),
            verifyBuilder: (context, state) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<StateError>());
      expect(waiting.last, MnemonicSecretPhase.protectionFailed);
    });
  });

  test(
    'an accented word typed in another Unicode form is held as the list spells it',
    () {
      // A phrase with at least one accented word, so the test always has something to compare.
      bool accented(MnemonicWords words) =>
          words.words.any((word) => word.contains(RegExp('[\u0301\u0303]')));
      var spanish = MnemonicWords.generate(language: Language.spanish);
      while (!accented(spanish)) {
        spanish = MnemonicWords.generate(language: Language.spanish);
      }
      // Re-typed the way an iOS keyboard composes accents (NFC), against the list's NFKD spelling.
      String composed(String word) => word
          .replaceAll('a\u0301', '\u00e1')
          .replaceAll('e\u0301', '\u00e9')
          .replaceAll('i\u0301', '\u00ed')
          .replaceAll('o\u0301', '\u00f3')
          .replaceAll('u\u0301', '\u00fa')
          .replaceAll('n\u0303', '\u00f1');
      final typed = spanish.words.map(composed).toList();
      expect(
        typed,
        isNot(spanish.words),
        reason: 'really typed in another form',
      );
      final parsed = MnemonicWords.fromList(typed, language: Language.spanish);
      expect(parsed.words, spanish.words);
      final list = Language.spanish.list.toSet();
      expect(parsed.words.every(list.contains), isTrue);
    },
  );

  test('a phrase remembers the word list it was made or checked with', () {
    expect(MnemonicWords.parse(specVector12).language, Language.english);
    expect(
      MnemonicWords.generate(language: Language.french).language,
      Language.french,
    );
    final spanish = MnemonicWords.generate(language: Language.spanish);
    expect(
      MnemonicWords.fromList(
        spanish.words,
        language: Language.spanish,
      ).language,
      Language.spanish,
    );
  });

  test('a phrase made in another isolate keeps its language', () async {
    final spanish = await Isolate.run(
      () => MnemonicWords.generate(language: Language.spanish),
    );
    expect(spanish.language, Language.spanish);
  });

  testWidgets(
    'a phrase class of the app\'s own still works, made afresh on every build',
    (tester) async {
      expect(_OwnWords(words.words).language, Language.english);
      final latest = Latest<MnemonicRevealState>();
      late StateSetter rebuild;
      await tester.pumpWidget(
        plain(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MnemonicRevealBuilder(
                // A new instance every build, with no == of its own: not a new phrase.
                words: _OwnWords(words.words),
                screenProtection: RecordingScreenProtection(),
                onConfirmed: () {},
                builder: (context, state) {
                  latest.value = state;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      latest.value.onShow!();
      await tester.pump();

      rebuild(() {});
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(latest.value.words, words.words, reason: 'still shown');
    },
  );

  test('each phase but visible has its text, and each import problem too', () {
    expect(
      strings.placeholder(MnemonicSecretPhase.preparing),
      strings.revealPreparing,
    );
    expect(
      strings.placeholder(MnemonicSecretPhase.protectionFailed),
      strings.protectionFailed,
    );
    expect(
      strings.placeholder(MnemonicSecretPhase.hidden),
      strings.revealHidden,
    );
    expect(strings.placeholder(MnemonicSecretPhase.visible), isNull);
    expect(
      strings.importError(const MnemonicFormatException.unknownWord('abandom')),
      strings.importUnknownWord('abandom'),
    );
    expect(
      strings.importError(const MnemonicFormatException.checksum()),
      strings.importInvalid,
    );
  });
}

/// A phrase class of an app's own, as a test double would be: it implements MnemonicWords.
class _OwnWords implements MnemonicWords {
  _OwnWords(this.words);

  @override
  final List<String> words;

  @override
  int get length => words.length;

  @override
  String get sentence => words.join(' ');
}
