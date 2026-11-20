import 'address.dart';
import 'history.dart';
import 'known_recipients.dart';

/// The two lists of an Etherscan-compatible account API that this package reads, named after the
/// API's `action` parameter.
///
/// Etherscan API V2 serves this format for every chain it covers (BNB Smart Chain included, with
/// `chainid=56`), and Blockscout explorers serve it at their own `/api` path. Fields are read as
/// the strings these APIs send; amounts come as strings because a large one does not survive as a
/// JSON number. History APIs with other shapes, such as NodeReal's `nr_getAssetTransfers`, are not
/// read here.
enum ExplorerList {
  /// `action=txlist`: the account's transactions, sent and received. Each row is a transaction
  /// itself, so its `from` is the signer.
  txlist,

  /// `action=tokentx`: the account's ERC-20 token transfers, in and out. Each row is read from a
  /// `Transfer` log, whose `from` anyone can make name any account.
  tokentx,
}

/// The [SentTransaction] for one row of [ExplorerList.txlist], or null when a field the record
/// needs is missing or malformed.
///
/// Give it every row the API returns for the account, sent and received: [deriveKnownRecipients]
/// keeps only the owner's own successful sends. [SentTransaction.succeeded] holds only when the
/// row's `isError` is `"0"` and its `txreceipt_status` is `"1"`. Anything else, an empty status
/// included, is not success: "first-time" is the safe answer to get wrong, "known" is not. (On
/// Ethereum that leaves out the recipients of sends from before 2017's Byzantium fork, whose
/// receipts carry no status.) For a contract creation, whose `to` is empty or null, the record's
/// [SentTransaction.to] is null.
///
/// Throws [ArgumentError] for a row from another list: one with token fields or without the
/// `isError` field every `txlist` row carries, as a row of [ExplorerList.tokentx] is, or one with
/// the `errCode` or `traceId` of an internal transaction (`txlistinternal`), whose sender is a
/// contract. A token row's `from` comes from a `Transfer` log, which is the poisoning step itself:
/// a record built from it would let a planted look-alike pass as a payment the owner made. That is
/// a wiring mistake, not bad data, so it is not skipped quietly. Give token rows to
/// [historyTransferFromExplorer]. A row with no `nonce`, which every signed transaction has, is bad
/// data and returns null.
///
/// Pure: the app fetches the rows, this only reads them.
SentTransaction? sentTransactionFromExplorer(Map<String, Object?> row) {
  _requireTransactionRow(
    row,
    'only ExplorerList.txlist rows describe what the owner signed',
  );
  // Every transaction the owner signed has a nonce. Without one, nothing says it was signed.
  if (_text(row, 'nonce') == null) return null;
  final from = _address(row, 'from');
  // A contract creation names no one: its `to` is empty or null, and the record's `to` is null.
  final rawTo = row['to'];
  final creation = row.containsKey('to') && (rawTo == null || rawTo == '');
  final to = creation ? null : _address(row, 'to');
  final value = _amount(row, 'value');
  final input = _text(row, 'input');
  final outcome = _outcome(row);
  if (from == null ||
      (to == null && !creation) ||
      value == null ||
      input == null ||
      outcome == null) {
    return null;
  }
  return SentTransaction(
    from: from,
    to: to,
    value: value,
    input: input,
    succeeded: outcome.isError == '0' && outcome.status == '1',
  );
}

/// The [HistoryTransfer] for one row of [list], or null when the row is a contract creation or
/// has no readable sender, recipient or amount.
///
/// - [ExplorerList.tokentx]: a transfer of the token at the row's `contractAddress`, `value` base
///   units from `from` to `to`. Zero-value and counterfeit-token rows are kept: they are the
///   poisoning transfers [screenHistory] looks for. A row that names a `tokenID` or `tokenValue`
///   is an NFT transfer, kept so its sender is screened too; its amount is the `tokenValue`
///   count, or one.
/// - [ExplorerList.txlist]: a native-coin transfer of the row's `value` from `from` to `to`,
///   whatever its calldata, so a look-alike that sends the account a transaction is screened. The
///   account's own contract calls become entries too, but [screenHistory] never flags a native
///   send from the account, so they cannot raise an alarm. Failed transactions are kept, since a
///   wallet still lists them and an address can be copied from there, with an amount of zero:
///   a reverted transaction moved nothing.
///
/// This path only raises alarms, so it drops as little as it can: a row is null only when its
/// `from` or `to` is missing or not an address, or its amount is missing or not a decimal number
/// (a failed transaction needs none), since then there is nothing to compare. A
/// `txreceipt_status` that is missing, or an `isError` or status that is not text, leaves the
/// amount as given; a row with no `isError` at all is not a transaction row, below. A missing or
/// malformed token address is passed on as text that is not an address, so [screenHistory] still
/// screens the row and counts the token as one the wallet does not list.
///
/// Throws [ArgumentError] when the row does not fit [list]: under [ExplorerList.txlist], a row
/// with token fields or without the `isError` field every transaction row carries; under
/// [ExplorerList.tokentx], a transaction row; under either, an internal transaction (one with
/// `errCode` or `traceId`). Every row read under the wrong list would be lost or
/// misread, so the mistake is reported, not skipped.
///
/// Pure: the app fetches the rows, this only reads them.
HistoryTransfer? historyTransferFromExplorer(
  Map<String, Object?> row,
  ExplorerList list,
) {
  switch (list) {
    case ExplorerList.txlist:
      // A token row read here would name a forged sender as a native send: refuse anything that
      // is not plainly a transaction, even a token row without its token fields.
      _requireTransactionRow(
        row,
        'read a token transfer row as ExplorerList.tokentx',
      );
      // A reverted transaction moved nothing, whatever value it carried. An outcome the row does
      // not state leaves the value as given: this path only raises alarms, so it keeps the row.
      final failed =
          _text(row, 'isError') == '1' || _text(row, 'txreceipt_status') == '0';
      // A failed row needs no readable value: it moved nothing.
      return _transfer(
        row,
        token: null,
        amount: failed ? BigInt.zero : _amount(row, 'value'),
      );
    case ExplorerList.tokentx:
      _refuseInternal(row);
      if (_isTransactionRow(row)) {
        throw ArgumentError.value(
          row['hash'],
          'row',
          'is a transaction row; read it as ExplorerList.txlist',
        );
      }
      // The token's name, symbol and decimals are not needed: a counterfeit that has none must
      // still be screened.
      // A token field that is missing or not an address is passed on as text that is not an
      // address, never as null: null means the native coin, and screenHistory never flags a
      // native send from the owner, which is exactly what a forged log claims to be. As text it
      // is screened, and counts as a token the wallet does not list.
      return _transfer(
        row,
        token: _text(row, 'contractAddress') ?? '',
        amount: _isNftRow(row)
            ? _amount(row, 'tokenValue') ?? BigInt.one
            : _amount(row, 'value'),
      );
  }
}

