/// Catch address-poisoning look-alikes before a Flutter wallet sends.
///
/// Build the user's known recipients with [deriveKnownRecipients] from the transactions they
/// signed (plus your own address book as [RecipientProvenance.confirmedByUser]), judge a
/// destination with [assessRecipient], and show the result with [RecipientConfirmCard]. Check the
/// returned [ConfirmedRecipient] against the transaction with [ConfirmedRecipient.matches] just
/// before signing. Mark the poisoning transfers in the account's activity list with
/// [screenHistory], so the user is warned before copying an address from there.
///
/// Reading an Etherscan-compatible explorer API? [sentTransactionFromExplorer] and
/// [historyTransferFromExplorer] turn its rows into the records above. Drawing the confirm step
/// in your own design system? [RecipientConfirmBuilder] gives you the card's rules without its
/// look.
library;

export 'src/acknowledgement.dart' show RecipientAcknowledgement;
export 'src/address.dart'
    show
        ChecksumState,
        checksumState,
        isEvmAddress,
        isValidChecksum,
        normalizeAddress,
        toChecksumAddress;
export 'src/address_characters.dart' show AddressCharacter, addressCharacters;
export 'src/assess.dart'
    show RecipientCheck, RecipientReason, RecipientVerdict, assessRecipient;
export 'src/confirm_builder.dart'
    show RecipientConfirmBuilder, RecipientConfirmState;
export 'src/confirm_card.dart' show AddressText, RecipientConfirmCard;
export 'src/confirmed_recipient.dart' show ConfirmedRecipient;
export 'src/explorer.dart'
    show ExplorerList, historyTransferFromExplorer, sentTransactionFromExplorer;
export 'src/history.dart'
    show HistoryTransfer, PoisoningSign, PoisoningSuspect, screenHistory;
export 'src/known_recipients.dart'
    show
        Erc20TransferCall,
        KnownRecipient,
        RecipientProvenance,
        SentTransaction,
        decodeErc20Transfer,
        deriveKnownRecipients,
        recipientNamedBy;
export 'src/lookalike.dart'
    show
        LookalikeMatch,
        MatchSource,
        defaultPrefixLength,
        defaultSuffixLength,
        findLookalikes;
export 'src/strings.dart'
    show AddressGuardStrings, AddressGuardStringsAcknowledgement;
