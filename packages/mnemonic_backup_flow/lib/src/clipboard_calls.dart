import 'dart:async';

import 'package:flutter/services.dart';

/// How long a clipboard write, or the question whether the clipboard holds text, may take. A
/// platform that never answers must not block the work queued behind the call.
const clipboardCallTimeout = Duration(seconds: 10);

/// How long a clipboard read may take: on iOS it waits for the user to answer the paste prompt.
const clipboardReadTimeout = Duration(seconds: 60);

Future<bool> clipboardHasText() =>
    Clipboard.hasStrings().timeout(clipboardCallTimeout);

Future<String?> readClipboardText() async => (await Clipboard.getData(
  Clipboard.kTextPlain,
).timeout(clipboardReadTimeout))?.text;

/// Writes [text], failing with a [TimeoutException] when the platform does not answer in time.
/// A write that lands after that calls [onLate], since the text is on the clipboard from then on.
Future<void> writeClipboardText(String text, {void Function()? onLate}) async {
  final write = Clipboard.setData(ClipboardData(text: text));
  try {
    await write.timeout(clipboardCallTimeout);
  } on TimeoutException {
    if (onLate != null) {
      unawaited(write.then((_) => onLate(), onError: (Object _) {}));
    }
    rethrow;
  }
}
