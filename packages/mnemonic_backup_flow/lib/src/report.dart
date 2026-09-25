import 'package:flutter/foundation.dart';

/// Reports a failure the package handled but the app should know about, through the same
/// channel Flutter uses for framework errors, so it reaches the debug console and any crash
/// reporter the app installed on [FlutterError.onError].
void reportBackupFlowError(Object error, StackTrace stack, String context) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'mnemonic_backup_flow',
      context: ErrorDescription(context),
    ),
  );
}
