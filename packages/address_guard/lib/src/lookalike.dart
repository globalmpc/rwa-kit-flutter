import 'address.dart';

/// Hex characters compared at the start of an address by default, after `0x`. Four is what most
/// wallets show in a shortened address, and what address-poisoning attackers match.
const int defaultPrefixLength = 4;

/// Hex characters compared at the end of an address by default.
const int defaultSuffixLength = 4;

/// What a look-alike was compared against.
enum MatchSource {
  /// A [KnownRecipient]: an address the user has really chosen to pay.
  knownRecipient,

  /// Another address in the same batch, such as another row of a payout list. The user has not
  /// necessarily paid it, so a match says only that two entries of the batch resemble each other.
  sameBatch,
}

/// One address that a candidate imitates.
class LookalikeMatch {
  const LookalikeMatch({
    required this.imitated,
    required this.source,
    required this.prefix,
    required this.suffix,
    required this.candidateMiddle,
    required this.imitatedMiddle,
  });

  /// The address being imitated, lower case.
  final String imitated;
  final MatchSource source;

  /// The shared opening characters, without `0x`.
  final String prefix;

  /// The shared closing characters.
  final String suffix;

  /// The candidate's middle, which differs from [imitatedMiddle].
  final String candidateMiddle;
  final String imitatedMiddle;

  @override
  String toString() => 'LookalikeMatch($imitated, ${source.name})';
}

/// The addresses in [others] that [candidate] imitates: the same first [prefixLength] and last
/// [suffixLength] hex characters, and a different middle.
///
/// Comparison is on the 40 hex characters after `0x` and ignores case, because casing is a
/// checksum and not part of the address. An exact match is never a look-alike: it is the same
/// account. Each imitated address is reported once.
///
/// Throws [FormatException] when [candidate] or an entry of [others] is not an EVM address, and
/// [ArgumentError] when a length is below one or the two leave no middle to differ in.
List<LookalikeMatch> findLookalikes(
  String candidate,
  Iterable<String> others, {
  int prefixLength = defaultPrefixLength,
  int suffixLength = defaultSuffixLength,
  MatchSource source = MatchSource.knownRecipient,
}) {
  checkWindow(prefixLength, suffixLength);
  final body = addressBody(candidate);
  final head = body.substring(0, prefixLength);
  final tail = body.substring(40 - suffixLength);
  final seen = <String>{};
  final matches = <LookalikeMatch>[];
  for (final entry in others) {
    final other = addressBody(entry);
    if (!seen.add(other) || other == body) continue;
    if (!other.startsWith(head) || !other.endsWith(tail)) continue;
    matches.add(
      LookalikeMatch(
        imitated: '0x$other',
        source: source,
        prefix: head,
        suffix: tail,
        candidateMiddle: body.substring(prefixLength, 40 - suffixLength),
        imitatedMiddle: other.substring(prefixLength, 40 - suffixLength),
      ),
    );
  }
  return matches;
}

/// Throws [ArgumentError] unless both lengths are at least one and leave a middle of at least one
/// character. With nothing left in the middle, every "look-alike" would be the same address, so
/// the check could never fire; asking for that is a mistake worth reporting.
void checkWindow(int prefixLength, int suffixLength) {
  if (prefixLength < 1) {
    throw ArgumentError.value(
      prefixLength,
      'prefixLength',
      'must be 1 or more',
    );
  }
  if (suffixLength < 1) {
    throw ArgumentError.value(
      suffixLength,
      'suffixLength',
      'must be 1 or more',
    );
  }
  if (prefixLength + suffixLength >= 40) {
    throw ArgumentError(
      'prefixLength ($prefixLength) plus suffixLength ($suffixLength) must be under 40, '
      'or no middle is left to differ in',
    );
  }
}
