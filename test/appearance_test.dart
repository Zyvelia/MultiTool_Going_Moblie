import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:multi_tool_remote/theme/appearance.dart';
import 'package:multi_tool_remote/theme/app_theme.dart';
import 'package:multi_tool_remote/screens/home_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('appearance round trips and clamps invalid preferences', () {
    const original = Appearance(preset: NeonPreset.midnight, customAccent: Color(0xFFFF718C),
      glow: 0.7, glass: 0.2, animations: false);
    final decoded = Appearance.fromJson(original.toJson());
    expect(decoded.toJson(), original.toJson());
    final invalid = Appearance.fromJson({'preset': 'unknown', 'glow': 9, 'glass': -3, 'animations': 'bad'});
    expect(invalid.preset, NeonPreset.eclipse);
    expect(invalid.glow, 1);
    expect(invalid.glass, 0);
    expect(invalid.animations, isTrue);
  });

  test('saved appearance is restored independently of module settings', () async {
    SharedPreferences.setMockInitialValues({'home_card_order': <String>['pc']});
    final first = AppearanceController();
    await first.apply(const Appearance(preset: NeonPreset.amoled, animations: false));
    final restored = AppearanceController();
    await restored.load();
    expect(restored.value.bg, Colors.black);
    expect(restored.value.animations, isFalse);
    expect((await SharedPreferences.getInstance()).getStringList('home_card_order'), ['pc']);
    first.dispose();
    restored.dispose();
  });

  testWidgets('catalog honors the selected preset', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const palette = Appearance(preset: NeonPreset.midnight);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(palette),
      home: HomeCatalog(onOpen: (_) {}, onSettings: () {}),
    ));
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, palette.bg);
    expect(tester.takeException(), isNull);
  });
}
