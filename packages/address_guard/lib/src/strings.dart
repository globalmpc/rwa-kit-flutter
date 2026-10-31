import 'assess.dart';

/// Every user-facing text in [RecipientConfirmCard], with English defaults.
///
/// Replace any of them to translate or reword. Texts that carry a value are functions.
class AddressGuardStrings {
  const AddressGuardStrings({
    this.titleKnown = 'You have paid this address before',
    this.titleSaved = 'This address is in your address book',
    this.titleLookalikeBatch = 'This address imitates another one in the list',
    this.titleFirstTime = 'First payment to this address',
    this.titleLookalike = 'This address imitates one you have used',
    this.titleInvalid = 'This is not a valid address',
    this.titleBadChecksum = 'This address has been altered',
    this.recipientLabel = 'Recipient',
    this.imitatedLabel = 'It looks like this address you have paid or saved',
    this.imitatedBatchLabel =
        'It looks like this other address in the same list',
    this.highlightHint =
        'Highlighted characters are the ones that differ. Only the start and the end match.',
    this.firstTimeAcknowledgement =
        'I have checked every character of the full address with the person I am paying',
    this.overrideAcknowledgement =
        'I have checked every character and I still want to pay this address',
    this.confirm = 'Confirm recipient',
    this.cancel = 'Cancel',
    this.reasonNotAnAddress =
        'An address is 0x followed by 40 characters from 0-9 and a-f.',
    this.reasonChecksumMismatch =
        'The mix of capital and small letters does not match the address checksum, so at least '
        'one character was changed. Copy the address again from the person you are paying.',
    this.reasonNoChecksum =
        'The address is all small or all capital letters, so it has no checksum to verify.',
    this.reasonKnownRecipient =
        'You have sent a payment to this exact address before.',
    this.reasonSavedRecipient =
        'You saved this exact address earlier. Make sure it is still the one you mean to pay.',
    this.reasonOthersShareEnds =
        'Other addresses you have paid or saved share its first and last characters. That does '
        'not make this one suspect.',
    this.reasonImitatesKnownRecipient =
        'Its first and last characters match an address you have paid or saved, but the middle is '
        'different. Scammers create addresses like this and send you a small or empty transfer '
        'so that it appears in your history, hoping you copy it from there.',
    this.reasonImitatesBatchEntry =
        'Its first and last characters match another address in the same list, but the middle '
        'is different.',
    this.reasonNothingToCompare =
        'There are no earlier payments to compare it with.',
    this.reasonUnlikeKnownRecipients =
        'It does not resemble any address you have paid or saved. Check the full address with '
        'the person you are paying, not only the start and the end.',
    this.moreImitated = _defaultMoreImitated,
    this.network = _defaultNetwork,
    this.addressSemantics = _defaultAddressSemantics,
  });

  final String titleKnown;
  final String titleSaved;
  final String titleLookalikeBatch;
  final String titleFirstTime;
  final String titleLookalike;
  final String titleInvalid;
  final String titleBadChecksum;
  final String recipientLabel;
  final String imitatedLabel;
  final String imitatedBatchLabel;
  final String highlightHint;
  final String firstTimeAcknowledgement;
  final String overrideAcknowledgement;
  final String confirm;
  final String cancel;
  final String reasonNotAnAddress;
  final String reasonChecksumMismatch;
  final String reasonNoChecksum;
  final String reasonKnownRecipient;
  final String reasonSavedRecipient;
  final String reasonOthersShareEnds;
  final String reasonImitatesKnownRecipient;
  final String reasonImitatesBatchEntry;
  final String reasonNothingToCompare;
  final String reasonUnlikeKnownRecipients;

  /// The line under the imitated addresses when more matched than are shown.
  final String Function(int hidden) moreImitated;

  /// The network line, given the name the app passed (or null) and the chain id.
  final String Function(String? networkName, int chainId) network;

  /// What a screen reader announces for an address, given its 4-character groups after `0x`.
  final String Function(List<String> groups) addressSemantics;

  /// The title for [check]: [title] of its verdict, told apart where the verdict alone would
  /// say something untrue (a saved address that was never paid, a look-alike of a list row).
  String titleFor(RecipientCheck check) {
    if (check.verdict == RecipientVerdict.known &&
        check.reasons.contains(RecipientReason.savedRecipient)) {
      return titleSaved;
    }
    if (check.verdict == RecipientVerdict.lookalike &&
        !check.reasons.contains(RecipientReason.imitatesKnownRecipient)) {
      return titleLookalikeBatch;
    }
    return title(check.verdict);
  }

  /// The title for [verdict].
  String title(RecipientVerdict verdict) => switch (verdict) {
    RecipientVerdict.known => titleKnown,
    RecipientVerdict.firstTime => titleFirstTime,
    RecipientVerdict.lookalike => titleLookalike,
    RecipientVerdict.invalid => titleInvalid,
    RecipientVerdict.badChecksum => titleBadChecksum,
  };

  /// The sentence for [reason].
  String reason(RecipientReason reason) => switch (reason) {
    RecipientReason.notAnAddress => reasonNotAnAddress,
    RecipientReason.checksumMismatch => reasonChecksumMismatch,
    RecipientReason.noChecksum => reasonNoChecksum,
    RecipientReason.knownRecipient => reasonKnownRecipient,
    RecipientReason.savedRecipient => reasonSavedRecipient,
    RecipientReason.othersShareEnds => reasonOthersShareEnds,
    RecipientReason.imitatesKnownRecipient => reasonImitatesKnownRecipient,
    RecipientReason.imitatesBatchEntry => reasonImitatesBatchEntry,
    RecipientReason.nothingToCompare => reasonNothingToCompare,
    RecipientReason.unlikeKnownRecipients => reasonUnlikeKnownRecipients,
  };
}

String _defaultMoreImitated(int hidden) =>
    'And $hidden more address${hidden == 1 ? '' : 'es'} with the same start and end.';

String _defaultNetwork(String? networkName, int chainId) => networkName == null
    ? 'Network: chain $chainId'
    : 'Network: $networkName (chain $chainId)';

// Each character spoken on its own, groups separated by a pause, so a screen reader spells the
// address instead of reading it as a word.
String _defaultAddressSemantics(List<String> groups) =>
    'Address 0x, ${groups.map((group) => group.split('').join(' ')).join(', ')}';
