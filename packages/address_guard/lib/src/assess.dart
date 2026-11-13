import 'address.dart';
import 'history.dart';
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
  /// another batch entry), but differs in the middle, or sent a poisoning transfer into the user's
  /// history. The pattern of an address-poisoning attack. Do not send.
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

  /// Sent a transfer into the user's history that [screenHistory] flagged as poisoning: the
  /// address is in the history because an attacker put it there. Added in 0.2.0, last, so the
  /// index of every earlier value is unchanged.
  plantedInHistory,
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
  /// sees whose address it is. Never set for [RecipientVerdict.lookalike], even for a saved
  /// address that planted a transfer: its label must not vouch for it on the warning.
  final KnownRecipient? knownRecipient;

  /// Every address the candidate resembles: matches with the known recipients first (including
  /// those [screenHistory] recorded for a planted address), then with the batch, each group
  /// closest copy first, because a recipient the user really chose matters more than a list row.
  /// Not empty when [verdict] is [RecipientVerdict.lookalike] (for suspects that come from
  /// [screenHistory], which always name what they imitate). For other verdicts it can still
  /// hold matches, which do not change the verdict: a known address can share its ends with
  /// others.
  final List<LookalikeMatch> lookalikes;

  /// The comparison window used: the fewest characters a look-alike must share at each end.
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
/// [suspects] are what [screenHistory] flagged in the user's history. A candidate that is the
/// counterparty of one is a look-alike, shown with the addresses the suspect imitates, even when
/// it does not match the window here (for example when the history was screened against an older
/// list of known recipients) and even when it is in the address book: saving the look-alike
/// copied from the history is how the attack succeeds. Only a recipient the owner has really paid
/// outranks it. Pass suspects screened for the same account and chain as [known].
///
/// The checks run in order of how much they should stop a payment, and the first that decides
/// wins:
///
/// 1. Not an address: [RecipientVerdict.invalid].
/// 2. An exact known recipient, unless its casing contradicts the checksum, or it is only saved
///    and was flagged in [suspects]: [RecipientVerdict.known]. An exact match outranks
///    resemblance, because flagging a recipient the user really pays teaches people to ignore the
///    warning.
/// 3. Imitates a known recipient or a batch entry, or was flagged in [suspects]:
///    [RecipientVerdict.lookalike]. This outranks a checksum complaint, because both mean "do not
///    send" and the casing would hide the dangerous half.
/// 4. Casing contradicts the checksum: [RecipientVerdict.badChecksum].
/// 5. Otherwise: [RecipientVerdict.firstTime].
///
/// Pure: no I/O. Throws [ArgumentError] for a comparison window that leaves no middle.
RecipientCheck assessRecipient(
  String candidate, {
  required Iterable<KnownRecipient> known,
  Iterable<String> batch = const [],
  Iterable<PoisoningSuspect> suspects = const [],
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
  final knownMatches = findLookalikes(
    normalized,
    knownList.map((entry) => entry.address),
    prefixLength: prefixLength,
    suffixLength: suffixLength,
  );
  final evidence = _plantedEvidence(suspects, normalized);
  final planted = evidence.isNotEmpty;
  // Each imitated address once, in the known group, since it was a known recipient when the
  // history was screened.
  final imitated = {for (final match in knownMatches) match.imitated};
  final plantedMatches = [
    for (final match in evidence)
      if (imitated.add(normalizeAddress(match.imitated))) match,
  ];
  final batchMatches = findLookalikes(
    normalized,
    // A batch row that is also a known recipient is already compared above; reporting it
    // twice would show the same address under two different labels.
    batch
        .where(isEvmAddress)
        .where((entry) => !knownAddresses.contains(normalizeAddress(entry))),
    prefixLength: prefixLength,
    suffixLength: suffixLength,
    source: MatchSource.sameBatch,
  );
  // An address can be both paid and saved; prefer the entry that carries the user's own label.
  final matches = knownList.where((entry) => entry.address == normalized);
  final match = matches
      .where((entry) => entry.label != null)
      .followedBy(matches);

  RecipientCheck result(
    RecipientVerdict verdict, {
    KnownRecipient? knownRecipient,
    List<LookalikeMatch> extra = const [],
    List<LookalikeMatch>? batchShown,
  }) => RecipientCheck(
    candidate: candidate,
    normalized: normalized,
    verdict: verdict,
    checksum: checksum,
    reasons: List.unmodifiable(reasons),
    knownRecipient: knownRecipient,
    lookalikes: List.unmodifiable([
      ...(extra.isEmpty
          ? knownMatches
          : closestFirst([...knownMatches, ...extra])),
      ...(batchShown ?? batchMatches),
    ]),
    prefixLength: prefixLength,
    suffixLength: suffixLength,
  );

  final paidByOwner = matches.any(
    (entry) => entry.provenance == RecipientProvenance.sentByOwner,
  );

  // A planted transfer outranks an address-book entry, because saving the look-alike copied from
  // the history is the attack succeeding. It never outranks the owner's own signed payment.
  if (match.isNotEmpty && (!planted || paidByOwner)) {
    // The bytes are a known recipient's, so it cannot be imitating another one. Altered casing
    // still means someone edited it, which is worth stopping for.
    if (checksum == ChecksumState.mismatch) {
      return result(RecipientVerdict.badChecksum, knownRecipient: match.first);
    }
    reasons.add(
      paidByOwner
          ? RecipientReason.knownRecipient
          : RecipientReason.savedRecipient,
    );
    if (knownMatches.isNotEmpty) {
      reasons.add(RecipientReason.othersShareEnds);
    }
    return result(RecipientVerdict.known, knownRecipient: match.first);
  }
  if (knownMatches.isNotEmpty || batchMatches.isNotEmpty || planted) {
    if (knownMatches.isNotEmpty || plantedMatches.isNotEmpty) {
      reasons.add(RecipientReason.imitatesKnownRecipient);
    }
    // A batch row the history screen already named is shown once, as the known recipient it was.
    final batchShown = [
      for (final match in batchMatches)
        if (!imitated.contains(match.imitated)) match,
    ];
    if (batchShown.isNotEmpty) {
      reasons.add(RecipientReason.imitatesBatchEntry);
    }
    if (planted) reasons.add(RecipientReason.plantedInHistory);
    return result(
      RecipientVerdict.lookalike,
      extra: plantedMatches,
      batchShown: batchShown,
    );
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

/// What [screenHistory] found for [normalized]: the known recipients it imitated in the history,
/// read once. A suspect built by hand may carry a checksummed counterparty; matches that do not
/// name another known recipient are not evidence, and a suspect with none is ignored, so a
/// look-alike verdict always has something to show.
List<LookalikeMatch> _plantedEvidence(
  Iterable<PoisoningSuspect> suspects,
  String normalized,
) => [
  for (final suspect in suspects)
    if (isEvmAddress(suspect.counterparty) &&
        normalizeAddress(suspect.counterparty) == normalized)
      for (final match in suspect.imitates)
        if (match.source == MatchSource.knownRecipient &&
            isEvmAddress(match.imitated) &&
            normalizeAddress(match.imitated) != normalized)
          match,
];
