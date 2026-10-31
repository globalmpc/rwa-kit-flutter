import 'package:address_guard/address_guard.dart';

// Synthetic addresses only. None belongs to a real account the tests depend on.

/// The owner whose sends the tests replay.
const owner = '0x1111111111111111111111111111111111111111';

/// A recipient the owner really paid.
const paid = '0xa1b2c3d4e5f60718293a4b5c6d7e8f9012345678';

/// The look-alike an attacker would generate for [paid]: same first and last four, new middle.
const poison = '0xa1b2ffffffffffffffffffffffffffffffff5678';

/// A token contract.
const token = '0x2222222222222222222222222222222222222222';

/// Calldata for `transfer(recipient, amount)`.
String transferCalldata(String recipient, BigInt amount) =>
    '0xa9059cbb'
    '${'0' * 24}${recipient.substring(2).toLowerCase()}'
    '${amount.toRadixString(16).padLeft(64, '0')}';

/// A successful transaction the owner signed.
SentTransaction sent({
  String from = owner,
  String? to,
  BigInt? value,
  String input = '0x',
  bool succeeded = true,
}) => SentTransaction(
  from: from,
  to: to,
  value: value ?? BigInt.zero,
  input: input,
  succeeded: succeeded,
);

/// A native send of one wei-unit amount to [recipient].
SentTransaction nativeSend(String recipient, {BigInt? value}) =>
    sent(to: recipient, value: value ?? BigInt.from(1000));

/// An ERC-20 transfer of [amount] to [recipient], called directly on [token].
SentTransaction tokenTransfer(String recipient, {BigInt? amount}) => sent(
  to: token,
  input: transferCalldata(recipient, amount ?? BigInt.from(500)),
);

/// [address] with the character at [index] (counted after `0x`) replaced by another hex digit.
String mutateAt(String address, int index) {
  final body = address.substring(2).toLowerCase().split('');
  body[index] = body[index] == 'a' ? 'b' : 'a';
  return '0x${body.join()}';
}

/// [address] with the case of its first letter after `0x` flipped: the same account, with
/// casing that no longer matches the checksum when [address] is checksummed.
String flipFirstLetter(String address) {
  final index = address.indexOf(RegExp('[a-fA-F]'), 2);
  final char = address[index];
  final flipped = char == char.toUpperCase()
      ? char.toLowerCase()
      : char.toUpperCase();
  return address.replaceRange(index, index + 1, flipped);
}
