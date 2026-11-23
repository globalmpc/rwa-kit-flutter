// The Material screens of this package import Material through this one file, so the reason for
// keeping package:flutter/material.dart is written once.
//
// Flutter 3.50 deprecates this library in favour of package:material_ui, but the two are separate
// copies: a screen built on material_ui inside an app built on MaterialApp from flutter/material,
// which is nearly every app today, would not see the app's Theme, and material_ui needs Flutter
// 3.47 or later. Keep flutter/material until host apps have moved; the builders need neither.
// ignore: deprecated_member_use
export 'package:flutter/material.dart';
