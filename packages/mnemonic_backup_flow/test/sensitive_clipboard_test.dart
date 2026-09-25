import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

import 'support.dart';

void main() {
  const thirtySeconds = Duration(seconds: 30);
  const fiveSeconds = Duration(seconds: 5);

  testWidgets('clears the copied text after the delay', (tester) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    await sensitive.copy('secret words');
    expect(clipboard.text, 'secret words');

    await tester.pump(const Duration(seconds: 29));
    expect(clipboard.text, 'secret words');

    await tester.pump(const Duration(seconds: 2));
    expect(clipboard.text, '');
  });

  testWidgets('leaves alone text the user copied afterwards', (tester) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    await sensitive.copy('secret words');
    clipboard.text = 'something else';

    await tester.pump(const Duration(seconds: 31));
    expect(clipboard.text, 'something else');
  });

  testWidgets(
    'in the foreground, no text on the clipboard means the copy is gone',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      await sensitive.copy('secret words');
      clipboard.text = null;

      await tester.pump(const Duration(seconds: 31));
      expect(
        clipboard.text,
        isNull,
        reason: 'a wipe would have written an empty string',
      );
      await tester.pump(const Duration(seconds: 60));
      expect(clipboard.text, isNull);
    },
  );

  testWidgets('clear removes the text at once and dispose does the same', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard();

    await sensitive.copy('secret words');
    await sensitive.clear();
    expect(clipboard.text, '');

    await sensitive.copy('again');
    sensitive.dispose();
    await tester.pump();
    expect(clipboard.text, '');
  });

  testWidgets(
    'a clear requested while the copy is still writing removes the text once written',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final gate = clipboard.gateNextSetData = Completer<void>();
      final sensitive = SensitiveClipboard();

      final copied = sensitive.copy('secret words');
      final cleared = sensitive.clear();
      await tester.pump();
      expect(clipboard.text, isNull);

      gate.complete();
      await copied;
      await cleared;
      expect(clipboard.text, '');
    },
  );

  testWidgets(
    'a write that never answers fails the copy without blocking the removal',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      clipboard.gateNextSetData = Completer<void>();
      final sensitive = SensitiveClipboard();

      final timedOut = expectLater(
        sensitive.copy('secret words'),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 11));
      await timedOut;

      clipboard.text = 'the user\'s own text';
      await sensitive.clear();
      expect(clipboard.text, 'the user\'s own text');
    },
  );

  testWidgets('a write that lands after its timeout is removed at once', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final gate = clipboard.gateNextSetData = Completer<void>();
    final sensitive = SensitiveClipboard();

    final timedOut = expectLater(
      sensitive.copy('secret words'),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 11));
    await timedOut;
    sensitive.dispose();
    await tester.pump();

    gate.complete();
    await tester.pump();
    expect(clipboard.text, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('refuses a copy after dispose', (tester) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard();

    sensitive.dispose();
    await expectLater(sensitive.copy('secret words'), throwsStateError);
    expect(clipboard.text, isNull);
  });

  testWidgets(
    'the first timer firing after a second copy leaves the second copy alone',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      await sensitive.copy('first');
      await tester.pump(const Duration(seconds: 29, milliseconds: 999));
      await sensitive.copy('second');
      await tester.pump(const Duration(milliseconds: 5));

      expect(clipboard.text, 'second');
      await tester.pump(const Duration(seconds: 29));
      expect(clipboard.text, 'second');
      await tester.pump(const Duration(seconds: 2));
      expect(clipboard.text, '');
    },
  );

  testWidgets('a failed write keeps the earlier copy on its original timer', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    await sensitive.copy('first');
    await tester.pump(const Duration(seconds: 10));
    clipboard.failNextSetData = true;
    await expectLater(
      sensitive.copy('second'),
      throwsA(isA<PlatformException>()),
    );
    expect(clipboard.text, 'first');

    await tester.pump(const Duration(seconds: 21));
    expect(clipboard.text, '');
  });

  testWidgets(
    'a write that landed but reported an error is still looked for and removed',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      clipboard.failNextSetDataAfterWrite = true;
      await expectLater(
        sensitive.copy('secret words'),
        throwsA(isA<PlatformException>()),
      );
      expect(clipboard.text, 'secret words');

      await tester.pump(const Duration(seconds: 31));
      expect(clipboard.text, '');
    },
  );

  testWidgets('a copy whose write failed is never wiped without looking', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    clipboard.failNextSetData = true;
    await expectLater(
      sensitive.copy('secret words'),
      throwsA(isA<PlatformException>()),
    );
    sendToBackground(tester);
    clipboard.text = 'the user\'s own text';
    for (var look = 1; look <= 3; look++) {
      clipboard.hideNextLook = true;
      await tester.pump(look == 1 ? const Duration(seconds: 31) : fiveSeconds);
    }

    expect(clipboard.text, 'the user\'s own text');
    await tester.pump(const Duration(seconds: 60));
    expect(clipboard.text, 'the user\'s own text');
  });

  testWidgets(
    'in the background, a hidden clipboard is looked at three times and then wiped',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      await sensitive.copy('secret words');
      sendToBackground(tester);
      clipboard.text = 'a later copy the looks cannot see';
      for (var look = 1; look <= 2; look++) {
        clipboard.hideNextLook = true;
        await tester.pump(
          look == 1 ? const Duration(seconds: 31) : fiveSeconds,
        );
        expect(clipboard.text, 'a later copy the looks cannot see');
      }
      clipboard.hideNextLook = true;
      await tester.pump(fiveSeconds);

      expect(clipboard.text, '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a look answered after the app came back is not taken as final', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    await sensitive.copy('secret words');
    sendToBackground(tester);
    clipboard.hideNextLook = true;
    final gate = clipboard.gateNextHasStrings = Completer<void>();
    await tester.pump(const Duration(seconds: 31));

    bringToForeground(tester);
    gate.complete();
    await tester.pump();
    expect(
      clipboard.text,
      'secret words',
      reason: 'the hidden answer must not read as gone',
    );

    await tester.pump(fiveSeconds);
    expect(clipboard.text, '');
  });

  testWidgets(
    'a look that fails is reported and tried again, and the third failure wipes',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      await sensitive.copy('secret words');
      for (var look = 1; look <= 2; look++) {
        clipboard.failNextGetData = true;
        await tester.pump(
          look == 1 ? const Duration(seconds: 31) : fiveSeconds,
        );
        expect(clipboard.text, 'secret words');
        expect(tester.takeException(), isA<PlatformException>());
      }
      clipboard.failNextGetData = true;
      await tester.pump(fiveSeconds);

      expect(clipboard.text, '');
      expect(
        tester.takeException(),
        isA<PlatformException>(),
        reason: 'the third failure is reported too',
      );
    },
  );

  testWidgets('each copied text gets its own three looks', (tester) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    sendToBackground(tester);
    await sensitive.copy('first');
    clipboard.hideNextLook = true;
    await tester.pump(const Duration(seconds: 31));
    clipboard.hideNextLook = true;
    await tester.pump(fiveSeconds);
    await sensitive.copy('second');
    await tester.pump(fiveSeconds);
    expect(
      clipboard.text,
      'second',
      reason: "the first text's third look saw another of ours",
    );

    clipboard.text = 'a photo';
    for (var look = 1; look <= 2; look++) {
      clipboard.hideNextLook = true;
      await tester.pump(look == 1 ? const Duration(seconds: 25) : fiveSeconds);
      expect(clipboard.text, 'a photo');
    }
    clipboard.hideNextLook = true;
    await tester.pump(fiveSeconds);
    expect(clipboard.text, '');
  });

  testWidgets(
    'text the platform holds but will not show is not ours and is left alone',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      await sensitive.copy('secret words');
      clipboard.text = 'a password from another app';
      clipboard.refuseNextGetData = true;
      await tester.pump(const Duration(seconds: 31));
      expect(clipboard.text, 'a password from another app');

      await tester.pump(const Duration(seconds: 60));
      expect(clipboard.text, 'a password from another app');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a read the user does not answer is taken as text that is not ours',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard();

      await sensitive.copy('secret words');
      clipboard.text = 'a bank account from another app';
      clipboard.gateNextGetData = Completer<void>();
      sensitive.dispose();
      await tester.pump(const Duration(seconds: 61));

      expect(clipboard.text, 'a bank account from another app');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a wipe that fails on the timer path is tried again', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    await sensitive.copy('secret words');
    clipboard.failNextSetData = true;
    await tester.pump(const Duration(seconds: 31));
    expect(clipboard.text, 'secret words');
    expect(tester.takeException(), isA<PlatformException>());

    await tester.pump(fiveSeconds);
    expect(clipboard.text, '');
  });

  testWidgets(
    'after three failed wipes the text is given up on, each failure reported',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      await sensitive.copy('secret words');
      for (var wipe = 1; wipe <= 3; wipe++) {
        clipboard.failNextSetData = true;
        await tester.pump(
          wipe == 1 ? const Duration(seconds: 31) : fiveSeconds,
        );
        expect(tester.takeException(), isA<PlatformException>());
      }

      await tester.pump(const Duration(seconds: 60));
      expect(clipboard.text, 'secret words');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('after a wipe every remembered text is forgotten', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    await sensitive.copy('first');
    await tester.pump(const Duration(seconds: 10));
    await sensitive.copy('second');
    await tester.pump(const Duration(seconds: 21));
    expect(
      clipboard.text,
      'second',
      reason: "the first text's timer forgets it and leaves the second",
    );

    await sensitive.clear();
    expect(clipboard.text, '');

    sendToBackground(tester);
    clipboard.text = 'a later copy';
    await tester.pump(const Duration(seconds: 60));
    expect(
      clipboard.text,
      'a later copy',
      reason: 'no timer is left to wipe it',
    );
  });

  testWidgets(
    'clear and dispose wipe without looking when the clipboard is hidden',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard();

      sendToBackground(tester);
      await sensitive.copy('secret words');
      clipboard.hideNextLook = true;
      await sensitive.clear();
      expect(clipboard.text, '');

      await sensitive.copy('again');
      clipboard.hideNextLook = true;
      sensitive.dispose();
      await tester.pump();
      expect(clipboard.text, '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'in the foreground, clear and dispose leave a clipboard without text alone',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard();

      await sensitive.copy('secret words');
      clipboard.text = null;
      await sensitive.clear();
      expect(clipboard.text, isNull);

      await sensitive.copy('again');
      clipboard.text = null;
      sensitive.dispose();
      await tester.pump();
      expect(clipboard.text, isNull);
    },
  );

  testWidgets(
    'a dispose whose wipe fails is reported and tried again, once for all texts',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard();

      await sensitive.copy('first');
      await sensitive.copy('second');
      clipboard.failNextSetData = true;
      sensitive.dispose();
      await tester.pump();
      expect(clipboard.text, 'second');
      expect(tester.takeException(), isA<PlatformException>());

      clipboard.failNextSetData = true;
      await tester.pump(fiveSeconds);
      expect(tester.takeException(), isA<PlatformException>());
      expect(
        tester.takeException(),
        isNull,
        reason: 'one retry, not one per text',
      );

      await tester.pump(fiveSeconds);
      expect(clipboard.text, '');
    },
  );

  testWidgets('a clear that fails throws to its caller and is tried again', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard();

    await sensitive.copy('secret words');
    clipboard.failNextSetData = true;
    await expectLater(sensitive.clear(), throwsA(isA<PlatformException>()));
    expect(clipboard.text, 'secret words');

    await tester.pump(fiveSeconds);
    expect(clipboard.text, '');
  });

  testWidgets(
    'a copy queued before dispose is placed and then removed, without an error',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final gate = clipboard.gateNextSetData = Completer<void>();
      final sensitive = SensitiveClipboard();

      final first = sensitive.copy('first');
      final second = sensitive.copy('second');
      sensitive.dispose();
      gate.complete();
      await first;
      await second;
      await tester.pump();

      expect(clipboard.text, '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late landing after a newer successful copy of the same text leaves it alone',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final gate = clipboard.gateNextSetData = Completer<void>();
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      final timedOut = expectLater(
        sensitive.copy('secret words'),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(seconds: 11));
      await timedOut;
      await sensitive.copy('secret words');

      gate.complete();
      await tester.pump();
      expect(clipboard.text, 'secret words');

      await tester.pump(const Duration(seconds: 31));
      expect(clipboard.text, '');
    },
  );

  testWidgets('the clearing timer starts when the write has landed', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final gate = clipboard.gateNextSetData = Completer<void>();
    final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

    final copied = sensitive.copy('secret words');
    await tester.pump(const Duration(seconds: 5));
    gate.complete();
    await copied;

    await tester.pump(const Duration(seconds: 29));
    expect(clipboard.text, 'secret words');
    await tester.pump(const Duration(seconds: 2));
    expect(clipboard.text, '');
  });

  testWidgets(
    'outside Android, no text on the clipboard is final even in the background',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard(clearAfter: thirtySeconds);

      await sensitive.copy('secret words');
      sendToBackground(tester);
      clipboard.text = null;
      await tester.pump(const Duration(seconds: 31));

      expect(clipboard.text, isNull);
      await tester.pump(const Duration(seconds: 60));
      expect(clipboard.text, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a look that fails on dispose is retried rather than wiped without looking',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      final sensitive = SensitiveClipboard();

      await sensitive.copy('secret words');
      clipboard.text = 'a bank account from another app';
      clipboard.failNextGetData = true;
      sensitive.dispose();
      await tester.pump();
      expect(clipboard.text, 'a bank account from another app');
      expect(tester.takeException(), isA<PlatformException>());

      await tester.pump(fiveSeconds);
      expect(
        clipboard.text,
        'a bank account from another app',
        reason: 'the retry saw it is not ours',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a copy nobody awaits still surfaces its failure to the zone', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    final sensitive = SensitiveClipboard();
    final uncaught = <Object>[];

    clipboard.failNextSetData = true;
    runZonedGuarded(
      () => unawaited(sensitive.copy('secret words')),
      (error, _) => uncaught.add(error),
    );
    await tester.pump();

    expect(uncaught, [isA<PlatformException>()]);

    sensitive.dispose();
    await tester.pump();
  });
}