HistoryTransfer? _transfer(
  Map<String, Object?> row, {
  required String? token,
  required BigInt? amount,
}) {
  final from = _address(row, 'from');
  // An empty `to` is a contract creation, which pays no one.
  final to = _address(row, 'to');
  if (from == null || to == null || amount == null) return null;
  return HistoryTransfer(from: from, to: to, amount: amount, token: token);
}

/// Throws unless [row] is a `txlist` row: every one carries `isError`, no token transfer row does
/// or has token fields, and it is not an internal transaction. The one place that rule lives.
void _requireTransactionRow(Map<String, Object?> row, String hint) {
  _refuseInternal(row);
  if (_isTransactionRow(row)) return;
  throw ArgumentError.value(
    row['hash'],
    'row',
    'is not a txlist row (it has no isError, or has token fields); $hint',
  );
}

/// Whether [row] is shaped like a `txlist` row: every one carries `isError`, and no token
/// transfer row does or has token fields.
bool _isTransactionRow(Map<String, Object?> row) =>
    row.containsKey('isError') && !_isTokenRow(row);

/// Throws for a row of `action=txlistinternal`: a call made inside a transaction, by a contract.
/// Etherscan marks those rows with `traceId` and Blockscout with `index`; both give them an
/// `errCode`, which no `txlist` or token row has.
void _refuseInternal(Map<String, Object?> row) {
  if (!row.containsKey('errCode') && !row.containsKey('traceId')) return;
  throw ArgumentError.value(
    row['hash'] ?? row['transactionHash'],
    'row',
    'is an internal transaction (action=txlistinternal), which this package does not read: '
        'its sender is a contract, not a signer',
  );
}

/// The row's `isError` and `txreceipt_status`, or null when either is missing or not text.
({String isError, String status})? _outcome(Map<String, Object?> row) {
  final isError = _text(row, 'isError');
  final status = _text(row, 'txreceipt_status');
  if (isError == null || status == null) return null;
  return (isError: isError, status: status);
}

/// Rows of the token lists carry the token's name, symbol and decimals; transaction rows never do.
bool _isTokenRow(Map<String, Object?> row) =>
    row.containsKey('tokenDecimal') ||
    row.containsKey('tokenSymbol') ||
    row.containsKey('tokenName');

/// An NFT transfer names the item it moved. Its `value`, where there is one, is not an amount: an
/// ERC-1155 row counts items in `tokenValue`, an ERC-721 row moves one.
bool _isNftRow(Map<String, Object?> row) =>
    _filled(row, 'tokenID') || _filled(row, 'tokenValue');

/// Whether [key] holds a value: some APIs send an NFT field on every row, empty or null on the
/// fungible ones.
bool _filled(Map<String, Object?> row, String key) {
  final value = row[key];
  return value != null && value != '';
}

/// The value of [key] when it is an EVM address, as given.
String? _address(Map<String, Object?> row, String key) {
  final value = _text(row, key);
  return value != null && isEvmAddress(value) ? value : null;
}

String? _text(Map<String, Object?> row, String key) {
  final value = row[key];
  return value is String ? value : null;
}

/// A decimal amount, as these APIs write wei and token base units. Signs, hex and blanks are not
/// amounts.
BigInt? _amount(Map<String, Object?> row, String key) {
  final value = _text(row, key);
  if (value == null || !_digits.hasMatch(value)) return null;
  return BigInt.parse(value);
}

final RegExp _digits = RegExp(r'^[0-9]+$');
