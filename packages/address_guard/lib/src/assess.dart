import 'address.dart';
import 'known_recipients.dart';
import 'lookalike.dart';

/// What a check concluded about a recipient. There is no "safe" verdict: the package can say what
/// it found, not that a payment is safe.
enum RecipientVerdict {
  /// The user has really chosen to pay this exact address before.
  known,

  /// A well-formed address unlike every known recipient. Normal for a first payment, and the
  /// moment to check the full address.
  firstTime,

  /// Shares the first and last characters of an address the user has paid or saved (or of
  /// another batch entry), but differs in the middle. The pattern of an address-poisoning attack.
  /// Do not send.
  lookalike,

  /// Not a 20-byte EVM address.
  invalid,

  /// The casing contradicts the EIP-55 checksum, so at least one character was changed.
  badChecksum,
}

/// One finding behind a verdict, in the order the checks ran. Each has an English sentence in
/// [AddressGuardStrings] and can be translated there.
enum RecipientReason {
  /// The input is not `0x` followed by 40 hex characters.
  notAnAddress,

  /// The casing contradicts the checksum.
  checksumMismatch,

  /// All lower case or all upper case, so there was no checksum to verify. Not an error.
  noChecksum,

  /// An exact match with a recipient the user has paid ([RecipientProvenance.sentByOwner]).
  knownRecipient,

  /// An exact match with an address the user saved or confirmed in the app
  /// ([RecipientProvenance.confirmedByUser]) and has not paid from this history.
  savedRecipient,

  /// Other known recipients share both ends with this known one. Reported for completeness; it
  /// does not make a known recipient suspect.
  othersShareEnds,

  /// Imitates a known recipient: one the user has paid or saved.
  imitatesKnownRecipient,

  /// Imitates another address in the same batch.
  imitatesBatchEntry,

  /// The app supplied no known recipients, so nothing could be compared.
  nothingToCompare,

  /// Unlike every known recipient in both ends and the middle.
  unlikeKnownRecipients,
}

/// The result of [assessRecipient].
class RecipientCheck {
  const RecipientCheck({
    required this.candidate,
    required this.verdict,
    required this.reasons,
    this.normalized,
    this.checksum,
    this.knownRecipient,
    this.lookalikes = const [],
    this.prefixLength = defaultPrefixLength,
    this.suffixLength = defaultSuffixLength,
  });

  /// The input exactly as given, casing and all.
  final String candidate;

  /// Lower case. Null when [verdict] is [RecipientVerdict.invalid].
  final String? normalized;

  final RecipientVerdict verdict;

  /// Null when [verdict] is [RecipientVerdict.invalid].
  final ChecksumState? checksum;

  /// Why, in the order the checks ran. Never empty.
  final List<RecipientReason> reasons;

  /// The matching known recipient: set when [verdict] is [RecipientVerdict.known], and when it is
  /// [RecipientVerdict.badChecksum] for a known address whose casing was edited, so the user still
  /// sees whose address it is.
  final KnownRecipient? knownRecipient;

  /// Every address the candidate resembles, from the known recipients and the batch. Not empty
  /// when [verdict] is [RecipientVerdict.lookalike]. For other verdicts it can still hold matches,
  /// which do not change the verdict: a known address can share its ends with others.
  final List<LookalikeMatch> lookalikes;

  /// The comparison window used.
  final int prefixLength;
  final int suffixLength;

  /// Whether the verdict means the payment should not go ahead as it is.
  bool get shouldStop =>
      verdict == RecipientVerdict.lookalike ||
      verdict == RecipientVerdict.invalid ||
      verdict == RecipientVerdict.badChecksum;
}

