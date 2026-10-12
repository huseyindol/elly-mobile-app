import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/models/crud_module.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

final CrudModule _posts = ModulesConfig.allModules.firstWhere((m) => m.permissionKey == 'posts');

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend.routes['/posts/list'] = (_) => okData([
          {'id': 1, 'title': 'Birinci', 'slug': 'birinci'},
          {'id': 2, 'title': 'Ikinci', 'slug': 'ikinci'},
        ]);
  });

  /// Opens the list screen as a user holding exactly [permissions].
  Future<void> pumpList(WidgetTester tester, List<String> permissions, {CrudModule? module}) async {
    backend.permissions(permissions);
    await tester.runAsync(() {
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'a', 'tenantId': 't1'});
      return auth.checkAuthStatus();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: GenericCrudListScreen(module: module ?? _posts, apiService: backend.api)),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  Finder edit(int id) => find.byKey(ValueKey('edit_$id'));
  Finder delete(int id) => find.byKey(ValueKey('delete_$id'));

  testWidgets('loads items through the injected ApiService', (tester) async {
    await pumpList(tester, ['posts:read']);

    expect(backend.requestsTo('/posts/list'), hasLength(1));
    expect(find.text('Birinci'), findsOneWidget);
    expect(find.text('Ikinci'), findsOneWidget);
  });

  testWidgets('read only: no FAB, no edit, no delete', (tester) async {
    await pumpList(tester, ['posts:read']);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(edit(1), findsNothing);
    expect(edit(2), findsNothing);
    expect(delete(1), findsNothing);
    expect(delete(2), findsNothing);
  });

  testWidgets('read + create: FAB only', (tester) async {
    await pumpList(tester, ['posts:read', 'posts:create']);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(edit(1), findsNothing);
    expect(delete(1), findsNothing);
  });

  testWidgets('read + update: edit actions only', (tester) async {
    await pumpList(tester, ['posts:read', 'posts:update']);

    expect(edit(1), findsOneWidget);
    expect(edit(2), findsOneWidget);
    expect(delete(1), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('read + delete: delete actions only', (tester) async {
    await pumpList(tester, ['posts:read', 'posts:delete']);

    expect(delete(1), findsOneWidget);
    expect(delete(2), findsOneWidget);
    expect(edit(1), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('all permissions: FAB, edit and delete are shown', (tester) async {
    await pumpList(tester, ['posts:read', 'posts:create', 'posts:update', 'posts:delete']);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(edit(1), findsOneWidget);
    expect(delete(1), findsOneWidget);
  });

  testWidgets('permissions of another module do not grant actions', (tester) async {
    await pumpList(tester, ['posts:read', 'pages:create', 'pages:update', 'pages:delete']);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(edit(1), findsNothing);
    expect(delete(1), findsNothing);
  });

  testWidgets('module-level canCreate/canEdit/canDelete=false hide actions even with permissions',
      (tester) async {
    const readOnlyModule = CrudModule(
      title: 'Posts',
      crudEndpoint: '/posts',
      listEndpoint: '/posts/list',
      icon: Icons.article_rounded,
      fields: [],
      permissionKey: 'posts',
      payloadKeys: [],
      canCreate: false,
      canEdit: false,
      canDelete: false,
    );
    await pumpList(tester, ['posts:read', 'posts:create', 'posts:update', 'posts:delete'],
        module: readOnlyModule);

    expect(find.text('Birinci'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(edit(1), findsNothing);
    expect(delete(1), findsNothing);
  });

  testWidgets('list request failure shows the error and "Tekrar Dene"', (tester) async {
    backend.routes['/posts/list'] = (_) => jsonResponse({'message': 'Sunucu hatası'}, 500);
    await pumpList(tester, ['posts:read']);

    expect(find.text('Sunucu hatası'), findsOneWidget);
    expect(find.text('Tekrar Dene'), findsOneWidget);
    expect(find.text('Birinci'), findsNothing);

  });
}
