import 'package:address_guard/address_guard.dart';
import 'package:flutter/material.dart';

// Synthetic accounts for the demo. None of them is a real address anyone depends on.
const _owner = '0x1111111111111111111111111111111111111111';
const _token = '0x2222222222222222222222222222222222222222';
const _supplier = '0xa1b2c3d4e5f60718293a4b5c6d7e8f9012345678';
const _poison = '0xa1b2ffffffffffffffffffffffffffffffff5678';
const _attacker = '0x4444444444444444444444444444444444444444';
const _fakeToken = '0x3333333333333333333333333333333333333333';

/// What the wallet already has: the transactions this account sent, plus one an attacker sent.
/// The attacker's zero-value transfer is the poisoning step: it puts the look-alike in the
/// account's history. `deriveKnownRecipients` ignores it because the owner did not sign it.
final _history = [
  SentTransaction(
    from: _owner,
    to: _token,
    value: BigInt.zero,
    input:
        '0xa9059cbb'
        '${'0' * 24}${_supplier.substring(2)}'
        '${BigInt.from(250000000).toRadixString(16).padLeft(64, '0')}',
    succeeded: true,
  ),
  SentTransaction(
    from: _attacker,
    to: _token,
    value: BigInt.zero,
    input:
        '0x23b872dd'
        '${'0' * 24}${_owner.substring(2)}'
        '${'0' * 24}${_poison.substring(2)}'
        '${'0' * 64}',
    succeeded: true,
  ),
];

/// What the activity list shows: token transfers as an indexer reports them. Two of them were
/// planted. The zero-value one reads as if the owner had paid the look-alike; the other is a
/// counterfeit token "from" the look-alike. `screenHistory` flags both.
final _activity = [
  HistoryTransfer(
    from: _owner,
    to: _supplier,
    amount: BigInt.from(250000000),
    token: _token,
  ),
  HistoryTransfer(
    from: _owner,
    to: _poison,
    amount: BigInt.zero,
    token: _token,
  ),
  HistoryTransfer(
    from: _poison,
    to: _owner,
    amount: BigInt.from(250000000),
    token: _fakeToken,
  ),
];

void main() => runApp(const AddressGuardExample());

class AddressGuardExample extends StatelessWidget {
  const AddressGuardExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'address_guard example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const SendScreen(),
  );
}

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  static const _chainId = 56;
  final _controller = TextEditingController();
  final _known = deriveKnownRecipients(_owner, _history);
  late final _suspects = screenHistory(
    _owner,
    _activity,
    known: _known,
    listedTokens: const [_token],
  );
  late final _suspectAt = {
    for (final suspect in _suspects) suspect.index: suspect,
  };
  ConfirmedRecipient? _confirmed;

  /// The exact text the user confirmed. Any other text, even the same address in another
  /// casing, is judged again and needs a new confirmation.
  String? _confirmedInput;

  /// A new card for every address picked from the chips, so picking the same one again asks again.
  int _pick = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Fills the field the way a wallet shows an address: in its checksummed spelling.
  void _use(String address) => setState(() {
    _controller.text = address.isEmpty ? '' : toChecksumAddress(address);
    _confirmed = null;
    _confirmedInput = null;
    _pick++;
  });

  @override
  Widget build(BuildContext context) {
    final input = _controller.text.trim();
    final check = input.isEmpty
        ? null
        : assessRecipient(input, known: _known, suspects: _suspects);
    final confirmed = _confirmed;

    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      // A short page, so every part stays built: a column in a scroll view rather than a lazy list.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Recipient address',
                border: OutlineInputBorder(),
              ),
              // Any edit drops the confirmation, except whitespace around the confirmed text. The
              // card resets on its own whenever the address it shows changes.
              onChanged: (text) => setState(() {
                if (text.trim() != _confirmedInput) {
                  _confirmed = null;
                  _confirmedInput = null;
                }
              }),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Supplier you paid'),
                  onPressed: () => _use(_supplier),
                ),
                ActionChip(
                  label: const Text('Look-alike from history'),
                  onPressed: () => _use(_poison),
                ),
                ActionChip(
                  label: const Text('New address'),
                  onPressed: () =>
                      _use('0x9f8e7d6c5b4a39281706f5e4d3c2b1a098765432'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (check != null)
              RecipientConfirmCard(
                key: ValueKey(_pick),
                check: check,
                chainId: _chainId,
                networkName: 'BNB Smart Chain',
                onCancel: () => _use(''),
                onConfirm: (result) => setState(() {
                  _confirmed = result;
                  _confirmedInput = input;
                }),
              ),
            if (confirmed != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  // A real wallet checks this again just before signing.
                  confirmed.matches(_controller.text.trim(), _chainId)
                      ? 'Ready to sign: ${confirmed.address}'
                      : 'The recipient changed after confirming. Confirm again.',
                ),
              ),
            const SizedBox(height: 24),
            Text('Activity', style: Theme.of(context).textTheme.titleSmall),
            for (final (index, entry) in _activity.indexed)
              _ActivityRow(
                transfer: entry,
                owner: _owner,
                suspect: _suspectAt[index],
                onUse: _use,
              ),
          ],
        ),
      ),
    );
  }
}

/// One activity entry, shortened the way wallets show it. A flagged entry says why, so the user
/// is warned before copying the address, not only when pasting it.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.transfer,
    required this.owner,
    required this.suspect,
    required this.onUse,
  });

  final HistoryTransfer transfer;
  final String owner;
  final PoisoningSuspect? suspect;
  final ValueChanged<String> onUse;

  @override
  Widget build(BuildContext context) {
    const strings = AddressGuardStrings();
    final sent = transfer.from.toLowerCase() == normalizeAddress(owner);
    final other = sent ? transfer.to : transfer.from;
    // Indexer records can be malformed; show those as they are rather than failing the list.
    final short = isEvmAddress(other)
        ? '${other.substring(0, 6)}…${other.substring(38)}'
        : other;
    final suspect = this.suspect;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        suspect == null ? Icons.receipt_long : Icons.warning_amber_rounded,
        color: suspect == null ? null : scheme.error,
      ),
      title: Text('${sent ? 'Sent to' : 'Received from'} $short'),
      subtitle: suspect == null
          ? null
          : Text(
              [
                strings.historyWarning,
                for (final sign in suspect.signs) strings.sign(sign),
              ].join(' '),
              style: TextStyle(color: scheme.error),
            ),
      // A flagged entry cannot be copied from here. The send card would still stop it, as the
      // "Look-alike from history" chip shows, but the history is the first place to refuse.
      trailing: TextButton(
        onPressed: suspect == null && isEvmAddress(other)
            ? () => onUse(other)
            : null,
        child: const Text('Use'),
      ),
    );
  }
}
