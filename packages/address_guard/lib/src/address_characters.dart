import 'address.dart';
import 'lookalike.dart';

/// One of the 40 hex characters of an address, with how a confirm step should show it.
class AddressCharacter {
  const AddressCharacter(
    this.character, {
    required this.inMiddle,
    required this.differs,
  });

  /// The character as given, casing kept: it is what the user compares with the source.
  final String character;

  /// Between the first and last characters people check: the part they skip, so set it in bold.
  final bool inMiddle;

  /// Differs from the address it was compared with: highlight it.
  final bool differs;

  @override
  bool operator ==(Object other) =>
      other is AddressCharacter &&
      other.character == character &&
      other.inMiddle == inMiddle &&
      other.differs == differs;

  @override
  int get hashCode => Object.hash(character, inMiddle, differs);

  @override
  String toString() =>
      'AddressCharacter($character${inMiddle ? ', middle' : ''}${differs ? ', differs' : ''})';
}

/// The 40 characters after `0x` of [address], each marked the way [AddressText] shows it, for an
/// app that draws addresses itself.
///
/// A character is [AddressCharacter.inMiddle] when it lies after the first [prefixLength] and
/// before the last [suffixLength]. With [compareWith], a character is [AddressCharacter.differs]
/// when it differs from the character in the same position there, ignoring case. Show them in
/// groups of four, as [AddressText] does; [AddressGuardStrings.addressSemantics] reads those
/// groups to a screen reader.
///
/// Any lengths are accepted, as [AddressText] always has: below 0 counts as 0 and above 40 as 40,
/// and ends that meet or overlap leave no middle, so nothing is set in bold. Throws
/// [FormatException] unless [address] and [compareWith] are EVM addresses.
List<AddressCharacter> addressCharacters(
  String address, {
  int prefixLength = defaultPrefixLength,
  int suffixLength = defaultSuffixLength,
  String? compareWith,
}) {
  // Clamped first, so even an extreme length cannot overflow `40 - suffixLength`.
  final head = prefixLength.clamp(0, 40);
  final tail = suffixLength.clamp(0, 40);
  // Validates, and keeps the casing the user gave.
  final lower = addressBody(address);
  final body = address.substring(2);
  final other = compareWith == null ? null : addressBody(compareWith);
  return List.unmodifiable([
    for (var index = 0; index < 40; index++)
      AddressCharacter(
        body[index],
        inMiddle: index >= head && index < 40 - tail,
        differs: other != null && other[index] != lower[index],
      ),
  ]);
}
