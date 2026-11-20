// Flutter 3.50 deprecates this library in favour of package:material_ui, but the two are separate
// copies: a material_ui card inside an app built on MaterialApp from flutter/material, which is
// nearly every app today, would not see the app's Theme, and material_ui needs Flutter 3.47 or
// later. Keep flutter/material until host apps have moved; RecipientConfirmBuilder needs neither.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'address_characters.dart';
import 'assess.dart';
import 'confirm_builder.dart';
import 'confirmed_recipient.dart';
import 'lookalike.dart';
import 'strings.dart';

/// A card that shows a recipient the way it must be checked, and asks the user to confirm it.
///
/// - The full address, never shortened, in groups of four characters. The characters between the
///   shared start and end are set in bold, because that is where a look-alike differs.
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
/// verdict, its reasons, the known recipient's label, or the addresses it imitates differ, so a
/// recipient swapped while the card is open is never confirmed by an earlier tick. To ask again for the same address, give the
/// card a new [Key]. Check the confirmation against the transaction with
/// [ConfirmedRecipient.matches] just before signing.
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

// A State only so the widget's public type stays what 0.2.0 shipped; the rules live in
// RecipientConfirmBuilder.
class _RecipientConfirmCardState extends State<RecipientConfirmCard> {
  @override
  Widget build(BuildContext context) => RecipientConfirmBuilder(
    check: widget.check,
    chainId: widget.chainId,
    allowOverride: widget.allowOverride,
    onConfirm: widget.onConfirm,
    builder: _build,
  );

  Widget _build(BuildContext context, RecipientConfirmState state) {
    final strings = widget.strings;
    final check = state.check;
    final theme = Theme.of(context);
    final tone = _Tone.of(check.verdict, theme.colorScheme);
    final imitated = state.imitated;
    final candidate = candidateLayout(check, imitated);
    final acknowledgement = state.acknowledgement;
    final onAcknowledgedChanged = state.onAcknowledgedChanged;

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
                if (state.candidateCharacters == null)
                  SelectableText(check.candidate, style: _monospace(theme))
                else
                  AddressText._marked(
                    state.candidateCharacters!,
                    address: check.candidate,
                    layout: candidate,
                    strings: strings,
                    key: const ValueKey('address_guard.candidate'),
                  ),
                for (final (index, match)
                    in imitated.take(_shownMatches).indexed) ...[
                  const SizedBox(height: 16),
                  Text(
                    match.source == MatchSource.knownRecipient
                        ? strings.imitatedLabel
                        : strings.imitatedBatchLabel,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  AddressText._marked(
                    state.imitatedCharacters[index],
                    address: match.imitated,
                    layout: imitatedLayout(match.imitated, check.candidate),
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
                    value: state.acknowledged,
                    onChanged: onAcknowledgedChanged == null
                        ? null
                        : (value) => onAcknowledgedChanged(value ?? false),
                    title: Text(strings.acknowledgement(acknowledgement)),
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
                    if (state.showsConfirm)
                      FilledButton(
                        onPressed: state.onConfirm,
                        style: state.overridesStop
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

/// Imitated addresses shown in full; the rest are counted.
const int _shownMatches = 3;

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
  }) : _characters = null;

  /// The card's own: characters [RecipientConfirmBuilder] already marked with [layout], so they
  /// are not worked out twice and the card shows exactly what the builder hands out.
  AddressText._marked(
    List<AddressCharacter> characters, {
    super.key,
    required this.address,
    required AddressLayout layout,
    required this.strings,
  }) : prefixLength = layout.prefixLength,
       suffixLength = layout.suffixLength,
       compareWith = layout.compareWith,
       _characters = characters;

  /// Throws [FormatException] at build time unless it is an EVM address.
  final String address;
  final int prefixLength;
  final int suffixLength;

  /// Another address to highlight differences against.
  final String? compareWith;
  final AddressGuardStrings strings;

  final List<AddressCharacter>? _characters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Validates both addresses, and keeps the casing the user gave: it is what they compare with
    // the source.
    final characters =
        _characters ??
        addressCharacters(
          address,
          prefixLength: prefixLength,
          suffixLength: suffixLength,
          compareWith: compareWith,
        );
    final base = _monospace(theme);
    final emphasis = base.copyWith(fontWeight: FontWeight.w700);
    final differs = base.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onErrorContainer,
      backgroundColor: theme.colorScheme.errorContainer,
      decoration: TextDecoration.underline,
    );

    // Read from the characters shown, so the spoken address can never differ from the visible one.
    final groups = <String>[
      for (var start = 0; start < 40; start += 4)
        characters.sublist(start, start + 4).map((c) => c.character).join(),
    ];

    TextSpan charSpan(AddressCharacter character) => TextSpan(
      text: character.character,
      style: character.differs
          ? differs
          : (character.inMiddle ? emphasis : base),
    );

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
                    charSpan(characters[index]),
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
