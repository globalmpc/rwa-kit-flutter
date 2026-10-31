import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/keccak.dart';

final RegExp _addressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');

/// Whether [value] is a 20-byte EVM address: `0x` followed by 40 hex characters, in any casing.
///
/// Leading or trailing whitespace makes it not an address. A wallet that trims pasted text does
/// so before asking, so that a space the user cannot see is never silently accepted.
bool isEvmAddress(String value) => _addressPattern.hasMatch(value);

/// The address in lower case, the form used for every comparison in this package.
///
/// Casing is an EIP-55 checksum, not part of the address: two spellings that differ only in case
/// are the same account. Throws [FormatException] unless [address] is an EVM address.
String normalizeAddress(String address) => _checked(address).toLowerCase();

/// How an address's casing relates to its EIP-55 checksum.
enum ChecksumState {
  /// The exact EIP-55 spelling.
  checksummed,

  /// All lower case or all upper case after the `0x`. It carries no case information, so there
  /// is nothing to verify. All lower case is the form most tools print; all upper case appears in
  /// QR codes. Neither is an error. A scanner that also upper-cases the prefix to `0X` must turn
  /// it back to `0x` first: [isEvmAddress] accepts only `0x`.
  unchecksummed,

  /// The casing carries information and it contradicts the checksum: at least one character was
  /// changed by hand or by a faulty tool. Worth stopping for.
  mismatch,
}

/// The EIP-55 checksummed spelling of [address].
///
/// Keccak-256 of the 40 lower-case hex characters, read as ASCII without the `0x`. Each letter is
/// upper-cased when the hash nibble in the same position is 8 or above. Throws [FormatException]
/// unless [address] is an EVM address.
String toChecksumAddress(String address) {
  final body = _checked(address).substring(2).toLowerCase();
  final digest = _keccak256(ascii.encode(body));
  final out = StringBuffer('0x');
  for (var i = 0; i < 40; i++) {
    final char = body[i];
    // Two hex digits per byte, high nibble first, so character i reads byte i >> 1.
    final byte = digest[i >> 1];
    final nibble = i.isEven ? byte >> 4 : byte & 0x0f;
    out.write(nibble >= 8 ? char.toUpperCase() : char);
  }
  return out.toString();
}

/// Classifies the casing of [address]. Throws [FormatException] unless it is an EVM address.
ChecksumState checksumState(String address) {
  _checked(address);
  if (address == toChecksumAddress(address)) return ChecksumState.checksummed;
  final body = address.substring(2);
  if (body == body.toLowerCase() || body == body.toUpperCase()) {
    return ChecksumState.unchecksummed;
  }
  return ChecksumState.mismatch;
}

/// Whether the casing of [value] is acceptable: the exact checksummed spelling, or a single case
/// throughout, which carries no checksum to contradict (EIP-55). Use [checksumState] to tell
/// "unchecksummed" and "wrong" apart.
bool isValidChecksum(String value) =>
    isEvmAddress(value) && checksumState(value) != ChecksumState.mismatch;

/// The 40 lower-case hex characters after `0x`.
String addressBody(String address) => normalizeAddress(address).substring(2);

String _checked(String address) {
  if (!isEvmAddress(address)) {
    throw FormatException(
      'not a 20-byte EVM address (expected 0x followed by 40 hex characters)',
      address,
    );
  }
  return address;
}

Uint8List _keccak256(Uint8List input) => KeccakDigest(256).process(input);
