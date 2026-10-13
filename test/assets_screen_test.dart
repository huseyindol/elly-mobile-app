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

void main() {
  group('assetsEndpoint', () {
    test('folder / name combinations map to the backend paged endpoints', () {
      expect(assetsEndpoint(), '/assets/list/paged?sort=id,desc');
      expect(assetsEndpoint(folder: 'images'), '/assets/list/images/paged?sort=id,desc');
      expect(assetsEndpoint(name: ' logo '), '/assets/logo/paged?sort=id,desc');
      expect(assetsEndpoint(folder: 'images', name: 'logo'), '/assets/images/logo/paged?sort=id,desc');
      expect(assetsEndpoint(folder: 'a b', name: 'ç/x'), '/assets/a%20b/%C3%A7%2Fx/paged?sort=id,desc');
    });
  });

  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    backend.ok('/assets/sub-folders', ['images', 'docs']);
    backend.ok(
      '/assets/list/paged',
      _page([
        {
          'id': 1,
          'name': 'logo.png',
          'path': 'assets/t/t1/images/logo.png',
          'type': 'image/png',
          'subFolder': 'images',
        },
        {'id': 2, 'name': 'cv.pdf', 'path': 'assets/t/t1/files/cv.pdf', 'type': 'application/pdf', 'subFolder': 'docs'},
      ]),
    );
  });

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

  testWidgets('lists assets with folder chips; a chip browses that folder', (tester) async {
    backend.ok(
      '/assets/list/images/paged',
      _page([
        {'id': 1, 'name': 'logo.png', 'path': 'x.png', 'type': 'image/png'},
      ]),
    );
    await pumpAssets(tester, ['assets:read']);

    expect(find.text('logo.png'), findsOneWidget);
    expect(find.text('cv.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('asset_upload_fab')), findsNothing, reason: 'no assets:create');

    await tester.tap(find.byKey(const ValueKey('folder_images')));
    await settle(tester);
    expect(backend.requestsTo('/assets/list/images/paged'), hasLength(1));
    expect(find.text('cv.pdf'), findsNothing);
  });

  testWidgets('name search hits the server search endpoint, ID search the by-id endpoint', (tester) async {
    backend.ok(
      '/assets/logo/paged',
      _page([
        {'id': 1, 'name': 'logo.png', 'path': 'x.png'},
      ]),
    );
    backend.ok('/assets/id/2', {'id': 2, 'name': 'cv.pdf', 'path': 'y.pdf'});
    await pumpAssets(tester, ['assets:read']);

    await tester.enterText(find.byKey(const ValueKey('asset_search_field')), 'logo');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(backend.requestsTo('/assets/logo/paged'), hasLength(1));
    expect(find.text('cv.pdf'), findsNothing);

    await tester.tap(find.text('ID'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('asset_search_field')), '2');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(backend.requestsTo('/assets/id/2'), hasLength(1));
    expect(find.text('cv.pdf'), findsOneWidget);
  });

  testWidgets('long-press selects; bulk delete posts the ids and reports failures', (tester) async {
    final sent = <http.Request>[];
    backend.routes['/assets/bulk-delete'] = (req) {
      sent.add(req);
      return okData({
        'deletedCount': 1,
        'failedIds': [2],
      });
    };
    await pumpAssets(tester, ['assets:read', 'assets:delete']);

    await tester.longPress(find.text('logo.png'));
    await tester.pump();
    await tester.tap(find.text('cv.pdf'));
    await tester.pump();
    expect(find.text('2 seçili'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk_delete_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm_bulk_delete_button')));
    await settle(tester);

    expect(jsonDecode(sent.single.body), {
      'ids': [1, 2],
    });
    expect(find.textContaining('1 silinemedi'), findsOneWidget);
    expect(find.text('2 seçili'), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('multi upload: several files → /assets/multi with subFolder', (tester) async {
    final dir = Directory.systemTemp.createTempSync('elly_assets_test');
    FilePickerPlatform.instance = _FakePicker([
      File('${dir.path}/a.png')..writeAsBytesSync([1]),
      File('${dir.path}/b.png')..writeAsBytesSync([2]),
    ]);
    final sent = <http.Request>[];
    backend.routes['/assets/multi'] = (req) {
      sent.add(req);
      return okData(<Object>[]);
    };
    await pumpAssets(tester, ['assets:read', 'assets:create']);

    await tester.tap(find.byKey(const ValueKey('asset_upload_fab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('upload_folder_field')), 'images');
    await tester.tap(find.byKey(const ValueKey('upload_pick_button')));
    await settle(tester);
    expect(find.text('2 dosya seçildi'), findsOneWidget);
    await tester.runAsync(() async {
      tester.widget<FilledButton>(find.byKey(const ValueKey('upload_send_button'))).onPressed!();
      for (var i = 0; i < 20 && sent.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await settle(tester);

    final body = utf8.decode(sent.single.bodyBytes, allowMalformed: true);
    expect(RegExp('name="files"').allMatches(body), hasLength(2));
    expect(body, contains('name="subFolder"\r\n\r\nimages'));
    await tester.pump(const Duration(seconds: 3));
    dir.deleteSync(recursive: true);
  });
}
