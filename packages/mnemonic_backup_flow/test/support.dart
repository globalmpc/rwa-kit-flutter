import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

/// The BIP39 specification's own test vector for all-zero entropy. It is a published constant,
/// not a wallet, and it is the only fixed phrase in this repository.
const specVector12 =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

/// The same vector's last word replaced, which breaks the checksum while every word stays valid.
const specVector12BadChecksum =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon';

/// Puts the app in the background for the rest of the test, where Android hides the clipboard.
/// The test binding starts every test in the foreground again.
void sendToBackground(WidgetTester tester) =>
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

/// Brings the app back to the foreground.
void bringToForeground(WidgetTester tester) =>
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

/// Stands in for the platform clipboard so tests can read what was copied and what was cleared.
class FakeClipboard {
  String? text;

  /// How many times `Clipboard.getData` was called.
  int reads = 0;

  /// When set, the next `Clipboard.setData` waits for it, to reproduce a slow platform write.
  Completer<void>? gateNextSetData;

  /// When true, the next `Clipboard.setData` fails, as a platform write can.
  bool failNextSetData = false;

  /// When true, the next `Clipboard.setData` stores the text and then fails, as a write whose
  /// reply is lost does.
  bool failNextSetDataAfterWrite = false;

  /// When true, the next `Clipboard.hasStrings` answers false, as Android does for an app that is
  /// not in the foreground and as any platform does for an empty clipboard or a photo.
  bool hideNextLook = false;

  /// When true, the next `Clipboard.getData` answers with no text although the clipboard holds
  /// some, as iOS does when the user declines to let the app read another app's text.
  bool refuseNextGetData = false;

  /// When true, the next `Clipboard.getData` fails.
  bool failNextGetData = false;

  /// When set, the next `Clipboard.getData` waits for it, as iOS does while the user answers the
  /// paste prompt.
  Completer<void>? gateNextGetData;

  /// When set, the next `Clipboard.hasStrings` waits for it.
  Completer<void>? gateNextHasStrings;

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            if (failNextSetData) {
              failNextSetData = false;
              throw PlatformException(code: 'fake', message: 'write failed');
            }
            final gate = gateNextSetData;
            gateNextSetData = null;
            if (gate != null) {
              await gate.future;
            }
            text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
            if (failNextSetDataAfterWrite) {
              failNextSetDataAfterWrite = false;
              throw PlatformException(code: 'fake', message: 'reply lost');
            }
            return null;
          case 'Clipboard.getData':
            reads++;
            final readGate = gateNextGetData;
            gateNextGetData = null;
            if (readGate != null) {
              await readGate.future;
            }
            if (failNextGetData) {
              failNextGetData = false;
              throw PlatformException(code: 'fake', message: 'read failed');
            }
            if (refuseNextGetData) {
              refuseNextGetData = false;
              return null;
            }
            return text == null ? null : <String, Object?>{'text': text};
          case 'Clipboard.hasStrings':
            final lookGate = gateNextHasStrings;
            gateNextHasStrings = null;
            if (lookGate != null) {
              await lookGate.future;
            }
            if (hideNextLook) {
              hideNextLook = false;
              return <String, Object?>{'value': false};
            }
            return <String, Object?>{'value': text?.isNotEmpty ?? false};
          default:
            return null;
        }
      },
    );
  }
}

/// Records protect and release calls, and lets a test hold either step open or make protect
/// fail, asynchronously or synchronously.
class RecordingScreenProtection extends ScreenProtection {
  RecordingScreenProtection({
    this.holdProtect = false,
    this.holdRelease = false,
    this.failProtect = false,
    this.failRelease = false,
    this.throwSynchronously = false,
  });

  final bool holdProtect;
  final bool holdRelease;

  /// Makes protect() fail, as a plugin does on an unsupported platform.
  final bool failProtect;

  /// With [failProtect], throws before returning a future, as a plain function can.
  final bool throwSynchronously;

  /// Makes release() fail.
  final bool failRelease;

  final events = <String>[];
  final _protected = Completer<void>();
  final _released = Completer<void>();

  void completeProtect() => _protected.complete();
  void completeRelease() => _released.complete();

  @override
  Future<void> protect() {
    events.add('protect');
    if (failProtect && throwSynchronously) {
      throw StateError('no screenshot plugin on this platform');
    }
    return _protectAsync();
  }

  Future<void> _protectAsync() async {
    if (failProtect) {
      throw StateError('no screenshot plugin on this platform');
    }
    if (holdProtect) {
      await _protected.future;
    }
  }

  @override
  Future<void> release() async {
    events.add('release');
    if (failRelease) {
      throw StateError('release failed');
    }
    if (holdRelease) {
      await _released.future;
    }
  }
}

Widget wrap(Widget child) => MaterialApp(home: child);

/// Holds a value a callback hands back during a test.
class Captured<T> {
  T? value;
}
