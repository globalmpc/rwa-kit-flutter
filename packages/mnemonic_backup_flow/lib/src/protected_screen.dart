import 'dart:async';

import 'package:flutter/widgets.dart';

import 'lifecycle.dart';
import 'report.dart';
import 'screen_protection.dart';
import 'strings.dart';

/// Activates the screen protection when the state is created and releases it when the state is
/// disposed, with the two calls ordered: the release waits for the protect to settle, so a screen
/// left early cannot leave the protection switched on by a protect that finished later.
///
/// A protect that throws is followed by a release, so the plugin is not left half on, and is
/// reported once. A protect that does not answer within [protectionTimeout] puts the screen in
/// the failed state, where it never shows the secret, and is reported while the screen is still
/// there; if it answers later, the screen becomes active after all. The release waits for an
/// unanswered protect for at most [protectionTimeout] after the screen goes away and then runs
/// anyway, since a protection that took effect with its reply lost must not stay on for the rest
/// of the session; a protect that answers after that release is released again. The queued work
/// holds only the protection, a flag and a weak reference to the screen, never the screen itself,
/// so a call that never answers cannot keep a disposed screen and its phrase in memory.
///
/// [ScreenProtection.none] is recognised: there is nothing to switch on, so the screen is active
/// from its first frame and nothing runs on dispose.
///
/// Each screen protects and releases on its own. The protection is read once, when the state is
/// created. See the README on what that means for two protected screens that overlap. A subclass
/// must not throw from `initState` after `super.initState()`: a State whose `initState` throws is
/// never disposed, so the protection would stay on and the lifecycle observer registered.
mixin ProtectedScreenState<T extends StatefulWidget> on State<T> {
  ScreenProtection get screenProtection;

  /// How long this screen waits for protect() before treating it as failed, and how long its
  /// release waits for an unanswered protect. Null waits without limit.
  Duration? get protectionTimeout;

  /// True once the protection is active. Render the secret only while this is true.
  bool get protectionActive => _status == _ProtectionStatus.active;

  /// True when protect() threw or has not answered within [protectionTimeout].
  bool get protectionFailed => _status == _ProtectionStatus.failed;

  /// The text to show in place of the secret while the protection is not active.
  String protectionPlaceholder(MnemonicBackupStrings strings) =>
      protectionFailed ? strings.protectionFailed : strings.revealPreparing;

  /// True while the secret may be rendered: the protection is active and the app is in the
  /// foreground, where the app switcher snapshot and a notification pull-down are not taken.
  bool get secretVisible => protectionActive && _inForeground;

  /// The text to show in place of the secret while [secretVisible] is false: why it is hidden.
  String secretPlaceholder(MnemonicBackupStrings strings) =>
      protectionActive ? strings.revealHidden : protectionPlaceholder(strings);

  late final ScreenProtection _protection;
  late final Future<void> _activation;
  final _released = _ReleasedFlag();
  _ProtectionStatus _status = _ProtectionStatus.pending;
  late final _ForegroundWatch _foreground;
  bool _inForeground = true;

  @override
  void initState() {
    super.initState();
    _inForeground = isAppInForeground(WidgetsBinding.instance.lifecycleState);
    _foreground = _ForegroundWatch((state) {
      final next = isAppInForeground(state);
      if (mounted && next != _inForeground) {
        setState(() => _inForeground = next);
      }
    });
    WidgetsBinding.instance.addObserver(_foreground);
    // Locals only in the work below: an instance member would capture the screen.
    final protection = _protection = screenProtection;
    if (identical(protection, const ScreenProtection.none())) {
      // Nothing to switch on: active from the first frame, nothing to release.
      _status = _ProtectionStatus.active;
      _activation = Future<void>.value();
      return;
    }
    final released = _released;
    final screen = WeakReference<ProtectedScreenState<StatefulWidget>>(this);
    _activation = _protect(protection, released, screen);
    unawaited(_settle(_activation, protectionTimeout, screen));
  }

  void _show(_ProtectionStatus status) {
    if (mounted && _status != status) {
      setState(() => _status = status);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_foreground);
    if (!identical(_protection, const ScreenProtection.none())) {
      unawaited(
        _releaseAfter(_activation, protectionTimeout, _protection, _released),
      );
    }
    super.dispose();
  }
}

enum _ProtectionStatus { pending, active, failed }

/// Observes the app lifecycle on behalf of a screen without making the State an observer.
class _ForegroundWatch with WidgetsBindingObserver {
  _ForegroundWatch(this._onChange);

  final void Function(AppLifecycleState state) _onChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onChange(state);
}

class _ReleasedFlag {
  bool value = false;
}

/// Our own timeout, distinct from a [TimeoutException] the plugin itself may throw from protect(),
/// which is reported where it happened and must not be reported a second time here.
class _ProtectionTimedOut extends TimeoutException {
  _ProtectionTimedOut(Duration timeout)
    : super('The screen protection did not answer in time.', timeout);
}

Future<void> _protect(
  ScreenProtection protection,
  _ReleasedFlag released,
  WeakReference<ProtectedScreenState<StatefulWidget>> screen,
) async {
  try {
    await protection.protect();
  } catch (error, stack) {
    reportBackupFlowError(error, stack, 'while enabling screen protection');
    // Not awaited: the failure settles the screen now, and a release that hangs is its own fault.
    unawaited(
      _release(
        protection,
        'while releasing screen protection after a failed protect',
      ),
    );
    rethrow;
  }
  if (released.value) {
    // The screen went away and released before this answer came; what just switched on goes off.
    await _release(
      protection,
      'while releasing screen protection that answered late',
    );
    return;
  }
  // A protect that answered after the screen gave up on it is still a protection that is on.
  screen.target?._show(_ProtectionStatus.active);
}

Future<void> _settle(
  Future<void> activation,
  Duration? timeout,
  WeakReference<ProtectedScreenState<StatefulWidget>> screen,
) async {
  _ProtectionStatus next;
  try {
    await _bounded(activation, timeout);
    next = _ProtectionStatus.active;
  } on _ProtectionTimedOut catch (error, stack) {
    next = _ProtectionStatus.failed;
    final target = screen.target;
    if (target == null || !target.mounted) {
      // The user has left; the release is waiting on the call, and a slow answer is not a fault.
      return;
    }
    reportBackupFlowError(
      error,
      stack,
      'while waiting for the screen protection',
    );
  } catch (_) {
    // Reported where it happened, in _protect.
    next = _ProtectionStatus.failed;
  }
  screen.target?._show(next);
}

Future<void> _releaseAfter(
  Future<void> activation,
  Duration? timeout,
  ScreenProtection protection,
  _ReleasedFlag released,
) async {
  try {
    await _bounded(activation, timeout);
  } on _ProtectionTimedOut {
    // Unanswered. The protection may well be on with its reply lost; releasing is the safer
    // failure, and a late answer is released again in _protect.
  } catch (_) {
    // The protect failed and released itself.
    return;
  }
  released.value = true;
  await _release(protection, 'while releasing screen protection');
}

Future<void> _bounded(Future<void> activation, Duration? timeout) =>
    timeout == null
    ? activation
    : activation.timeout(
        timeout,
        onTimeout: () => throw _ProtectionTimedOut(timeout),
      );

Future<void> _release(ScreenProtection protection, String context) async {
  try {
    await protection.release();
  } catch (error, stack) {
    reportBackupFlowError(error, stack, context);
  }
}
