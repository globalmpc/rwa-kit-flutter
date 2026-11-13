import 'address.dart';
import 'known_recipients.dart';
import 'lookalike.dart';

/// One transfer as the wallet shows it in the account's activity list.
///
/// This is the data [deriveKnownRecipients] refuses to trust: token `Transfer` logs, an indexer's
/// "token transfers" list, incoming payments. It is safe here because [screenHistory] only uses it
/// to raise an alarm, never to make an address known.
class HistoryTransfer {
  const HistoryTransfer({
    required this.from,
    required this.to,
    required this.amount,
    this.token,
  });

  /// The sender the record names. For a token transfer this is the log's `from`, which anyone can
  /// make name any account.
  final String from;

  final String to;

  /// In the token's base units, or in wei for the native coin.
  final BigInt amount;

  /// The token contract, or null for the chain's native coin.
  final String? token;
}

/// What makes a [PoisoningSuspect] look like a poisoning transfer, beyond the look-alike itself.
/// The 2025 measurement of 270 million poisoning transfers found three kinds: zero-value
/// transfers (55%), counterfeit tokens (44%) and tiny amounts (1.5%).
enum PoisoningSign {
  /// An amount of zero. A zero-value `transferFrom` needs no approval, so an attacker can make a
  /// log that shows the owner paying the look-alike.
  zeroValue,

  /// An amount the app judged too small to be a real payment, through `isDust`.
  dust,

  /// A token missing from the app's `listedTokens`. Counterfeit tokens copy a real token's name
  /// and symbol, but cannot copy its contract address.
  unlistedToken,

  /// A token transfer record that names the owner as the sender of a payment to the look-alike. A
  /// forged log reads exactly like this, though so does a real send the owner's known recipients
  /// leave out (one below `minTokenAmount`, for example). Never set for the native coin, whose
  /// sender cannot be forged.
  namesOwnerAsSender,
}

/// A history entry that looks like an address-poisoning attempt.
class PoisoningSuspect {
  const PoisoningSuspect({
    required this.index,
    required this.transfer,
    required this.counterparty,
    required this.imitates,
    required this.signs,
  });

  /// The entry's position in the list given to [screenHistory].
  final int index;
  final HistoryTransfer transfer;

  /// The other side of the transfer, lower case: the look-alike.
  final String counterparty;

  /// The known recipients it imitates, closest copy first. Never empty.
  final List<LookalikeMatch> imitates;

  /// The signs found, in the order of [PoisoningSign]. Can be empty: a look-alike of a known
  /// recipient is suspect on its own.
  final List<PoisoningSign> signs;

  @override
  String toString() =>
      'PoisoningSuspect(#$index, $counterparty, ${signs.map((sign) => sign.name).join(', ')})';
}

