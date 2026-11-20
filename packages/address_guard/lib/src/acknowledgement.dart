/// The tick a confirm step asks for before the user can confirm.
enum RecipientAcknowledgement {
  /// A first-time recipient: the user checked the full address with the person they are paying.
  checkedFullAddress,

  /// A look-alike or altered address, with an override allowed: the user checked every character
  /// and still wants to pay it.
  override,
}
