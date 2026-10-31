import 'address.dart';

/// How the app knows that the user meant to pay an address.
enum RecipientProvenance {
  /// A successful transaction the user signed named this address as the recipient: a native coin
  /// send to it, or a direct `transfer(address,uint256)` call naming it. See
  /// [deriveKnownRecipients].
  sentByOwner,

  /// The user saved or confirmed this address in the app, for example in an address book.
  confirmedByUser,
}

/// An address the user has really chosen to pay, and how the app knows.
///
/// Only the app's own records belong here: the user's signed sends and the user's own
/// confirmations. An address that merely appears in the account's history, because something
/// was sent *to* the user from it or a transfer log names it, does not belong here. That is the
/// exact route an address-poisoning attack uses to get a look-alike in front of the user.
class KnownRecipient {
  /// Throws [FormatException] unless [address] is an EVM address.
  KnownRecipient(String address, this.provenance, {this.label})
    : address = normalizeAddress(address);

  /// Lower case.
  final String address;
  final RecipientProvenance provenance;

  /// The user's own name for the address, if the app has one. Shown on the confirm card.
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is KnownRecipient &&
      other.address == address &&
      other.provenance == provenance &&
      other.label == label;

  @override
  int get hashCode => Object.hash(address, provenance, label);

  @override
  String toString() => 'KnownRecipient($address, ${provenance.name})';
}

/// One transaction the user's own account sent, as the wallet already has it.
///
/// Build it from the transaction itself: the wallet's own record of what it signed and broadcast,
/// or `eth_getTransactionByHash` plus the receipt status. Never build it from a "token transfers"
/// list or from `Transfer` logs. Those name a sender that anyone can forge, which is the
/// poisoning step itself, and a record built from them would let a look-alike pass as a send the
/// owner made. For an ERC-20 payment, [to] is the token contract, [value] is the native value
/// (usually zero) and [input] is the `transfer` calldata.
///
/// Pass the transactions of the chain the payment is on. The same address can belong to a
/// different owner on another chain (a contract or Safe deployed by someone else there), so a
/// recipient paid on one chain is not known on another.
///
/// No network call is made by this package.
class SentTransaction {
  const SentTransaction({
    required this.from,
    required this.to,
    required this.value,
    required this.input,
    required this.succeeded,
  });

  /// The signer, the transaction's own `from`.
  final String from;

  /// The transaction's `to`: the recipient of a native send, or the token contract for an ERC-20
  /// call. Null for a contract creation.
  final String? to;

  /// Native coin value in wei.
  final BigInt value;

  /// The calldata, `0x`-prefixed hex. `0x` or empty for a plain native send.
  final String input;

  /// The receipt status. A reverted transaction moved nothing.
  final bool succeeded;
}

/// The recipients [owner] has really chosen to pay, in first-seen order, deduplicated, each with
/// [RecipientProvenance.sentByOwner].
///
/// A transaction counts only when all of these hold:
///
/// 1. [SentTransaction.from] is [owner]: the user signed it.
/// 2. [SentTransaction.succeeded]: a reverted transaction moved nothing.
/// 3. The recipient is named in what the user signed, in one of two shapes:
///    - a native send: empty calldata, a non-zero [SentTransaction.value] of at least
///      [minNativeValue], and the recipient is [SentTransaction.to];
///    - an ERC-20 transfer: calldata calling `transfer(address,uint256)` directly on
///      [SentTransaction.to], a non-zero amount of at least [minTokenAmount], and the recipient
///      is the address argument.
///
/// Everything else is left out on purpose, and the cost is that its recipients stay first-time
/// recipients:
///
/// - Transfers *to* the owner, and anything read from a token `Transfer` log. A log's `from` is an
///   indexed topic that anyone can make name any account: `transferFrom(victim, lookalike, 0)`
///   emits `Transfer(victim, lookalike, 0)`, which reads like the victim's own send. Counting it
///   would let the attacker enrol a look-alike as a known recipient.
/// - `transferFrom`, `approve`, multisend, Safe and every other contract call. The user signed a
///   call to a contract, and the contract chose where the money went. Signing is not choosing a
///   recipient.
/// - Zero-value sends, whatever the minimums are set to. A zero transfer is not a payment.
///
/// "First-time" is the safe answer to get wrong. "Known" is not.
///
/// Throws [FormatException] if [owner] is not an EVM address. A transaction whose own fields are
/// malformed is skipped, not thrown on: one bad record must not hide the rest.
List<KnownRecipient> deriveKnownRecipients(
  String owner,
  Iterable<SentTransaction> transactions, {
  BigInt? minNativeValue,
  BigInt? minTokenAmount,
}) {
  final signer = normalizeAddress(owner);
  final seen = <String>{};
  final known = <KnownRecipient>[];
  for (final transaction in transactions) {
    final recipient = recipientNamedBy(
      transaction,
      owner: signer,
      minNativeValue: minNativeValue,
      minTokenAmount: minTokenAmount,
    );
    if (recipient == null || !seen.add(recipient)) continue;
    known.add(KnownRecipient(recipient, RecipientProvenance.sentByOwner));
  }
  return known;
}

/// The recipient [owner]'s own signature named in [transaction], lower case, or null when the
/// transaction is not evidence that the owner chose one. The predicate behind
/// [deriveKnownRecipients], exposed so an app can explain a single record.
///
/// A zero value or amount never counts, whatever the minimums are set to.
String? recipientNamedBy(
  SentTransaction transaction, {
  required String owner,
  BigInt? minNativeValue,
  BigInt? minTokenAmount,
}) {
  if (!transaction.succeeded) return null;
  if (!isEvmAddress(transaction.from) || !isEvmAddress(owner)) return null;
  if (normalizeAddress(transaction.from) != normalizeAddress(owner)) {
    return null;
  }
  final to = transaction.to;
  if (to == null || !isEvmAddress(to)) return null;

  final input = transaction.input.toLowerCase();
  if (input.isEmpty || input == '0x') {
    final value = transaction.value;
    if (value < _floor(minNativeValue)) return null;
    return normalizeAddress(to);
  }

  final transfer = decodeErc20Transfer(input);
  if (transfer == null) return null;
  if (transfer.amount < _floor(minTokenAmount)) return null;
  return transfer.recipient;
}

/// A decoded `transfer(address,uint256)` call.
class Erc20TransferCall {
  const Erc20TransferCall(this.recipient, this.amount);

  /// Lower case.
  final String recipient;

  /// In the token's base units.
  final BigInt amount;
}

/// Decodes [calldata] as `transfer(address,uint256)`, or returns null when it is anything else.
///
/// Strict on purpose: the selector `0xa9059cbb`, exactly two 32-byte words and nothing after them,
/// and an address word whose upper 12 bytes are zero. A call that only resembles a transfer is not
/// evidence of a chosen recipient.
Erc20TransferCall? decodeErc20Transfer(String calldata) {
  final hex = calldata.toLowerCase();
  if (!_transferCall.hasMatch(hex)) return null;
  final addressWord = hex.substring(10, 74);
  if (!addressWord.startsWith('0' * 24)) return null;
  final recipient = '0x${addressWord.substring(24)}';
  final amount = BigInt.parse(hex.substring(74, 138), radix: 16);
  return Erc20TransferCall(recipient, amount);
}

final RegExp _transferCall = RegExp(r'^0xa9059cbb[0-9a-f]{128}$');

/// The smallest amount that counts as a send. Never below one: a zero transfer is not a payment.
BigInt _floor(BigInt? minimum) =>
    minimum != null && minimum > BigInt.one ? minimum : BigInt.one;