/// The entries of [owner]'s history that look like address poisoning, so the wallet can hide them,
/// mark them, or refuse to let the user copy the address from them.
///
/// An entry is a suspect when its counterparty, the side that is not [owner], imitates one of the
/// [known] recipients: at least [prefixLength] and [suffixLength] characters in common at the ends,
/// a different middle. A counterparty the owner has really paid
/// ([RecipientProvenance.sentByOwner]) is never a suspect. One that is only saved
/// ([RecipientProvenance.confirmedByUser]) is still a suspect: a look-alike copied from the
/// history into the address book is the attack succeeding. So two saved addresses that resemble
/// each other flag each other's entries. Nothing says which one is real, and a false alarm is the
/// safe mistake. The [signs] add
/// what else looks wrong, for the message the user sees: [PoisoningSign.zeroValue] always,
/// [PoisoningSign.unlistedToken] when [listedTokens] is given, [PoisoningSign.dust] when [isDust]
/// is given, and [PoisoningSign.namesOwnerAsSender] when the record names [owner] as the sender.
///
/// Pass the result to [assessRecipient] as `suspects`, so an address copied from one of these
/// entries is stopped at the confirm card too, with the addresses it imitates:
///
/// ```dart
/// final suspects = screenHistory(account, activity, known: known);
/// final check = assessRecipient(input, known: known, suspects: suspects);
/// ```
///
/// A native-coin entry from [owner] is never a suspect: its sender cannot be forged, so the owner
/// really sent it. An entry that does not involve [owner], names [owner] on both sides, or has a
/// field that is not an address is skipped, not thrown on: one bad record must not hide the rest.
/// Throws [FormatException] if [owner] or an entry of [listedTokens] is not an EVM address (a
/// mistyped token list would call every real token fake), and [ArgumentError] for a comparison
/// window that leaves no middle. [isDust] is called once for each suspect with a non-zero
/// amount; if it throws, so does this function. Pass the transfers of one account on one chain.
/// Pure: no I/O.
List<PoisoningSuspect> screenHistory(
  String owner,
  Iterable<HistoryTransfer> transfers, {
  required Iterable<KnownRecipient> known,
  Iterable<String>? listedTokens,
  bool Function(HistoryTransfer transfer)? isDust,
  int prefixLength = defaultPrefixLength,
  int suffixLength = defaultSuffixLength,
}) {
  checkWindow(prefixLength, suffixLength);
  final account = normalizeAddress(owner);
  // Read once: `known` may be an iterable that cannot be read twice.
  final knownList = known.toList(growable: false);
  final knownAddresses = {for (final entry in knownList) entry.address};
  final paid = {
    for (final entry in knownList)
      if (entry.provenance == RecipientProvenance.sentByOwner) entry.address,
  };
  // A poisoner usually plants several entries; compare each counterparty once.
  final compared = <String, List<LookalikeMatch>>{};
  final listed = listedTokens?.map(normalizeAddress).toSet();

  final suspects = <PoisoningSuspect>[];
  for (final (index, transfer) in transfers.indexed) {
    final counterparty = _counterparty(transfer, account);
    if (counterparty == null || paid.contains(counterparty)) {
      continue;
    }
    // A native send from the owner was signed by the owner: whatever it is, it was not planted.
    if (transfer.token == null && normalizeAddress(transfer.from) == account) {
      continue;
    }
    final imitates = compared.putIfAbsent(
      counterparty,
      () => List.unmodifiable(
        findLookalikes(
          counterparty,
          knownAddresses,
          prefixLength: prefixLength,
          suffixLength: suffixLength,
        ),
      ),
    );
    if (imitates.isEmpty) continue;
    final token = transfer.token;
    suspects.add(
      PoisoningSuspect(
        index: index,
        transfer: transfer,
        counterparty: counterparty,
        imitates: imitates,
        signs: List.unmodifiable([
          if (transfer.amount == BigInt.zero) PoisoningSign.zeroValue,
          if (transfer.amount > BigInt.zero &&
              (isDust?.call(transfer) ?? false))
            PoisoningSign.dust,
          // A token field that is not an address cannot be a listed token.
          if (token != null &&
              listed != null &&
              !(isEvmAddress(token) &&
                  listed.contains(normalizeAddress(token))))
            PoisoningSign.unlistedToken,
          if (token != null && normalizeAddress(transfer.from) == account)
            PoisoningSign.namesOwnerAsSender,
        ]),
      ),
    );
  }
  return suspects;
}

/// The side of [transfer] that is not [account], lower case, or null when the entry is malformed
/// or does not involve [account] exactly once. The token field is not checked here: a look-alike
/// counterparty must raise the alarm even when the record's token field is malformed.
String? _counterparty(HistoryTransfer transfer, String account) {
  if (!isEvmAddress(transfer.from) ||
      !isEvmAddress(transfer.to) ||
      transfer.amount.isNegative) {
    return null;
  }
  final from = normalizeAddress(transfer.from);
  final to = normalizeAddress(transfer.to);
  if (from == account && to != account) return to;
  if (to == account && from != account) return from;
  return null;
}
