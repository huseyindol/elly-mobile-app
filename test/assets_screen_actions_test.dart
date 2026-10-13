import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/assets_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'helpers/fake_backend.dart';

/// AssetsScreen beyond assets_screen_test.dart: bulk-delete reporting, folder × search endpoint
/// combinations, single upload / replace / delete and permission-dependent actions.

final class _PickedFile extends PlatformFile {
  final File file;
  _PickedFile(this.file);
  @override
  String get name => file.uri.pathSegments.last;
  @override
  Uri get uri => file.uri;
  @override
  get xFile => throw UnimplementedError('not used');
  @override
  int? lengthSync() => file.lengthSync();
  @override
  Future<int?> length() async => file.lengthSync();
  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();
  @override
  Stream<Uint8List> readAsByteStream() => file.openRead().map(Uint8List.fromList);
}

class _FakePicker extends FilePickerPlatform {
  final List<File> files;
  _FakePicker(this.files);
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => [for (final f in files) _PickedFile(f)];
}

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {'content': items, 'last': true};

Map<String, dynamic> _asset(int id, String name, {String folder = 'images'}) => {
  'id': id,
  'name': name,
  'path': 'assets/t/t1/$folder/$name',
  'type': 'image/png',
  'subFolder': folder,
};

const _search = ValueKey('asset_search_field');

