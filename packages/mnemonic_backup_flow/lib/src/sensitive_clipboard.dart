import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'clipboard_calls.dart';
import 'lifecycle.dart';
import 'report.dart';
import 'serial_queue.dart';

/// How many looks may find the clipboard hidden before a copy is wiped without looking.
const _looksBeforeWipe = 3;

/// How many wipes may fail before a copy is given up on.
const _wipeFailuresBeforeGivingUp = 3;

/// How soon a look that found the clipboard hidden, or a failed look or wipe, is tried again.
const _retryAfter = Duration(seconds: 5);

/// Copies text to the clipboard and removes it again after [clearAfter], if it is still there.
///
/// Every text this object may have put on the clipboard is remembered, with its own timer, until
/// a look shows it is gone or it has been wiped. Only such texts are removed, so text the user
/// copied later is left alone. The timer starts when the write has landed.
///
/// A look first asks whether the clipboard holds any text at all, which is answered without a
/// prompt on every platform. That answer is final, except on Android with the app out of the
/// foreground, where the clipboard is hidden from the app. A timer then looks again after
/// [_retryAfter], and after [_looksBeforeWipe] hidden looks wipes the clipboard without looking; a
/// phrase left behind by an app that never comes back costs more than a copy the user made in
/// between. Only text this object knows it placed is wiped without looking; a copy whose write
/// failed is looked for, never wiped blind. Text the platform holds but will not show (iOS asks
/// the user before another app's text is read; they may decline or not answer) was not written
/// by this app and is left alone.
///
/// [clear] and [dispose] remove the text at once, wiping without looking when the clipboard is
/// hidden. A look or a wipe that fails is retried, and the text is given up on after
/// [_wipeFailuresBeforeGivingUp] failed wipes; every failure on a path nobody awaits is reported.
///
/// Operations run one after another, so a [clear] requested while a [copy] is still writing waits
/// for that write and then removes it. Each platform call is bounded, so a call that never
/// answers cannot block the ones behind it; a write that lands after its bound is removed at
/// once, since the user was told it failed.
class SensitiveClipboard {
  SensitiveClipboard({this.clearAfter = const Duration(seconds: 30)});

  final Duration clearAfter;

  final _queue = SerialQueue();
  final _entries = <String, _Entry>{};
  final _all = _Attempts();
  bool _disposed = false;

  /// Fails with a [StateError] after [dispose].
  Future<void> copy(String text) async {
    if (_disposed) {
      throw StateError('SensitiveClipboard.copy after dispose');
    }
    await _queue.run(() async {
      // Remembered before the write: a write whose outcome is unknown is still ours to look for.
      final entry = _entries.putIfAbsent(text, _Entry.new)..startCopy();
      final generation = entry.generation;
      try {
        await writeClipboardText(
          text,
          onLate: () => _landedLate(text, generation),
        );
      } catch (_) {
        _arm(text, entry, clearAfter);
        rethrow;
      }
      entry.placed = true;
      _arm(text, entry, clearAfter);
    });
  }

  /// Removes every text this object put on the clipboard, now. Throws when the platform refused,
  /// after arming a retry.
  Future<void> clear() => _queue.run(() => _remove(null));

  /// Removes the text as [clear] does, reporting a failure, and refuses further copies.
  void dispose() {
    _disposed = true;
    unawaited(_removeReporting(null, 'on dispose'));
  }

  /// A write that had timed out has landed: the text is on the clipboard now, and the user was
  /// told the copy failed, so it comes off at once. Unless the same text was copied again since
  /// and the user was told that one succeeded.
  void _landedLate(String text, int generation) {
    unawaited(
      _queue
          .run(() {
            final entry = _entries[text];
            if (entry != null && entry.generation != generation) {
              entry.placed = true;
              return Future<void>.value();
            }
            (entry ?? (_entries[text] = _Entry())).placed = true;
            return _remove(_disposed ? null : text);
          })
          .catchError((Object error, StackTrace stack) {
            reportBackupFlowError(
              error,
              stack,
              'while clearing the clipboard after a late write',
            );
          }),
    );
  }

  Future<void> _removeReporting(String? only, String when) => _queue
      .run(() => _remove(only))
      .catchError((Object error, StackTrace stack) {
        reportBackupFlowError(
          error,
          stack,
          'while clearing the clipboard $when',
        );
      });

