import 'address.dart';

/// The fewest hex characters, after `0x`, that a look-alike must share with the start of the
/// address it imitates.
///
/// Three, because that is where measured attacks begin. The USENIX Security 2025 study of 270
/// million poisoning transfers on Ethereum and BNB Smart Chain found look-alikes sharing at least
/// three characters at the start and four at the end, with more on either side as attackers spend
/// more on generating them. It also matches wallets that shorten an address to its first few
/// characters.
const int defaultPrefixLength = 3;

/// The fewest hex characters a look-alike must share with the end of the address it imitates.
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

  /// Every opening character the two share, without `0x`. At least the requested minimum, and
  /// longer when the look-alike copies more.
  final String prefix;

  /// Every closing character the two share.
  final String suffix;

  /// The candidate's characters between [prefix] and [suffix]. Its first and last characters
  /// differ from [imitatedMiddle]'s.
  final String candidateMiddle;
  final String imitatedMiddle;

  /// How many characters the two share at the ends, [prefix] and [suffix] together. The more,
  /// the closer the copy, and the more likely a person is to take one for the other.
  int get sharedLength => prefix.length + suffix.length;

  @override
  String toString() => 'LookalikeMatch($imitated, ${source.name})';
}

/// The addresses in [others] that [candidate] imitates: at least the first [prefixLength] and the
/// last [suffixLength] hex characters in common, and a different middle.
///
/// The two lengths are minimums. A look-alike that copies more of the ends, six and six for
/// example, is found too, and its [LookalikeMatch.prefix] and [LookalikeMatch.suffix] hold
/// everything it shares. Matches come closest copy first, the longest
/// [LookalikeMatch.sharedLength] first and in the order of [others] when equally close, because
/// the closest copy is the one a person is most likely to pick.
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
  final seen = <String>{};
  final matches = <LookalikeMatch>[];
  for (final entry in others) {
    final other = addressBody(entry);
    if (!seen.add(other) || other == body) continue;
    final head = sharedHead(body, other);
    if (head < prefixLength) continue;
    // The two differ at index `head`, so the shared end can never reach back over it.
    final tail = sharedTail(body, other);
    if (tail < suffixLength) continue;
    matches.add(
      LookalikeMatch(
        imitated: '0x$other',
        source: source,
        prefix: body.substring(0, head),
        suffix: body.substring(40 - tail),
        candidateMiddle: body.substring(head, 40 - tail),
        imitatedMiddle: other.substring(head, 40 - tail),
      ),
    );
  }
  return closestFirst(matches);
}

/// How many of the 40 lower-case hex characters [a] and [b] share at the start.
int sharedHead(String a, String b) {
  var length = 0;
  while (length < 40 && a[length] == b[length]) {
    length++;
  }
  return length;
}

/// How many of the 40 lower-case hex characters [a] and [b] share at the end.
int sharedTail(String a, String b) {
  var length = 0;
  while (length < 40 && a[39 - length] == b[39 - length]) {
    length++;
  }
  return length;
}

/// Sorted by [LookalikeMatch.sharedLength], longest first, keeping the given order among equals.
/// [List.sort] is not stable, so the original position breaks ties.
List<LookalikeMatch> closestFirst(List<LookalikeMatch> matches) {
  final indexed = matches.indexed.toList()
    ..sort((a, b) {
      final closer = b.$2.sharedLength.compareTo(a.$2.sharedLength);
      return closer != 0 ? closer : a.$1.compareTo(b.$1);
    });
  return [for (final (_, match) in indexed) match];
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