/// Judges one recipient address before a payment.
///
/// [known] are the addresses the user has really chosen to pay: from [deriveKnownRecipients] and
/// the app's own address book. [batch] are other addresses compared in the same operation, such as
/// the rest of a payout list; a match with them flags a look-alike but never makes an address
/// known. Entries of [batch] that are not addresses are skipped: they cannot be imitated, and one
/// malformed row must not stop the others from being checked. Assess that row on its own to
/// report it as [RecipientVerdict.invalid].
///
/// The checks run in order of how much they should stop a payment, and the first that decides
/// wins:
///
/// 1. Not an address: [RecipientVerdict.invalid].
/// 2. An exact known recipient, unless its casing contradicts the checksum:
///    [RecipientVerdict.known]. An exact match outranks resemblance, because flagging a recipient
///    the user really pays teaches people to ignore the warning.
/// 3. Imitates a known recipient or a batch entry: [RecipientVerdict.lookalike]. This outranks a
///    checksum complaint, because both mean "do not send" and the casing would hide the
///    dangerous half.
/// 4. Casing contradicts the checksum: [RecipientVerdict.badChecksum].
/// 5. Otherwise: [RecipientVerdict.firstTime].
///
/// Pure: no I/O. Throws [ArgumentError] for a comparison window that leaves no middle.
RecipientCheck assessRecipient(
  String candidate, {
  required Iterable<KnownRecipient> known,
  Iterable<String> batch = const [],
  int prefixLength = defaultPrefixLength,
  int suffixLength = defaultSuffixLength,
}) {
  checkWindow(prefixLength, suffixLength);
  if (!isEvmAddress(candidate)) {
    return RecipientCheck(
      candidate: candidate,
      verdict: RecipientVerdict.invalid,
      reasons: const [RecipientReason.notAnAddress],
      prefixLength: prefixLength,
      suffixLength: suffixLength,
    );
  }

  final reasons = <RecipientReason>[];
  final normalized = normalizeAddress(candidate);
  final checksum = checksumState(candidate);
  if (checksum == ChecksumState.mismatch) {
    reasons.add(RecipientReason.checksumMismatch);
  } else if (checksum == ChecksumState.unchecksummed) {
    reasons.add(RecipientReason.noChecksum);
  }

  final knownList = known.toList(growable: false);
  final knownAddresses = {for (final entry in knownList) entry.address};
  final lookalikes = [
    ...findLookalikes(
      normalized,
      knownList.map((entry) => entry.address),
      prefixLength: prefixLength,
      suffixLength: suffixLength,
    ),
    ...findLookalikes(
      normalized,
      // A batch row that is also a known recipient is already compared above; reporting it
      // twice would show the same address under two different labels.
      batch
          .where(isEvmAddress)
          .where((entry) => !knownAddresses.contains(normalizeAddress(entry))),
      prefixLength: prefixLength,
      suffixLength: suffixLength,
      source: MatchSource.sameBatch,
    ),
  ];
  // An address can be both paid and saved; prefer the entry that carries the user's own label.
  final matches = knownList.where((entry) => entry.address == normalized);
  final match = matches
      .where((entry) => entry.label != null)
      .followedBy(matches);

  RecipientCheck result(
    RecipientVerdict verdict, {
    KnownRecipient? knownRecipient,
  }) => RecipientCheck(
    candidate: candidate,
    normalized: normalized,
    verdict: verdict,
    checksum: checksum,
    reasons: List.unmodifiable(reasons),
    knownRecipient: knownRecipient,
    lookalikes: List.unmodifiable(lookalikes),
    prefixLength: prefixLength,
    suffixLength: suffixLength,
  );

  if (match.isNotEmpty) {
    // The bytes are a known recipient's, so it cannot be imitating another one. Altered casing
    // still means someone edited it, which is worth stopping for.
    if (checksum == ChecksumState.mismatch) {
      return result(RecipientVerdict.badChecksum, knownRecipient: match.first);
    }
    reasons.add(
      matches.any(
            (entry) => entry.provenance == RecipientProvenance.sentByOwner,
          )
          ? RecipientReason.knownRecipient
          : RecipientReason.savedRecipient,
    );
    if (lookalikes.any((m) => m.source == MatchSource.knownRecipient)) {
      reasons.add(RecipientReason.othersShareEnds);
    }
    return result(RecipientVerdict.known, knownRecipient: match.first);
  }
  if (lookalikes.isNotEmpty) {
    if (lookalikes.any((m) => m.source == MatchSource.knownRecipient)) {
      reasons.add(RecipientReason.imitatesKnownRecipient);
    }
    if (lookalikes.any((m) => m.source == MatchSource.sameBatch)) {
      reasons.add(RecipientReason.imitatesBatchEntry);
    }
    return result(RecipientVerdict.lookalike);
  }
  if (checksum == ChecksumState.mismatch) {
    return result(RecipientVerdict.badChecksum);
  }
  reasons.add(
    knownList.isEmpty
        ? RecipientReason.nothingToCompare
        : RecipientReason.unlikeKnownRecipients,
  );
  return result(RecipientVerdict.firstTime);
}
