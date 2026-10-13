import 'package:elly_mobile_app/main.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

void main() {
  testWidgets('the app runs in Turkish whatever the device language (system strings too)', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final backend = FakeBackend();
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(value: backend.newAuth(), child: const EllyMobileApp()),
    );
    await tester.pump();

    final context = tester.element(find.byType(LoginScreen));
    expect(Localizations.localeOf(context), const Locale('tr'));
    expect(WidgetsLocalizations.of(context).reorderItemUp, 'Yukarı taşı');
    expect(MaterialLocalizations.of(context).cancelButtonLabel, isNot('Cancel'));
    expect(FlutterQuillLocalizations.of(context), isNotNull, reason: 'rich text toolbar strings still load');
  });

  test('each delegate once (Quill + Material + Widgets + Cupertino)', () {
    expect(appLocalizationsDelegates.map((d) => d.type).toSet(), hasLength(appLocalizationsDelegates.length));
    expect(appLocalizationsDelegates, hasLength(4));
  });

  testWidgets('ReorderableListView row actions are Turkish, no English "Move up"', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr')],
        home: Scaffold(
          body: ReorderableListView(
            onReorderItem: (_, _) {},
            children: [
              for (final i in [1, 2, 3]) ListTile(key: ValueKey(i), title: Text('Satır $i')),
            ],
          ),
        ),
      ),
    );

    final labels = <String>{};
    final data = tester.getSemantics(find.text('Satır 2')).getSemanticsData();
    for (final id in data.customSemanticsActionIds ?? const <int>[]) {
      labels.add(CustomSemanticsAction.getAction(id)!.label!);
    }
    expect(labels, containsAll(['Yukarı taşı', 'Aşağı taşı', 'Başa taşı', 'Sona taşı']));
    expect(labels.where((l) => l.contains('Move')), isEmpty);
    handle.dispose();
  });
}
