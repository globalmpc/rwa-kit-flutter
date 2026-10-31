import 'package:flutter/material.dart';

import 'address.dart';
import 'assess.dart';
import 'confirmed_recipient.dart';
import 'lookalike.dart';
import 'strings.dart';

/// A card that shows a recipient the way it must be checked, and asks the user to confirm it.
///
/// - The full address, never shortened, in groups of four characters. The characters between the
///   compared start and end are set in bold, because that is where a look-alike differs.
/// - For a look-alike, the addresses it imitates underneath (up to three, the rest counted). Each
///   has the characters that differ from the candidate highlighted, and the candidate is
///   highlighted against the first.
/// - The verdict and its reasons in plain language, and the network the payment is on.
/// - A confirm button whose rule depends on the verdict:
///   - [RecipientVerdict.known]: enabled.
///   - [RecipientVerdict.firstTime]: enabled once the user ticks that they checked the full
///     address.
///   - [RecipientVerdict.lookalike] and [RecipientVerdict.badChecksum]: not shown. With
///     [allowOverride], shown and enabled once the user ticks an explicit override.
///   - [RecipientVerdict.invalid]: never shown.
///
/// [onConfirm] receives a [ConfirmedRecipient] bound to the address and chain that were shown,
/// and is called at most once until the check, the chain or [allowOverride] changes. Any of those
/// changes also clears the tick: the check counts as changed when its address or casing, its
/// verdict, or the addresses it imitates differ, so a recipient swapped while the card is open is
/// never confirmed by an earlier tick. To ask again for the same address, give the card a new
/// [Key]. Check the confirmation against the transaction with [ConfirmedRecipient.matches] just
/// before signing.
class RecipientConfirmCard extends StatefulWidget {
  const RecipientConfirmCard({
    super.key,
    required this.check,
    required this.chainId,
    required this.onConfirm,
    this.onCancel,
    this.networkName,
    this.allowOverride = false,
    this.strings = const AddressGuardStrings(),
  });

  /// The result of [assessRecipient] for the address about to be paid.
  final RecipientCheck check;

  /// The chain the payment will be sent on.
  final int chainId;

  /// Shown next to the chain id, for example `BNB Smart Chain`.
  final String? networkName;

  final ValueChanged<ConfirmedRecipient> onConfirm;

  /// Shows a cancel button when given.
  final VoidCallback? onCancel;

  /// Lets the user confirm a look-alike or an altered address after an explicit override tick.
  /// Off by default: both verdicts mean "do not send".
  final bool allowOverride;

  final AddressGuardStrings strings;

  @override
  State<RecipientConfirmCard> createState() => _RecipientConfirmCardState();
}

/// Imitated addresses shown in full; the rest are counted.
const int _shownMatches = 3;

/// What the user saw of [check], as one comparable value.
String _shown(RecipientCheck check) => [
  check.candidate,
  check.verdict.name,
  for (final match in check.lookalikes)
    '${match.imitated}:${match.source.name}',
].join('|');

class _RecipientConfirmCardState extends State<RecipientConfirmCard> {
  bool _acknowledged = false;
  bool _confirmed = false;

  @override
  void didUpdateWidget(RecipientConfirmCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compared by value, so a parent that rebuilds the same check keeps the tick, and anything
    // the user's decision rested on clears it: the address, the verdict, what it imitates, the
    // chain, or whether an override is allowed.
    final changed =
        _shown(oldWidget.check) != _shown(widget.check) ||
        oldWidget.chainId != widget.chainId ||
        oldWidget.allowOverride != widget.allowOverride;
    if (changed) {
      _acknowledged = false;
      _confirmed = false;
    }
  }

  RecipientVerdict get _verdict => widget.check.verdict;

  /// A verdict that blocks confirming unless an override is allowed. Invalid input never
  /// confirms, so it is handled apart.
  bool get _stops =>
      widget.check.shouldStop && _verdict != RecipientVerdict.invalid;

  /// The tick the user must give before confirming, or null when none is needed or possible.
  String? get _acknowledgement {
    if (_verdict == RecipientVerdict.firstTime) {
      return widget.strings.firstTimeAcknowledgement;
    }
    if (_stops && widget.allowOverride) {
      return widget.strings.overrideAcknowledgement;
    }
    return null;
  }

  bool get _canConfirm {
    if (_confirmed) return false;
    if (_verdict == RecipientVerdict.invalid) return false;
    if (_stops) return widget.allowOverride && _acknowledged;
    if (_verdict == RecipientVerdict.firstTime) return _acknowledged;
    return true;
  }

