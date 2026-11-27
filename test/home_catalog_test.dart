import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:multi_tool_remote/screens/home_catalog.dart';
import 'package:multi_tool_remote/services/home_tabs.dart';

void main() {
  Future<void> mount(WidgetTester tester, List<int> opened) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeCatalog(onOpen: opened.add, onSettings: () {}),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('compact catalog searches and opens an existing tool', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final opened = <int>[];
    await mount(tester, opened);
    await tester.enterText(find.byType(TextField), 'vault');
    await tester.pumpAndSettle();
    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('Music'), findsNothing);
    await tester.tap(find.text('Vault'));
    await tester.pumpAndSettle();
    expect(opened, [HomeTabs.vault]);
  });

  testWidgets('empty saved pins and recent lists remain empty', (tester) async {
    SharedPreferences.setMockInitialValues({
      'home_card_pinned': <String>[],
      'home_recent_tools': <String>[],
    });
    await mount(tester, []);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Pin tools from the Tools tab.'), findsOneWidget);
    expect(find.text('Open a tool to see it here.'), findsOneWidget);
  });

  testWidgets('devices navigation opens PC Remote', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final opened = <int>[];
    await mount(tester, opened);
    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(opened, [HomeTabs.pc]);
  });
}
