import 'dart:async';

/// Runs operations one after another, in the order they were requested, whatever the outcome of
/// the earlier ones. The future [run] returns carries its own operation's error to the caller,
/// and to the zone when nobody awaits it.
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() operation) {
    final gate = Completer<void>();
    final previous = _tail;
    _tail = gate.future;
    return previous.then((_) => operation()).whenComplete(gate.complete);
  }
}
