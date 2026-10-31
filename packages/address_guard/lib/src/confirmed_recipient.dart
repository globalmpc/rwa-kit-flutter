import 'address.dart';
import 'assess.dart';

/// What the user confirmed on a [RecipientConfirmCard]: one exact address on one exact chain.
///
/// Check it against the transaction just before signing with [matches]. If the address or the
/// chain changed after the user looked, for example because a field was edited or the clipboard
/// was replaced, the confirmation no longer applies and the user must confirm again.
class ConfirmedRecipient {
  /// Throws [FormatException] unless [address] is an EVM address.
  ConfirmedRecipient({
    required String address,
    required this.chainId,
    required this.verdict,
  }) : address = toChecksumAddress(address);

  /// The EIP-55 spelling of the address that was shown.
  final String address;
  final int chainId;

  /// The verdict the user saw when confirming.
  final RecipientVerdict verdict;

  /// Whether a payment to [recipient] on [onChainId] is the one the user confirmed. Casing is
  /// ignored, because it is a checksum and not part of the address.
  bool matches(String recipient, int onChainId) =>
      onChainId == chainId &&
      isEvmAddress(recipient) &&
      normalizeAddress(recipient) == normalizeAddress(address);

  @override
  String toString() =>
      'ConfirmedRecipient($address, chain $chainId, ${verdict.name})';
}
