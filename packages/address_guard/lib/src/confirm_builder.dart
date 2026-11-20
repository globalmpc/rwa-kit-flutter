import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import 'acknowledgement.dart';
import 'address.dart';
import 'address_characters.dart';
import 'assess.dart';
import 'confirmed_recipient.dart';
import 'lookalike.dart';

/// What a recipient confirm step shows and allows at this moment, given to
/// [RecipientConfirmBuilder.builder].
///
/// It carries the rules of [RecipientConfirmCard], so an app with its own design system draws its
/// own step without re-deciding when the user may confirm.
class RecipientConfirmState {
  /// [RecipientConfirmBuilder] makes these. Public so that an app can test its own step with any
  /// state it wants to see; in the app itself, take the one the builder hands over.
  @visibleForTesting
  const RecipientConfirmState({
    required this.check,
    required this.chainId,
    required this.imitated,
    required this.candidateCharacters,
    required this.imitatedCharacters,
    required this.showsConfirm,
    required this.overridesStop,
    required this.acknowledgement,
    required this.acknowledged,
    required this.confirmed,
    required this.onAcknowledgedChanged,
    required this.onConfirm,
  });

  /// The check being confirmed.
  final RecipientCheck check;

  /// The chain the payment will be sent on.
  final int chainId;

  /// The addresses the candidate imitates, in the order of [RecipientCheck.lookalikes]: the
  /// user's known recipients first, then other rows of a payout list, each group closest copy
  /// first. Empty unless the verdict is [RecipientVerdict.lookalike]. Show them, with what
  /// differs highlighted.
  final List<LookalikeMatch> imitated;

  /// The candidate's characters: the middle is what lies between the ends it shares with the
  /// first of [imitated], or the check's window when it imitates none, and with an imitated
  /// address the characters that differ from that first one are marked. Null for
  /// [RecipientVerdict.invalid], which has no 40 characters to show: print the input as it is.
  final List<AddressCharacter>? candidateCharacters;

  /// For each of [imitated], in the same order, its characters compared with the candidate.
  final List<List<AddressCharacter>> imitatedCharacters;

  /// Whether to offer a confirm action at all. False for [RecipientVerdict.invalid], and for a
  /// look-alike or altered address unless [RecipientConfirmBuilder.allowOverride] is set.
  final bool showsConfirm;

  /// Whether confirming goes against a verdict that says stop. Show the action as dangerous.
  final bool overridesStop;

  /// The tick to ask for before confirming, or null when none is needed. Its text is
  /// [AddressGuardStringsAcknowledgement.acknowledgement].
  final RecipientAcknowledgement? acknowledgement;

  /// Whether the user has given [acknowledgement].
  final bool acknowledged;

  /// Whether the user has confirmed. The step stays done until the check, the chain or
  /// [RecipientConfirmBuilder.allowOverride] changes.
  final bool confirmed;

  /// Sets the tick. Null when there is no [acknowledgement], or once the user has confirmed.
  ///
  /// Like [onConfirm], it belongs to this state: once the check, the chain or
  /// [RecipientConfirmBuilder.allowOverride] changes, a copy kept from before does nothing. Take
  /// both from the latest state.
  final ValueChanged<bool>? onAcknowledgedChanged;

  /// Confirms, calling [RecipientConfirmBuilder.onConfirm]. Null whenever confirming is not
  /// allowed right now, so it can be given straight to a button's `onPressed`. A copy kept from
  /// an earlier state, such as one captured by a sheet built once, does nothing after the check,
  /// the chain or [RecipientConfirmBuilder.allowOverride] has changed: it can never confirm a
  /// recipient the user was not shown.
  final VoidCallback? onConfirm;

  /// Whether the confirm action is enabled right now.
  bool get canConfirm => onConfirm != null;
}

/// The confirm step of [RecipientConfirmCard] without its look: the same rules, drawn by
/// [builder].
///
/// - [RecipientVerdict.known]: confirm at once.
/// - [RecipientVerdict.firstTime]: confirm once the user ticks
///   [RecipientAcknowledgement.checkedFullAddress].
/// - [RecipientVerdict.lookalike] and [RecipientVerdict.badChecksum]: no confirm action. With
///   [allowOverride], one that is enabled once the user ticks
///   [RecipientAcknowledgement.override].
/// - [RecipientVerdict.invalid]: never.
///
/// [onConfirm] receives a [ConfirmedRecipient] bound to the address and chain, and is called at
/// most once until the check, the chain or [allowOverride] changes. Any of those changes also
/// clears the tick: the check counts as changed when its address or casing, its verdict, its
/// reasons, the label of the known recipient, or the addresses it imitates differ, so a recipient
/// swapped while the step is open is never confirmed by an earlier tick, nor by a callback kept
/// from an earlier state. A parent that rebuilds the same check keeps the tick. To ask again for
/// the same address, give the builder a new [Key]. Check the confirmation against the transaction
/// with [ConfirmedRecipient.matches] just before signing.
///
/// It draws nothing itself and needs no Material ancestor or theme, so it fits any design system.
class RecipientConfirmBuilder extends StatefulWidget {
  const RecipientConfirmBuilder({
    super.key,
    required this.check,
    required this.chainId,
    required this.onConfirm,
    required this.builder,
    this.allowOverride = false,
  });

