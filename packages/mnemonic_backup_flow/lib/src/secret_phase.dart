/// Where a protected step stands, for an app that draws the step itself.
///
/// Only [visible] lets the secret (the words, the choices of a challenge, the phrase being typed)
/// be painted. Every other phase has a text in [MnemonicBackupStrings] to show in its place,
/// through `strings.placeholder(phase)`.
enum MnemonicSecretPhase {
  /// The screen protection has not answered yet. Nothing secret is shown.
  preparing,

  /// The screen protection failed or did not answer in time. Nothing secret is shown, and the
  /// user should go back and try again.
  protectionFailed,

  /// The protection is on, but the app is not in the foreground, so the secret is kept out of
  /// the app switcher snapshot and the notification pull-down.
  hidden,

  /// The protection is on and the app is in the foreground: the secret may be on screen.
  visible,
}