  /// Removes [only] (its clearing timer) or every remembered text (clear, dispose).
  Future<void> _remove(String? only) async {
    final entry = only == null ? null : _entries[only];
    if (only == null ? _entries.isEmpty : entry == null) {
      return;
    }
    switch (await _decide(only, entry ?? _all)) {
      case _Verdict.lookAgain:
        return;
      case _Verdict.forgetOne:
        _forget(only!);
      case _Verdict.forgetAll:
        _forgetAll();
      case _Verdict.wipe:
        await _wipe(only, entry ?? _all);
    }
  }

  Future<_Verdict> _decide(String? only, _Attempts attempts) async {
    final bool hidden;
    final String? held;
    try {
      (hidden, held) = await _look();
    } catch (error, stack) {
      if (_lookAgain(only, attempts)) {
        Error.throwWithStackTrace(error, stack);
      }
      reportBackupFlowError(error, stack, 'while looking at the clipboard');
      return _lastResort(only);
    }
    if (hidden) {
      // A timer looks again; clear and dispose do not wait.
      return only != null && _lookAgain(only, attempts)
          ? _Verdict.lookAgain
          : _lastResort(only);
    }
    if (held == null || !_entries.containsKey(held)) {
      return _Verdict.forgetAll;
    }
    if (only == null || held == only) {
      return _Verdict.wipe;
    }
    // Another of ours, with a timer of its own.
    return _Verdict.forgetOne;
  }

  /// Whether the clipboard is hidden from the app, and otherwise the text it shows: null when it
  /// holds no text, or holds text it withholds, which was not written by this app.
  Future<(bool, String?)> _look() async {
    final foreground = _inForeground;
    if (!await clipboardHasText()) {
      // Android hides the clipboard from an app out of the foreground; the answer is final only
      // when the app was in the foreground before and after the question. Elsewhere it is final.
      final hidden =
          defaultTargetPlatform == TargetPlatform.android &&
          !(foreground && _inForeground);
      return (hidden, null);
    }
    try {
      return (false, await readClipboardText());
    } on TimeoutException {
      // The platform holds text and has not shown it within the wait: on iOS, the user has not
      // answered the paste prompt. Text this app wrote is shown without one, so this is not ours.
      return (false, null);
    }
  }

  bool get _inForeground =>
      isAppInForeground(WidgetsBinding.instance.lifecycleState);

  /// After the looks are used up: wipe without looking what is known to be placed, forget the rest.
  _Verdict _lastResort(String? only) {
    final placed = only == null
        ? _entries.values.any((e) => e.placed)
        : _entries[only]!.placed;
    return placed
        ? _Verdict.wipe
        : (only == null ? _Verdict.forgetAll : _Verdict.forgetOne);
  }

  /// Counts a look that did not show the clipboard. True when another look has been armed.
  bool _lookAgain(String? only, _Attempts attempts) {
    if (++attempts.looks >= _looksBeforeWipe) {
      return false;
    }
    _arm(only, attempts, _retryAfter);
    return true;
  }

  Future<void> _wipe(String? only, _Attempts attempts) async {
    try {
      await writeClipboardText('');
    } catch (error, stack) {
      if (++attempts.wipeFailures < _wipeFailuresBeforeGivingUp) {
        _arm(only, attempts, _retryAfter);
      } else {
        only == null ? _forgetAll() : _forget(only);
      }
      Error.throwWithStackTrace(error, stack);
    }
    _forgetAll();
  }

  void _arm(String? only, _Attempts attempts, Duration after) {
    attempts.timer?.cancel();
    attempts.timer = Timer(
      after,
      () => unawaited(_removeReporting(_disposed ? null : only, 'on a timer')),
    );
  }

  void _forget(String text) {
    _entries.remove(text)?.timer?.cancel();
  }

  /// After a wipe, or a look that showed none of our texts, nothing of ours is on the clipboard.
  void _forgetAll() {
    for (final entry in _entries.values) {
      entry.timer?.cancel();
    }
    _entries.clear();
    _all.reset();
  }
}

enum _Verdict { wipe, forgetOne, forgetAll, lookAgain }

/// The retry state of one text, or of a clear of every text.
class _Attempts {
  Timer? timer;
  int looks = 0;
  int wipeFailures = 0;

  void reset() {
    timer?.cancel();
    timer = null;
    looks = 0;
    wipeFailures = 0;
  }
}

class _Entry extends _Attempts {
  bool placed = false;
  int generation = 0;

  void startCopy() {
    reset();
    placed = false;
    generation++;
  }
}