  /// The result of [assessRecipient] for the address about to be paid.
  final RecipientCheck check;

  /// The chain the payment will be sent on.
  final int chainId;

  /// Called with the address and chain the user confirmed, at most once until the check, the
  /// chain or [allowOverride] changes. Check it against the transaction with
  /// [ConfirmedRecipient.matches] just before signing.
  final ValueChanged<ConfirmedRecipient> onConfirm;

  /// Draws the step from its current state.
  final Widget Function(BuildContext context, RecipientConfirmState state)
  builder;

  /// Lets the user confirm a look-alike or an altered address after an explicit override tick.
  /// Off by default: both verdicts mean "do not send".
  final bool allowOverride;

  @override
  State<RecipientConfirmBuilder> createState() =>
      _RecipientConfirmBuilderState();
}

/// What the user saw of [check], field by field, so that two checks are equal only when they show
/// the same thing. The known recipient's label is part of it, since the card prints it next to the
/// address, and each list is preceded by its length, so no field can pass for another.
List<Object?> _shown(RecipientCheck check) => [
  check.candidate,
  check.verdict,
  check.knownRecipient?.provenance,
  check.knownRecipient?.label,
  check.reasons.length,
  ...check.reasons,
  check.lookalikes.length,
  for (final match in check.lookalikes) ...[match.imitated, match.source],
];

class _RecipientConfirmBuilderState extends State<RecipientConfirmBuilder> {
  bool _acknowledged = false;
  bool _confirmed = false;

  /// Counts the decisions the user has been asked to make here. Every callback handed out carries
  /// the count it was made for and does nothing once it moves on, so a sheet left open on an
  /// earlier recipient can never tick or confirm the current one.
  int _generation = 0;

  /// What the user was shown of the check, as compared on every update. Set in [initState], not
  /// lazily: a lazy first read in [didUpdateWidget] would see the new check already.
  late List<Object?> _shownKey;

  /// The window the characters were drawn with.
  late (int, int) _window;

  @override
  void initState() {
    super.initState();
    _shownKey = _shown(widget.check);
    _window = (widget.check.prefixLength, widget.check.suffixLength);
  }

  /// Compares the check with what was shown, on every build and before every callback acts, so a
  /// check changed in place is caught even when nothing rebuilt the parent. A change clears the
  /// tick and the confirmation, retires the callbacks handed out so far, and redraws the
  /// characters; a new window only redraws them. Returns whether the tick was cleared.
  bool _sync() {
    final window = (widget.check.prefixLength, widget.check.suffixLength);
    if (window != _window) {
      _window = window;
      _characters = null;
    }
    final shown = _shown(widget.check);
    if (listEquals(shown, _shownKey)) return false;
    _shownKey = shown;
    _characters = null;
    _reset();
    return true;
  }

  void _reset() {
    _acknowledged = false;
    _confirmed = false;
    _generation++;
  }

  /// The characters of the check, worked out on the first build after the check or its window
  /// changes rather than on every rebuild. Cleared, never patched, so a check that cannot be drawn
  /// fails the build instead of showing the previous recipient's characters.
  _ShownCharacters? _characters;

  _ShownCharacters get _shownCharacters =>
      _characters ??= _ShownCharacters.of(widget.check);

  @override
  void didUpdateWidget(RecipientConfirmBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The check itself is compared in [_sync], on the build that follows. The chain and the
    // override setting are the builder's own, so they are compared here.
    if (oldWidget.chainId != widget.chainId ||
        oldWidget.allowOverride != widget.allowOverride) {
      _reset();
    }
  }

  RecipientVerdict get _verdict => widget.check.verdict;

  /// A verdict that blocks confirming unless an override is allowed. Invalid input never
  /// confirms, so it is handled apart.
  bool get _stops =>
      widget.check.shouldStop && _verdict != RecipientVerdict.invalid;

  /// A stop verdict the user may override after an explicit tick. The one place that rule lives.
  bool get _offersOverride => _stops && widget.allowOverride;

