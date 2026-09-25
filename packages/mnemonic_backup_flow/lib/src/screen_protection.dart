/// Keeps the recovery phrase out of screenshots and screen recordings while it is on screen.
///
/// This package contains no native code, so the app supplies the implementation, usually by
/// wrapping the screenshot plugin it already uses. Each screen calls [protect] before it renders
/// the phrase, waits for it, and calls [release] once the screen is gone.
///
/// What a platform can do differs: Android can refuse screenshots and recordings outright
/// (`FLAG_SECURE`); iOS cannot, and plugins there hide the content behind an overlay when a
/// screenshot or a recording happens. Say so in your app's copy rather than promising more.
abstract class ScreenProtection {
  const ScreenProtection();

  /// A deliberate opt-out. Screenshots and recordings of the phrase are then possible, which is
  /// acceptable in a development build and nowhere else.
  const factory ScreenProtection.none() = _NoScreenProtection;

  /// Wraps two callbacks, which is all a plugin adapter needs.
  const factory ScreenProtection.callbacks({
    required Future<void> Function() protect,
    required Future<void> Function() release,
  }) = _CallbackScreenProtection;

  /// Called before the phrase is rendered. The screen shows a placeholder until this completes.
  Future<void> protect();

  /// Called once the phrase is no longer rendered.
  Future<void> release();
}

class _NoScreenProtection extends ScreenProtection {
  const _NoScreenProtection();

  @override
  Future<void> protect() async {}

  @override
  Future<void> release() async {}
}

class _CallbackScreenProtection extends ScreenProtection {
  const _CallbackScreenProtection({
    required Future<void> Function() protect,
    required Future<void> Function() release,
  }) : _protect = protect,
       _release = release;

  final Future<void> Function() _protect;
  final Future<void> Function() _release;

  @override
  Future<void> protect() => _protect();

  @override
  Future<void> release() => _release();
}