void main() {
  late FakeBackend backend;
  late AuthProvider auth;
  late Directory tmp;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    tmp = Directory.systemTemp.createTempSync('elly_assets_actions');
    backend.ok('/assets/sub-folders', ['images', 'docs']);
    backend.ok('/assets/list/paged', _page([_asset(1, 'logo.png'), _asset(2, 'banner.png', folder: 'docs')]));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> pumpAssets(WidgetTester tester, List<String> permissions) async {
    await tester.runAsync(() => backend.signIn(auth, permissions));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(home: AssetsScreen(apiService: backend.api)),
      ),
    );
    await settle(tester);
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(_search), text);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
  }

  Future<void> chip(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey('folder_$key')));
    await settle(tester);
  }

  File file(String name, [int byte = 1]) => File('${tmp.path}/$name')..writeAsBytesSync([byte]);

  Future<void> selectBoth(WidgetTester tester) async {
    await tester.longPress(find.text('logo.png'));
    await tester.pump();
    await tester.tap(find.text('banner.png'));
    await tester.pump();
  }

  Future<void> bulkDelete(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('bulk_delete_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm_bulk_delete_button')));
    await settle(tester);
  }

  /// Registers POST /assets/bulk-delete → [response]; returns the captured requests.
  List<http.Request> bulkRoute(http.Response Function() response) {
    final sent = <http.Request>[];
    backend.routes['/assets/bulk-delete'] = (req) {
      sent.add(req);
      return response();
    };
    return sent;
  }

  group('bulk delete', () {
    testWidgets('all deleted: plain success message, selection cleared, list reloaded', (tester) async {
      final sent = bulkRoute(() => okData({'deletedCount': 2, 'failedIds': <Object>[]}));
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      final before = backend.requestsTo('/assets/list/paged').length;

      await selectBoth(tester);
      await bulkDelete(tester);

      expect(jsonDecode(sent.single.body), {
        'ids': [1, 2],
      });
      expect(find.text('2 asset silindi.'), findsOneWidget);
      expect(find.textContaining('silinemedi'), findsNothing);
      expect(find.textContaining('seçili'), findsNothing);
      expect(backend.requestsTo('/assets/list/paged').length, greaterThan(before), reason: 'list refetched');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('failedIds are listed with their ids; the count comes from deletedCount', (tester) async {
      bulkRoute(
        () => okData({
          'deletedCount': 0,
          'failedIds': [1, 2],
        }),
      );
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      await selectBoth(tester);
      await bulkDelete(tester);

      expect(find.text('0 asset silindi, 2 silinemedi (ID: 1, 2)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('response without deletedCount: derived from selected - failed', (tester) async {
      bulkRoute(
        () => okData({
          'failedIds': [2],
        }),
      );
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      await selectBoth(tester);
      await bulkDelete(tester);

      expect(find.text('1 asset silindi, 1 silinemedi (ID: 2)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('failed bulk request: error shown, selection kept so the user can retry', (tester) async {
      final sent = bulkRoute(() => jsonResponse({'result': false, 'message': 'Silme başarısız'}, 500));
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      await selectBoth(tester);
      await bulkDelete(tester);

      expect(sent, hasLength(1));
      expect(find.textContaining('Silme başarısız'), findsOneWidget);
      expect(find.text('2 seçili'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('cancelling the confirmation sends nothing and keeps the selection', (tester) async {
      final sent = bulkRoute(() => okData({'deletedCount': 2, 'failedIds': <Object>[]}));
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      await selectBoth(tester);
      await tester.tap(find.byKey(const ValueKey('bulk_delete_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      expect(sent, isEmpty);
      expect(find.text('2 seçili'), findsOneWidget);
    });

    testWidgets('deselecting the last item leaves selection mode (tile tap toggles)', (tester) async {
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      await tester.longPress(find.text('logo.png'));
      await tester.pump();
      expect(find.text('1 seçili'), findsOneWidget);
      await tester.tap(find.text('logo.png'));
      await tester.pump();

      expect(find.byKey(const ValueKey('bulk_delete_button')), findsNothing);
      expect(find.text('Assetler'), findsWidgets);
    });

    testWidgets('"Seçimi temizle" clears the selection', (tester) async {
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      await selectBoth(tester);
      await tester.tap(find.byTooltip('Seçimi temizle'));
      await tester.pump();

      expect(find.textContaining('seçili'), findsNothing);
    });
  });

  group('folder × search endpoints', () {
    setUp(() {
      backend.ok('/assets/list/images/paged', _page([_asset(1, 'logo.png')]));
      backend.ok('/assets/logo/paged', _page([_asset(1, 'logo.png')]));
      backend.ok('/assets/images/logo/paged', _page([_asset(1, 'logo.png')]));
      backend.ok('/assets/docs/logo/paged', _page([_asset(3, 'logo-doc.png', folder: 'docs')]));
      backend.ok('/assets/id/2', _asset(2, 'banner.png', folder: 'docs'));
    });

    testWidgets('folder chip + name search → /assets/{folder}/{name}/paged', (tester) async {
      await pumpAssets(tester, ['assets:read']);
      await chip(tester, 'images');
      await search(tester, 'logo');

      expect(backend.requestsTo('/assets/images/logo/paged'), hasLength(1));
      expect(backend.requestsTo('/assets/logo/paged'), isEmpty);
    });

    testWidgets('name search first, then a folder chip: the search term is kept', (tester) async {
      await pumpAssets(tester, ['assets:read']);
      await search(tester, 'logo');
      expect(backend.requestsTo('/assets/logo/paged'), hasLength(1));

      await chip(tester, 'docs');
      expect(backend.requestsTo('/assets/docs/logo/paged'), hasLength(1));
      expect(find.text('logo-doc.png'), findsOneWidget);
    });

    testWidgets('clearing the search returns to the folder listing', (tester) async {
      await pumpAssets(tester, ['assets:read']);
      await chip(tester, 'images');
      await search(tester, 'logo');
      await tester.tap(find.byKey(const ValueKey('asset_search_clear')));
      await settle(tester);

      expect(backend.requestsTo('/assets/list/images/paged'), hasLength(2), reason: 'chip load + after clearing');
      expect(find.byKey(const ValueKey('asset_search_clear')), findsNothing);
    });

    testWidgets('"Tümü" chip drops the folder but keeps the name search', (tester) async {
      await pumpAssets(tester, ['assets:read']);
      await chip(tester, 'images');
      await search(tester, 'logo');
      await chip(tester, 'all');

      expect(backend.requestsTo('/assets/logo/paged'), hasLength(1));
    });

    testWidgets('ID search ignores the selected folder and uses /assets/id/{id}', (tester) async {
      await pumpAssets(tester, ['assets:read']);
      await chip(tester, 'images');
      await tester.tap(find.text('ID'));
      await tester.pump();
      await search(tester, '2');

      expect(backend.requestsTo('/assets/id/2'), hasLength(1));
      expect(find.text('banner.png'), findsOneWidget);
    });

    testWidgets('non-numeric ID is rejected locally with a message and no request', (tester) async {
      await pumpAssets(tester, ['assets:read']);
      await tester.tap(find.text('ID'));
      await tester.pump();
      await search(tester, 'abc');

      expect(find.text('ID bir sayı olmalı'), findsOneWidget);
      expect(backend.requests.where((r) => r.url.path.contains('/assets/id/')), isEmpty);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('ID not found (404) shows the error view, not a stale list', (tester) async {
      backend.routes['/assets/id/99'] = (_) => jsonResponse({'result': false, 'message': 'Asset bulunamadı'}, 404);
      await pumpAssets(tester, ['assets:read']);
      await tester.tap(find.text('ID'));
      await tester.pump();
      await search(tester, '99');

      expect(find.text('logo.png'), findsNothing);
      expect(find.text('Tekrar Dene'), findsOneWidget);
    });

    testWidgets('name search is trimmed and URL-encoded', (tester) async {
      await pumpAssets(tester, ['assets:read']);
      await search(tester, '  logo 2  ');

      expect(backend.requests.any((r) => r.url.path.endsWith('/assets/logo%202/paged')), isTrue);
    });
  });

  group('upload, replace, delete', () {
    testWidgets('single file → POST /assets with `file` and the selected folder as subFolder', (tester) async {
      FilePickerPlatform.instance = _FakePicker([file('a.png')]);
      final sent = <http.Request>[];
      backend.routes['/assets'] = (req) {
        sent.add(req);
        return okData({'id': 9});
      };
      await pumpAssets(tester, ['assets:read', 'assets:create']);
      await chip(tester, 'images');

      await tester.tap(find.byKey(const ValueKey('asset_upload_fab')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('upload_folder_field'))).controller!.text,
        'images',
        reason: 'prefilled with the browsed folder',
      );
      await tester.tap(find.byKey(const ValueKey('upload_pick_button')));
      await settle(tester);
      await tester.runAsync(() async {
        tester.widget<FilledButton>(find.byKey(const ValueKey('upload_send_button'))).onPressed!();
        for (var i = 0; i < 20 && sent.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await settle(tester);

      expect(sent.single.method, 'POST');
      final body = utf8.decode(sent.single.bodyBytes, allowMalformed: true);
      expect(body, contains('name="file"'));
      expect(body, isNot(contains('name="files"')));
      expect(body, contains('name="subFolder"\r\n\r\nimages'));
      expect(backend.requestsTo('/assets/multi'), isEmpty);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('no folder typed → no subFolder part; several files → /assets/multi', (tester) async {
      FilePickerPlatform.instance = _FakePicker([file('a.png'), file('b.png', 2), file('c.png', 3)]);
      final sent = <http.Request>[];
      backend.routes['/assets/multi'] = (req) {
        sent.add(req);
        return okData(<Object>[]);
      };
      await pumpAssets(tester, ['assets:read', 'assets:create']);

      await tester.tap(find.byKey(const ValueKey('asset_upload_fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('upload_pick_button')));
      await settle(tester);
      expect(find.text('3 dosya seçildi'), findsOneWidget);
      await tester.runAsync(() async {
        tester.widget<FilledButton>(find.byKey(const ValueKey('upload_send_button'))).onPressed!();
        for (var i = 0; i < 20 && sent.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await settle(tester);

      final body = utf8.decode(sent.single.bodyBytes, allowMalformed: true);
      expect(RegExp('name="files"').allMatches(body), hasLength(3));
      expect(body, isNot(contains('name="subFolder"')));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('upload error (quota) stays in the sheet with the backend message; send is re-enabled', (tester) async {
      FilePickerPlatform.instance = _FakePicker([file('a.png')]);
      backend.routes['/assets'] = (_) => jsonResponse({
        'result': false,
        'message': 'Depolama kotası aşıldı',
        'errorCode': 'STORAGE_QUOTA_EXCEEDED',
      }, 413);
      await pumpAssets(tester, ['assets:read', 'assets:create']);

      await tester.tap(find.byKey(const ValueKey('asset_upload_fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('upload_pick_button')));
      await settle(tester);
      await tester.runAsync(() async {
        tester.widget<FilledButton>(find.byKey(const ValueKey('upload_send_button'))).onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);

      expect(find.textContaining('Depolama kotası aşıldı'), findsOneWidget);
      expect(find.byKey(const ValueKey('upload_send_button')), findsOneWidget, reason: 'sheet still open');
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('upload_send_button'))).onPressed, isNotNull);
    });

    testWidgets('upload needs a file: send is disabled until one is picked', (tester) async {
      await pumpAssets(tester, ['assets:read', 'assets:create']);
      await tester.tap(find.byKey(const ValueKey('asset_upload_fab')));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('upload_send_button'))).onPressed, isNull);
    });

    testWidgets('replace file → PUT /assets/{id} multipart with `file`', (tester) async {
      FilePickerPlatform.instance = _FakePicker([file('new.png')]);
      final sent = <http.Request>[];
      backend.routes['/assets/1'] = (req) {
        sent.add(req);
        return okData({'id': 1});
      };
      await pumpAssets(tester, ['assets:read', 'assets:update']);

      await tester.tap(find.byKey(const ValueKey('asset_menu_1')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Dosyayı değiştir'));
        for (var i = 0; i < 20 && sent.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await settle(tester);

      expect(sent.single.method, 'PUT');
      expect(utf8.decode(sent.single.bodyBytes, allowMalformed: true), contains('name="file"'));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('single delete: confirm → DELETE /assets/{id}', (tester) async {
      final sent = <http.Request>[];
      backend.routes['/assets/1'] = (req) {
        sent.add(req);
        return okData(true);
      };
      await pumpAssets(tester, ['assets:read', 'assets:delete']);

      await tester.tap(find.byKey(const ValueKey('asset_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"logo.png" adlı asset silinecek'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm_delete_button')));
      await settle(tester);

      expect(sent.single.method, 'DELETE');
      expect(find.text('Asset silindi'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('permissions', () {
    Future<List<String>> menuLabels(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('asset_menu_1')));
      await tester.pumpAndSettle();
      final labels = [
        for (final item in tester.widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>)))
          (item.child as Text).data!,
      ];
      await tester.tapAt(const Offset(5, 5)); // dismiss
      await tester.pumpAndSettle();
      return labels;
    }

    testWidgets('read only: only "URL kopyala"; no upload button; long press does not select', (tester) async {
      await pumpAssets(tester, ['assets:read']);

      expect(await menuLabels(tester), ['URL kopyala']);
      expect(find.byKey(const ValueKey('asset_upload_fab')), findsNothing);
      await tester.longPress(find.text('logo.png'));
      await tester.pump();
      expect(find.textContaining('seçili'), findsNothing);
      expect(find.byKey(const ValueKey('bulk_delete_button')), findsNothing);
    });

    testWidgets('update: adds "Dosyayı değiştir" but no delete/select', (tester) async {
      await pumpAssets(tester, ['assets:read', 'assets:update']);
      expect(await menuLabels(tester), ['URL kopyala', 'Dosyayı değiştir']);
    });

    testWidgets('delete: adds "Sil" and "Seç" but no replace', (tester) async {
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      expect(await menuLabels(tester), ['URL kopyala', 'Sil', 'Seç']);
    });

    testWidgets('create: upload button shown, and hidden while selecting', (tester) async {
      await pumpAssets(tester, ['assets:read', 'assets:create', 'assets:delete']);
      expect(find.byKey(const ValueKey('asset_upload_fab')), findsOneWidget);

      await tester.longPress(find.text('logo.png'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('asset_upload_fab')), findsNothing);
    });

    testWidgets('menu "Seç" starts a selection', (tester) async {
      await pumpAssets(tester, ['assets:read', 'assets:delete']);
      await tester.tap(find.byKey(const ValueKey('asset_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seç'));
      await tester.pumpAndSettle();

      expect(find.text('1 seçili'), findsOneWidget);
    });
  });
}
