import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

class FakePlugin {
  int on = 0;
  int off = 0;
  Future<void> enable() async => on++;
  Future<void> disable() async => off++;
}

void main() {
  test('callbacks forward to the plugin', () async {
    final plugin = FakePlugin();
    final adapter = ScreenProtection.callbacks(
      protect: plugin.enable,
      release: plugin.disable,
    );

    await adapter.protect();
    await adapter.release();

    expect((plugin.on, plugin.off), (1, 1));
  });

  test('none() is one shared no-op', () async {
    const protection = ScreenProtection.none();
    await protection.protect();
    await protection.release();
    expect(identical(protection, const ScreenProtection.none()), isTrue);
  });
}