  /// Whether a confirm action exists at all.
  bool get _showsConfirm =>
      _verdict != RecipientVerdict.invalid && (!_stops || _offersOverride);

  RecipientAcknowledgement? get _acknowledgement {
    if (_verdict == RecipientVerdict.firstTime) {
      return RecipientAcknowledgement.checkedFullAddress;
    }
    if (_offersOverride) return RecipientAcknowledgement.override;
    return null;
  }

  bool get _canConfirm {
    if (_confirmed || !_showsConfirm) return false;
    // Every tick asked for must be given.
    return _acknowledgement == null || _acknowledged;
  }

  bool _current(int generation) => mounted && generation == _generation;

  void _confirm(int generation) {
    if (!mounted) return;
    if (_sync()) return setState(() {});
    if (!_current(generation) || !_canConfirm) return;
    setState(() => _confirmed = true);
    widget.onConfirm(
      ConfirmedRecipient(
        address: widget.check.candidate,
        chainId: widget.chainId,
        verdict: _verdict,
      ),
    );
  }

  void _setAcknowledged(int generation, bool value) {
    if (!mounted) return;
    if (_sync()) return setState(() {});
    if (!_current(generation) || _confirmed) return;
    setState(() => _acknowledged = value);
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final acknowledgement = _acknowledgement;
    final generation = _generation;
    final characters = _shownCharacters;
    final state = RecipientConfirmState(
      check: widget.check,
      chainId: widget.chainId,
      imitated: characters.imitated,
      candidateCharacters: characters.candidate,
      imitatedCharacters: characters.imitatedCharacters,
      showsConfirm: _showsConfirm,
      overridesStop: _offersOverride,
      acknowledgement: acknowledgement,
      acknowledged: _acknowledged,
      confirmed: _confirmed,
      onAcknowledgedChanged: acknowledgement == null || _confirmed
          ? null
          : (value) => _setAcknowledged(generation, value),
      onConfirm: _canConfirm ? () => _confirm(generation) : null,
    );
    return widget.builder(context, state);
  }
}

/// How an address is shown on a confirm step: where its middle starts and ends, and what it is
/// compared with. Shared by [RecipientConfirmBuilder] and [RecipientConfirmCard], so both mark
/// the same characters. Not exported.
typedef AddressLayout = ({
  int prefixLength,
  int suffixLength,
  String? compareWith,
});

/// The candidate's layout: the part a look-alike changed, where it imitates an address; otherwise
/// the check's window. [imitated] is the list from [RecipientConfirmState.imitated].
AddressLayout candidateLayout(
  RecipientCheck check,
  List<LookalikeMatch> imitated,
) {
  if (imitated.isEmpty) {
    return (
      prefixLength: check.prefixLength,
      suffixLength: check.suffixLength,
      compareWith: null,
    );
  }
  return imitatedLayout(check.candidate, imitated.first.imitated);
}

/// The layout of [address] compared with [other]: the middle is what lies between the ends they
/// share. Counted from the addresses rather than read from a match, so the bold part is right
/// whatever built the match.
AddressLayout imitatedLayout(String address, String other) {
  final a = addressBody(address);
  final b = addressBody(other);
  return (
    prefixLength: sharedHead(a, b),
    suffixLength: sharedTail(a, b),
    compareWith: other,
  );
}

/// What [RecipientConfirmState] shows of one check: the addresses it imitates and the characters
/// of each address. It depends on the check alone, not on the chain or the tick.
class _ShownCharacters {
  const _ShownCharacters(
    this.imitated,
    this.candidate,
    this.imitatedCharacters,
  );

  factory _ShownCharacters.of(RecipientCheck check) {
    // A copy, so a list changed in place later cannot fall out of step with its characters.
    final imitated = check.verdict == RecipientVerdict.lookalike
        ? List<LookalikeMatch>.unmodifiable(check.lookalikes)
        : const <LookalikeMatch>[];
    return _ShownCharacters(
      imitated,
      check.verdict == RecipientVerdict.invalid
          ? null
          : _characters(check.candidate, candidateLayout(check, imitated)),
      List.unmodifiable([
        for (final match in imitated)
          _characters(
            match.imitated,
            imitatedLayout(match.imitated, check.candidate),
          ),
      ]),
    );
  }

  final List<LookalikeMatch> imitated;
  final List<AddressCharacter>? candidate;
  final List<List<AddressCharacter>> imitatedCharacters;
}

List<AddressCharacter> _characters(String address, AddressLayout layout) =>
    addressCharacters(
      address,
      prefixLength: layout.prefixLength,
      suffixLength: layout.suffixLength,
      compareWith: layout.compareWith,
    );
