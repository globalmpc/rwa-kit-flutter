import 'dart:convert';

import 'package:address_guard/address_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Rows in the Etherscan-compatible format (Etherscan API V2, Blockscout): every value a string.

/// A row of `action=txlist`.
Map<String, Object?> txRow({
  String from = owner,
  String to = paid,
  String value = '1000',
  String input = '0x',
  String isError = '0',
  String status = '1',
  String hash = 'ab',
  int time = 1700000000,
}) => {
  'blockNumber': '19000000',
  'timeStamp': '$time',
  'hash': '0x${hash * 32}',
  'nonce': '7',
  'from': from,
  'to': to,
  'value': value,
  'input': input,
  'isError': isError,
  'txreceipt_status': status,
  'contractAddress': '',
  'methodId': input.length >= 10 ? input.substring(0, 10) : '0x',
};

/// A row of `action=tokentx`. Its `input` is the calldata of the transaction that emitted the log,
/// as Blockscout returns it, which is why a token row is never read as a transaction.
Map<String, Object?> tokenRow({
  String from = owner,
  String to = paid,
  String value = '0',
  String contract = token,
  String hash = 'cd',
  int time = 1700000000,
}) => {
  'blockNumber': '19000001',
  'timeStamp': '$time',
  'hash': '0x${hash * 32}',
  'from': from,
  'to': to,
  'value': value,
  'contractAddress': contract,
  'tokenName': 'Tether USD',
  'tokenSymbol': 'USDT',
  'tokenDecimal': '18',
  'input': '0x23b872dd${'0' * 192}',
};

