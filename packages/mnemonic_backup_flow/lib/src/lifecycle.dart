import 'package:flutter/widgets.dart';

/// Whether the app is in the foreground: visible and receiving input. Null is the state before
/// the platform has said, which is treated as the foreground the app starts in.
bool isAppInForeground(AppLifecycleState? state) =>
    state == null || state == AppLifecycleState.resumed;