  void _confirm() {
    if (!_canConfirm) return;
    setState(() => _confirmed = true);
    widget.onConfirm(
      ConfirmedRecipient(
        address: widget.check.candidate,
        chainId: widget.chainId,
        verdict: _verdict,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final check = widget.check;
    final theme = Theme.of(context);
    final tone = _Tone.of(_verdict, theme.colorScheme);
    final imitated = check.verdict == RecipientVerdict.lookalike
        ? check.lookalikes
        : const <LookalikeMatch>[];
    final acknowledgement = _acknowledgement;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Container(
              color: tone.background,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(tone.icon, color: tone.foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings.titleFor(check),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: tone.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.knownRecipient?.label == null
                      ? strings.recipientLabel
                      : '${strings.recipientLabel}: ${check.knownRecipient!.label}',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                if (check.verdict == RecipientVerdict.invalid)
                  SelectableText(check.candidate, style: _monospace(theme))
                else
                  AddressText(
                    address: check.candidate,
                    prefixLength: check.prefixLength,
                    suffixLength: check.suffixLength,
                    compareWith: imitated.isEmpty
                        ? null
                        : imitated.first.imitated,
                    strings: strings,
                    key: const ValueKey('address_guard.candidate'),
                  ),
                for (final match in imitated.take(_shownMatches)) ...[
                  const SizedBox(height: 16),
                  Text(
                    match.source == MatchSource.knownRecipient
                        ? strings.imitatedLabel
                        : strings.imitatedBatchLabel,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  AddressText(
                    address: match.imitated,
                    prefixLength: check.prefixLength,
                    suffixLength: check.suffixLength,
                    compareWith: check.candidate,
                    strings: strings,
                  ),
                ],
                if (imitated.length > _shownMatches) ...[
                  const SizedBox(height: 8),
                  Text(
                    strings.moreImitated(imitated.length - _shownMatches),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (imitated.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(strings.highlightHint, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 16),
                for (final reason in check.reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      strings.reason(reason),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                Text(
                  strings.network(widget.networkName, widget.chainId),
                  style: theme.textTheme.bodySmall,
                ),
                if (acknowledgement != null) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _acknowledged,
                    onChanged: _confirmed
                        ? null
                        : (value) =>
                              setState(() => _acknowledged = value ?? false),
                    title: Text(acknowledgement),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.onCancel != null)
                      TextButton(
                        onPressed: widget.onCancel,
                        child: Text(strings.cancel),
                      ),
                    if (_verdict != RecipientVerdict.invalid &&
                        (!_stops || widget.allowOverride))
                      FilledButton(
                        onPressed: _canConfirm ? _confirm : null,
                        style: _stops
                            ? FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                                foregroundColor: theme.colorScheme.onError,
                              )
                            : null,
                        child: Text(strings.confirm),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full EVM address in groups of four characters, read as one spelled-out label by screen
/// readers.
///
/// The characters between the first [prefixLength] and the last [suffixLength] are bold, because
/// they are the part people skip. With [compareWith], every character that differs from it is
/// also highlighted. Casing is shown as given.
class AddressText extends StatelessWidget {
  const AddressText({
    super.key,
    required this.address,
    this.prefixLength = defaultPrefixLength,
    this.suffixLength = defaultSuffixLength,
    this.compareWith,
    this.strings = const AddressGuardStrings(),
  });

  /// Throws [FormatException] at build time unless it is an EVM address.
  final String address;
  final int prefixLength;
  final int suffixLength;

  /// Another address to highlight differences against.
  final String? compareWith;
  final AddressGuardStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Validates, and keeps the casing the user gave: it is what they compare with the source.
    final lower = addressBody(address);
    final body = address.substring(2);
    final other = compareWith == null ? null : addressBody(compareWith!);
    final base = _monospace(theme);
    final emphasis = base.copyWith(fontWeight: FontWeight.w700);
    final differs = base.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onErrorContainer,
      backgroundColor: theme.colorScheme.errorContainer,
      decoration: TextDecoration.underline,
    );

    final groups = <String>[
      for (var start = 0; start < 40; start += 4)
        body.substring(start, start + 4),
    ];

    TextSpan charSpan(int index) {
      final isMiddle = index >= prefixLength && index < 40 - suffixLength;
      final isDifferent = other != null && other[index] != lower[index];
      return TextSpan(
        text: body[index],
        style: isDifferent ? differs : (isMiddle ? emphasis : base),
      );
    }

    return Semantics(
      // Its own node, so the spelled-out address is announced on its own and never merged into
      // the label or the reasons around it.
      container: true,
      label: strings.addressSemantics(groups),
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          Text('0x', style: base),
          for (var group = 0; group < 10; group++)
            Text.rich(
              TextSpan(
                children: [
                  for (var index = group * 4; index < group * 4 + 4; index++)
                    charSpan(index),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

TextStyle _monospace(ThemeData theme) =>
    (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['RobotoMono', 'Menlo', 'Courier New'],
      letterSpacing: 0.5,
    );

class _Tone {
  const _Tone(this.icon, this.background, this.foreground);

  final IconData icon;
  final Color background;
  final Color foreground;

  static _Tone of(RecipientVerdict verdict, ColorScheme scheme) =>
      switch (verdict) {
        RecipientVerdict.known => _Tone(
          Icons.history,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
        RecipientVerdict.firstTime => _Tone(
          Icons.info_outline,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
        RecipientVerdict.lookalike => _Tone(
          Icons.warning_amber_rounded,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
        RecipientVerdict.badChecksum => _Tone(
          Icons.report_outlined,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
        RecipientVerdict.invalid => _Tone(
          Icons.error_outline,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      };
}