void main() {
  group('sentTransactionFromExplorer', () {
    test('a native send the owner signed makes its recipient known', () {
      final sent = sentTransactionFromExplorer(txRow())!;
      expect(sent.from, owner);
      expect(sent.to, paid);
      expect(sent.value, BigInt.from(1000));
      expect(sent.succeeded, isTrue);
      expect(deriveKnownRecipients(owner, [sent]).single.address, paid);
    });

    test(
      'a token transfer the owner signed names the recipient in its calldata',
      () {
        final sent = sentTransactionFromExplorer(
          txRow(
            to: token,
            value: '0',
            input: transferCalldata(paid, BigInt.from(5000000)),
          ),
        )!;
        expect(deriveKnownRecipients(owner, [sent]).single.address, paid);
      },
    );

    test('a failed transaction is not a payment', () {
      for (final row in [txRow(isError: '1'), txRow(status: '0')]) {
        final sent = sentTransactionFromExplorer(row)!;
        expect(sent.succeeded, isFalse);
        expect(deriveKnownRecipients(owner, [sent]), isEmpty);
      }
    });

    test('an empty status is not success: "known" is the mistake to avoid', () {
      final sent = sentTransactionFromExplorer(txRow(status: ''))!;
      expect(sent.succeeded, isFalse);
      expect(deriveKnownRecipients(owner, [sent]), isEmpty);
    });

    test('a contract creation has no recipient, written empty or null', () {
      for (final row in [
        txRow(to: ''),
        {...txRow(), 'to': null},
      ]) {
        final sent = sentTransactionFromExplorer(row)!;
        expect(sent.to, isNull);
        expect(deriveKnownRecipients(owner, [sent]), isEmpty);
      }
      // A row with no `to` field at all is malformed, not a creation.
      expect(sentTransactionFromExplorer({...txRow()}..remove('to')), isNull);
    });

    test('a transaction received from someone else never makes them known', () {
      final sent = sentTransactionFromExplorer(txRow(from: paid, to: owner))!;
      expect(deriveKnownRecipients(owner, [sent]), isEmpty);
    });

    test(
      'a row with a missing or malformed field is skipped, not thrown on',
      () {
        final malformed = <Map<String, Object?>>[
          {...txRow()}..remove('value'),
          {...txRow()}..remove('txreceipt_status'),
          {...txRow()}..remove('input'),
          txRow(value: '0x3e8'),
          txRow(value: '-1'),
          txRow(value: ''),
          txRow(value: '1.5'),
          {...txRow(), 'value': 1000},
          {...txRow(), 'from': null},
          txRow(from: '0x123'),
          txRow(to: 'pending'),
        ];
        for (final row in malformed) {
          expect(sentTransactionFromExplorer(row), isNull, reason: '$row');
        }
      },
    );

    test('refuses an internal transaction; skips a row with no nonce as bad data', () {
      // A txlistinternal row: a trace inside a transaction, sent by a contract.
      final internal = {...txRow()}
        ..remove('nonce')
        ..remove('txreceipt_status')
        ..['traceId'] = '0_1'
        ..['type'] = 'call';
      expect(() => sentTransactionFromExplorer(internal), throwsArgumentError);
      expect(
        () => sentTransactionFromExplorer({...txRow(), 'traceId': '0_1'}),
        throwsArgumentError,
      );
      // A row with no nonce is bad data, not a wiring mistake: skipped, so it cannot take the
      // rest of the account's known recipients down with it.
      expect(
        sentTransactionFromExplorer({...txRow()}..remove('nonce')),
        isNull,
      );
      // The history path refuses internal rows too, under either list: both readers agree.
      expect(
        () => historyTransferFromExplorer(internal, ExplorerList.txlist),
        throwsArgumentError,
      );
      // Blockscout's internal rows, as its API returns them: an `index` and an `errCode`,
      // no `traceId`, no `nonce`, the hash under `transactionHash`.
      final blockscoutInternal = <String, Object?>{
        'blockNumber': '19000000',
        'callType': 'call',
        'contractAddress': '',
        'errCode': '',
        'from': token,
        'gas': '2300',
        'gasUsed': '0',
        'index': '0',
        'input': '0x',
        'isError': '0',
        'timeStamp': '1700000000',
        'to': owner,
        'transactionHash': '0x${'ef' * 32}',
        'type': 'call',
        'value': '1',
      };
      for (final read in [
        () => sentTransactionFromExplorer(blockscoutInternal),
        () => historyTransferFromExplorer(
          blockscoutInternal,
          ExplorerList.txlist,
        ),
        () => historyTransferFromExplorer(
          blockscoutInternal,
          ExplorerList.tokentx,
        ),
      ]) {
        expect(
          read,
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains('internal transaction'),
            ),
          ),
        );
      }
    });

    test('refuses a token transfer row, whose sender anyone can forge', () {
      // transferFrom(owner, poison, 0): the log names the owner as the sender, though the
      // attacker sent it. Read as a transaction, it would make the look-alike a known recipient.
      final bare = tokenRow(to: poison)
        ..remove('tokenName')
        ..remove('tokenSymbol')
        ..remove('tokenDecimal');
      for (final row in [tokenRow(to: poison), bare]) {
        expect(() => sentTransactionFromExplorer(row), throwsArgumentError);
      }
      // A transaction row is one with isError; without it, nothing says the row was signed.
      expect(
        () => sentTransactionFromExplorer({...txRow()}..remove('isError')),
        throwsArgumentError,
      );
    });
  });

  group('historyTransferFromExplorer', () {
    test('a token row becomes a transfer of that token', () {
      final transfer = historyTransferFromExplorer(
        tokenRow(to: poison),
        ExplorerList.tokentx,
      )!;
      expect(transfer.from, owner);
      expect(transfer.to, poison);
      expect(transfer.amount, BigInt.zero);
      expect(transfer.token, token);
    });

    test('a native send becomes a native-coin transfer', () {
      final transfer = historyTransferFromExplorer(
        txRow(from: poison, to: owner, value: '1'),
        ExplorerList.txlist,
      )!;
      expect(transfer.from, poison);
      expect(transfer.amount, BigInt.one);
      expect(transfer.token, isNull);
    });

    test(
      'the account\'s own contract call is an entry that never raises an alarm',
      () {
        // A token contract that happens to share the ends of a paid recipient.
        const lookalikeContract = '0xa1b2000000000000000000000000000000005678';
        final transfer = historyTransferFromExplorer(
          txRow(
            to: lookalikeContract,
            value: '0',
            input: transferCalldata(paid, BigInt.one),
          ),
          ExplorerList.txlist,
        )!;
        expect(transfer.token, isNull);
        expect(
          screenHistory(
            owner,
            [transfer],
            known: [KnownRecipient(paid, RecipientProvenance.sentByOwner)],
          ),
          isEmpty,
        );
      },
    );

    test(
      'a look-alike\'s transaction to the account is screened, calldata or not',
      () {
        final transfer = historyTransferFromExplorer(
          txRow(from: poison, to: owner, value: '0', input: '0xdeadbeef'),
          ExplorerList.txlist,
        )!;
        final suspects = screenHistory(
          owner,
          [transfer],
          known: [KnownRecipient(paid, RecipientProvenance.sentByOwner)],
        );
        expect(suspects.single.counterparty, poison);
        expect(suspects.single.signs, [PoisoningSign.zeroValue]);
      },
    );

    test('a token row with no name, symbol or decimals is still read', () {
      final row = tokenRow(to: poison)
        ..remove('tokenName')
        ..remove('tokenSymbol')
        ..remove('tokenDecimal');
      expect(
        historyTransferFromExplorer(row, ExplorerList.tokentx)?.token,
        token,
      );
    });

    test(
      'a failed send is kept, since the wallet still lists it, and moved nothing',
      () {
        for (final row in [
          txRow(from: poison, to: owner, value: '1', isError: '1'),
          txRow(from: poison, to: owner, value: '1', status: '0'),
        ]) {
          final transfer = historyTransferFromExplorer(
            row,
            ExplorerList.txlist,
          )!;
          expect(transfer.amount, BigInt.zero);
          final suspects = screenHistory(
            owner,
            [transfer],
            known: [KnownRecipient(paid, RecipientProvenance.sentByOwner)],
          );
          expect(suspects.single.signs, [PoisoningSign.zeroValue]);
        }
      },
    );

    test('a row with a missing or malformed field is skipped, not thrown on', () {
      // Only rows with no readable sender, recipient or amount: nothing to compare.
      final malformed = <(Map<String, Object?>, ExplorerList)>[
        ({...tokenRow()}..remove('value'), ExplorerList.tokentx),
        (tokenRow(value: 'abc'), ExplorerList.tokentx),
        ({...tokenRow(), 'to': 7}, ExplorerList.tokentx),
        (txRow(to: ''), ExplorerList.txlist),
        (txRow(from: '0x12'), ExplorerList.txlist),
        (tokenRow(to: 'not an address'), ExplorerList.tokentx),
        (txRow(value: '-5'), ExplorerList.txlist),
      ];
      for (final (row, list) in malformed) {
        expect(historyTransferFromExplorer(row, list), isNull, reason: '$row');
      }
    });

    test(
      'an unreadable outcome keeps the row and its value: alarms drop as little as they can',
      () {
        for (final row in [
          {...txRow(from: poison, to: owner, value: '7'), 'isError': 1},
          {...txRow(from: poison, to: owner, value: '7')}
            ..remove('txreceipt_status'),
        ]) {
          expect(
            historyTransferFromExplorer(row, ExplorerList.txlist)?.amount,
            BigInt.from(7),
            reason: '$row',
          );
        }
      },
    );

    test(
      'a forged log with no token address is still screened, never read as native',
      () {
        // Null would mean the native coin, and a native send from the owner is never a suspect.
        for (final row in [
          tokenRow(to: poison, contract: ''),
          {...tokenRow(to: poison)}..remove('contractAddress'),
        ]) {
          final transfer = historyTransferFromExplorer(
            row,
            ExplorerList.tokentx,
          )!;
          expect(transfer.token, isNotNull);
          final suspects = screenHistory(
            owner,
            [transfer],
            known: [KnownRecipient(paid, RecipientProvenance.sentByOwner)],
            listedTokens: [token],
          );
          expect(suspects.single.signs, [
            PoisoningSign.zeroValue,
            PoisoningSign.unlistedToken,
            PoisoningSign.namesOwnerAsSender,
          ]);
        }
      },
    );

    test(
      'an NFT row is kept so its sender is screened, with a count as its amount',
      () {
        // An ERC-721 row: its value, where there is one, is not an amount. It moves one item.
        final erc721 = historyTransferFromExplorer({
          ...tokenRow(from: poison, to: owner, value: '42'),
          'tokenID': '42',
        }, ExplorerList.tokentx)!;
        expect(erc721.amount, BigInt.one);
        // An ERC-1155 row counts its items in tokenValue.
        final erc1155 = historyTransferFromExplorer({
          ...tokenRow(from: poison, to: owner)..remove('value'),
          'tokenID': '7',
          'tokenValue': '3',
        }, ExplorerList.tokentx)!;
        expect(erc1155.amount, BigInt.from(3));
        expect(
          screenHistory(
            owner,
            [erc721],
            known: [KnownRecipient(paid, RecipientProvenance.sentByOwner)],
          ).single.counterparty,
          poison,
        );
      },
    );

    test('a failed send needs no readable value: it moved nothing', () {
      final transfer = historyTransferFromExplorer(
        {...txRow(from: poison, to: owner, isError: '1')}..remove('value'),
        ExplorerList.txlist,
      )!;
      expect(transfer.amount, BigInt.zero);
    });

    test('empty NFT fields on a fungible row keep it', () {
      for (final empty in [null, '']) {
        expect(
          historyTransferFromExplorer({
            ...tokenRow(to: poison),
            'tokenID': empty,
            'tokenValue': empty,
          }, ExplorerList.tokentx),
          isNotNull,
        );
      }
    });

    test('a row read as the wrong list is reported, not misread', () {
      expect(
        () => historyTransferFromExplorer(tokenRow(), ExplorerList.txlist),
        throwsArgumentError,
      );
      // A counterfeit's row without token fields, read as a transaction, would become a native
      // send from the owner, which is never screened. It has no isError, so it is refused.
      final bare = tokenRow(to: poison)
        ..remove('tokenName')
        ..remove('tokenSymbol')
        ..remove('tokenDecimal');
      expect(
        () => historyTransferFromExplorer(bare, ExplorerList.txlist),
        throwsArgumentError,
      );
      expect(
        () => historyTransferFromExplorer(txRow(), ExplorerList.tokentx),
        throwsArgumentError,
      );
    });
  });

  // The README's code, so it is known to compile and to do what the README says.
  List<Map<String, Object?>> rows(String body) {
    final result = (jsonDecode(body) as Map<String, Object?>)['result'];
    if (result is! List<Object?>) throw StateError('explorer error: $result');
    return result.cast<Map<String, Object?>>();
  }

  test('an error response fails loudly instead of screening nothing', () {
    expect(
      () => rows(
        jsonEncode({
          'status': '0',
          'message': 'NOTOK',
          'result': 'Max rate limit reached',
        }),
      ),
      throwsStateError,
    );
    expect(
      rows(
        jsonEncode({
          'status': '0',
          'message': 'No transactions found',
          'result': <Object?>[],
        }),
      ),
      isEmpty,
    );
  });

  test('from the API responses to a stopped payment', () {
    const account = owner;
    final myTokens = [token];
    final txlistBody = jsonEncode({
      'status': '1',
      'message': 'OK',
      'result': [
        txRow(
          to: token,
          value: '0',
          input: transferCalldata(paid, BigInt.from(250000000)),
          hash: '01',
          time: 1700000100,
        ),
        txRow(
          from: poison,
          to: owner,
          value: '1',
          hash: '02',
          time: 1700000300,
        ),
      ],
    });
    final tokentxBody = jsonEncode({
      'status': '1',
      'message': 'OK',
      'result': [
        tokenRow(value: '250000000', hash: '01', time: 1700000100),
        tokenRow(to: poison, hash: '03', time: 1700000200),
      ],
    });

    final allTxlistBody =
        txlistBody; // One page holds this account's whole history.
    final allTxlistRows = rows(allTxlistBody);
    final txlistRows = rows(txlistBody);
    final tokentxRows = rows(tokentxBody);

    final known = [
      ...deriveKnownRecipients(
        account,
        allTxlistRows.map(sentTransactionFromExplorer).nonNulls,
      ),
    ];

    final activity = [
      for (final row in txlistRows)
        if (historyTransferFromExplorer(row, ExplorerList.txlist)
            case final transfer?)
          (row: row, transfer: transfer),
      for (final row in tokentxRows)
        if (historyTransferFromExplorer(row, ExplorerList.tokentx)
            case final transfer?)
          (row: row, transfer: transfer),
    ];

    final suspects = screenHistory(
      account,
      [for (final entry in activity) entry.transfer],
      known: known,
      listedTokens: myTokens,
    );
    final check = assessRecipient(poison, known: known, suspects: suspects);

    expect(known.map((entry) => entry.address), [paid]);
    // The native dust (02) and the forged zero-value log (03), found by hash. The owner's own
    // token payment (01) is screened twice, its call and its log, and neither is a suspect.
    expect(
      [for (final suspect in suspects) activity[suspect.index].row['hash']],
      ['0x${'02' * 32}', '0x${'03' * 32}'],
    );
    expect(suspects.last.signs, [
      PoisoningSign.zeroValue,
      PoisoningSign.namesOwnerAsSender,
    ]);
    expect(check.verdict, RecipientVerdict.lookalike);
    expect(check.reasons, contains(RecipientReason.plantedInHistory));
  });
}
