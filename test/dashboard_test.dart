import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_tool_remote/services/connectivity_service.dart';
import 'package:multi_tool_remote/services/dashboard_service.dart';
import 'package:multi_tool_remote/widgets/dashboard_status.dart';

void main() {
  test('endpoint status does not imply every PC module is online', () {
    final snapshot = DashboardSnapshot(
      reachability: DashboardReachability.reachable, checkedAt: DateTime(2026),
    );
    expect(snapshot.connectionLabel, 'PC music endpoint reachable');
    expect(snapshot.networkLabel, 'Network unknown');
    expect(snapshot.paired, isNull);
  });

  testWidgets('dashboard shows real snapshot and refreshes on request', (tester) async {
    var loads = 0;
    var remote = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: DashboardStatus(
        active: true,
        load: () async {
          loads++;
          return DashboardSnapshot(
            reachability: DashboardReachability.denied,
            checkedAt: DateTime(2026), network: NetworkType.wifi,
            paired: false, indexed: 42, downloaded: 3, downloadBytes: 2048,
          );
        },
        onRemote: () => remote++, onMusic: () {}, onSend: () {}, onSettings: () {},
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Music endpoint denied access'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    await tester.tap(find.text('PC Remote'));
    expect(remote, 1);
    await tester.tap(find.byTooltip('Refresh dashboard'));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });
}
