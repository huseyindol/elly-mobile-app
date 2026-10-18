import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:elly_mobile_app/config/modules_config.dart';
import 'package:elly_mobile_app/models/crud_module.dart';
import 'package:elly_mobile_app/providers/auth_provider.dart';
import 'package:elly_mobile_app/screens/crud/generic_crud_form_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
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
  get xFile => throw UnimplementedError('not used by the form');
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
  final File file;
  _FakePicker(this.file);
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
  }) async => [_PickedFile(file)];
}

void main() {
  late FakeBackend backend;
  late AuthProvider auth;

  setUp(() {
    backend = FakeBackend();
    auth = backend.newAuth();
    for (final path in ['/components/list/summary', '/banners/list/summary', '/widgets/list/summary', '/forms/list']) {
      backend.ok(path, <Object>[]);
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> pumpForm(WidgetTester tester, CrudModule module, [Map<String, dynamic>? item]) async {
    await tester.runAsync(() => backend.signIn(auth, ['${module.permissionKey}:update']));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
          home: GenericCrudFormScreen(module: module, initialData: item, apiService: backend.api),
        ),
      ),
    );
    await settle(tester);
  }

  /// Records the body of [method] requests to [path] and answers `{result: true, data: {}}`.
  List<http.Request> capture(String path, String method) {
    final sent = <http.Request>[];
    final previous = backend.routes[path];
    backend.routes[path] = (req) {
      if (req.method != method) return previous?.call(req) ?? http.Response('', 404);
      sent.add(req);
      return okData({'id': 1});
    };
    return sent;
  }

  Future<void> save(WidgetTester tester) async {
    // onPressed directly: at the 800x600 test size the bottom button sits under the scroll clip.
    tester.widget<ElevatedButton>(find.byKey(const ValueKey('crud_save_button'))).onPressed!();
    await settle(tester);
  }

  testWidgets('page edit: untouched component assignment is not sent', (tester) async {
    backend.ok('/pages/hakkimda', {
      'id': 7,
      'title': 'Hakkımda',
      'slug': 'hakkimda',
      'status': true,
      'components': [
        {'id': 1, 'name': 'Hero'},
      ],
    });
    final sent = capture('/pages/7', 'PUT');
    await pumpForm(tester, ModulesConfig.byKey('pages'), {'id': 7, 'slug': 'hakkimda'});

    await tester.enterText(find.byKey(const ValueKey('field_title')), 'Hakkımızda');
    await save(tester);

    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['title'], 'Hakkımızda');
    expect(body['slug'], 'hakkimda', reason: 'slug of an existing record is not regenerated');
    expect(body.containsKey('componentIds'), isFalse);
  });

  testWidgets('component edit: relations go back unchanged (backend null would clear them)', (tester) async {
    backend.ok('/components/3', {
      'id': 3,
      'name': 'Slider',
      'type': 'BANNER',
      'orderIndex': 0,
      'status': true,
      'pageIds': [7],
      'banners': [
        {'id': 11, 'title': 'A'},
      ],
    });
    final sent = capture('/components/3', 'PUT');
    await pumpForm(tester, ModulesConfig.byKey('components'), {'id': 3});

    expect(find.byKey(const ValueKey('field_bannerIds')), findsOneWidget);
    expect(find.byKey(const ValueKey('field_widgetIds')), findsNothing, reason: 'other types hidden');
    await save(tester);

    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['bannerIds'], [11]);
    expect(body['pageIds'], [7]);
    expect(body['widgetIds'], isEmpty);
    expect(body['formIds'], isEmpty);
  });

  testWidgets('new page: slug follows the title until typed', (tester) async {
    await pumpForm(tester, ModulesConfig.byKey('pages'));

    await tester.enterText(find.byKey(const ValueKey('field_title')), 'Şirket Hakkında');
    expect(find.text('sirket-hakkinda'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field_slug')), 'ozel');
    await tester.enterText(find.byKey(const ValueKey('field_title')), 'Başka');
    expect(find.text('ozel'), findsOneWidget);
  });

  testWidgets('banner create, upload mode: data part without local keys + picked file part', (tester) async {
    final dir = Directory.systemTemp.createTempSync('elly_form_test');
    final png = File('${dir.path}/desktop.png')..writeAsBytesSync([137, 80, 78, 71]);
    FilePickerPlatform.instance = _FakePicker(png);
    final sent = capture('/banners', 'POST');
    await pumpForm(tester, ModulesConfig.byKey('banners'));

    expect(
      find.byKey(const ValueKey('field_images.desktop')),
      findsNothing,
      reason: 'URL inputs hidden in upload mode',
    );
    await tester.enterText(find.byKey(const ValueKey('field_title')), 'Kampanya');
    final pick = find.descendant(of: find.byKey(const ValueKey('field_desktop')), matching: find.text('Seç'));
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await settle(tester);
    // Multipart reads the file with real IO → start it inside runAsync.
    await tester.runAsync(() async {
      tester.widget<ElevatedButton>(find.byKey(const ValueKey('crud_save_button'))).onPressed!();
      for (var i = 0; i < 20 && sent.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await settle(tester);

    final body = utf8.decode(sent.single.bodyBytes, allowMalformed: true);
    expect(sent.single.headers['content-type'], startsWith('multipart/form-data'));
    expect(body, contains('name="desktop"'));
    expect(body, isNot(contains('name="tablet"')));
    final data = RegExp(r'name="data"\r\n\r\n(.*?)\r\n', dotAll: true).firstMatch(body)!.group(1)!;
    final json = jsonDecode(data) as Map<String, dynamic>;
    expect(json['title'], 'Kampanya');
    expect(json.containsKey('_imageMode'), isFalse);
    dir.deleteSync(recursive: true);
  });

  testWidgets('post with unsupported HTML: warning, raw mode, body saved unchanged', (tester) async {
    const html = '<p>x</p><table><tr><td>1</td></tr></table>';
    backend.ok('/posts/5', {'id': 5, 'title': 'T', 'slug': 't', 'content': html});
    final sent = capture('/posts/5', 'PUT');
    await pumpForm(tester, ModulesConfig.byKey('posts'), {'id': 5});

    expect(find.byKey(const ValueKey('rich_text_warning')), findsOneWidget);
    expect(find.byKey(const ValueKey('rich_text_raw')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('field_title')), 'T2');
    await save(tester);

    expect((jsonDecode(sent.single.body) as Map)['content'], html);
  });

  testWidgets('post with Tiptap HTML: editor mode, untouched body saved byte-for-byte', (tester) async {
    const html = '<h2>Başlık</h2><p>Merhaba <strong>dünya</strong></p>';
    backend.ok('/posts/6', {'id': 6, 'title': 'T', 'slug': 't', 'content': html});
    final sent = capture('/posts/6', 'PUT');
    await pumpForm(tester, ModulesConfig.byKey('posts'), {'id': 6});

    expect(find.byKey(const ValueKey('rich_text_warning')), findsNothing);
    expect(find.byKey(const ValueKey('rich_text_raw')), findsNothing);
    await save(tester);

    expect((jsonDecode(sent.single.body) as Map)['content'], html);
    await tester.pump(const Duration(seconds: 5)); // editor/snackbar timers
  });

  testWidgets('contents: metadata fields follow the content type; type locked when editing', (tester) async {
    await pumpForm(tester, ModulesConfig.byKey('contents'));
    expect(find.byKey(const ValueKey('field_metadata.name')), findsOneWidget);
    expect(find.byKey(const ValueKey('field_metadata.company')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('field_contentType_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deneyimler').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('field_metadata.name')), findsNothing);
    expect(find.byKey(const ValueKey('field_metadata.company')), findsOneWidget);
    expect(find.text('portfolio_experience'), findsOneWidget, reason: 'section key template follows the type');
  });

  testWidgets('banner edit with stored images opens in URL mode (inputs visible, URLs filled)', (tester) async {
    await pumpForm(tester, ModulesConfig.byKey('banners'), {
      'id': 4,
      'title': 'Kampanya',
      'images': {'desktop': 'assets/t/t1/images/d.png', 'tablet': null, 'mobile': null},
    });

    expect(find.text('URL gir'), findsOneWidget);
    expect(find.byKey(const ValueKey('field_images.desktop')), findsOneWidget);
    expect(find.text('assets/t/t1/images/d.png'), findsOneWidget);
    expect(find.byKey(const ValueKey('field_desktop')), findsNothing);
  });

  testWidgets('banner edit without images opens in upload mode', (tester) async {
    await pumpForm(tester, ModulesConfig.byKey('banners'), {'id': 5, 'title': 'Boş', 'images': null});

    expect(find.text('Dosya yükle'), findsOneWidget);
    expect(find.byKey(const ValueKey('field_desktop')), findsOneWidget);
    expect(find.byKey(const ValueKey('field_images.desktop')), findsNothing);
  });

  testWidgets('invalid form: no request, "N alan hatalı" and the first error is shown', (tester) async {
    final sent = capture('/pages', 'POST');
    await pumpForm(tester, ModulesConfig.byKey('pages'));

    await save(tester);
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
    expect(find.text('2 alan hatalı: Başlık'), findsOneWidget, reason: 'title + slug required, first named');
    expect(find.text('Başlık zorunlu'), findsOneWidget);
  });

  group('leaving with unsaved changes', () {
    Future<void> pumpInNavigator(WidgetTester tester) async {
      await tester.runAsync(() => backend.signIn(auth, ['pages:update']));
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        GenericCrudFormScreen(module: ModulesConfig.byKey('pages'), apiService: backend.api),
                  ),
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await settle(tester);
    }

    testWidgets('untouched form pops without asking', (tester) async {
      await pumpInNavigator(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(GenericCrudFormScreen), findsNothing);
    });

    testWidgets('edited form asks; "Kal" stays, "Çık" leaves', (tester) async {
      await pumpInNavigator(tester);
      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Taslak');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      await tester.tap(find.text('Kal'));
      await tester.pumpAndSettle();
      expect(find.byType(GenericCrudFormScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_leave_button')));
      await tester.pumpAndSettle();
      expect(find.byType(GenericCrudFormScreen), findsNothing);
    });

    testWidgets('a toggled switch also counts as a change', (tester) async {
      await pumpInNavigator(tester);
      await tester.tap(find.byKey(const ValueKey('field_status')));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
    });
  });

  group('AI generation', () {
    testWidgets('page form: AI slug, description, and SEO generation populate fields', (tester) async {
      backend.ok('/ai/slug', {'slug': 'ai-uretilen-slug'});
      backend.ok('/ai/description', {'description': 'AI sayfa açıklaması'});
      backend.ok('/ai/seo', {
        'seoTitle': 'AI SEO Başlığı',
        'seoDescription': 'AI SEO Açıklaması',
        'seoKeywords': 'flutter, cms, ai',
      });
      final sent = capture('/pages', 'POST');
      await pumpForm(tester, ModulesConfig.byKey('pages'));

      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Hakkımızda Sayfası');
      await tester.pump();

      tester.widget<IconButton>(find.byKey(const ValueKey('ai_button_slug'))).onPressed!();
      await settle(tester);

      tester.widget<IconButton>(find.byKey(const ValueKey('ai_button_description'))).onPressed!();
      await settle(tester);

      tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('ai_section_seo'))).onPressed!();
      await settle(tester);

      await save(tester);
      expect(sent, hasLength(1));
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['slug'], 'ai-uretilen-slug');
      expect(body['description'], 'AI sayfa açıklaması');
      expect(body['seoInfo'], {
        'title': 'AI SEO Başlığı',
        'description': 'AI SEO Açıklaması',
        'keywords': 'flutter, cms, ai',
        'canonicalUrl': '/ai-uretilen-slug',
        'noIndex': false,
        'noFollow': false,
      });
    });

    testWidgets('post form: AI article and blog-info generation populate content and metadata', (tester) async {
      backend.ok('/ai/article', {'html': '<h2>Giriş</h2><p>Bu bir AI makalesidir.</p>'});
      backend.ok('/ai/blog-info', {
        'description': 'Kısa blog özeti',
        'category': 'Teknoloji',
        'readingTime': '4 dk',
        'imagePrompt': 'modern cloud server illustration',
      });
      final sent = capture('/posts', 'POST');
      await pumpForm(tester, ModulesConfig.byKey('posts'));

      await tester.enterText(find.byKey(const ValueKey('field_title')), 'Bulut Mimarisi');
      await tester.pump();

      // Open AI Article dialog and submit
      tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('ai_section_article'))).onPressed!();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai_article_topic')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('ai_article_keywords')), 'cloud, k8s');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ai_article_submit')));
      await tester.pumpAndSettle();
      await settle(tester);

      // Generate blog info from title + generated article content
      tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('ai_section_blog_info'))).onPressed!();
      await settle(tester);

      await save(tester);
      expect(sent, hasLength(1));
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['content'], contains('Bu bir AI makalesidir.'));
      expect(body['description'], 'Kısa blog özeti');
      expect(body['category'], 'Teknoloji');
      expect(body['readingTime'], '4 dk');
      expect(
        body['coverImage'],
        'https://image.pollinations.ai/prompt/modern%20cloud%20server%20illustration?width=1600&height=900&nologo=true',
      );
      expect(body['publishedAt'], isNotNull);
    });

    testWidgets('post form: live preview renders article in Mobile Web and Desktop viewports', (tester) async {
      final postRecord = {
        'id': 42,
        'title': 'Spring Boot ve Kubernetes Rehberi',
        'slug': 'spring-boot-k8s',
        'content': '<h2>Mimari</h2><p>Bu makalede <strong>mikroservis</strong> mimarisini inceliyoruz.</p>',
        'description': 'Adım adım üretim ortamı kurulumu',
        'category': 'DevOps',
        'author': 'Hüseyin DOL',
        'readingTime': '6 dk',
        'publishedAt': '2026-10-18',
        'status': true,
      };
      backend.ok('/posts/42', postRecord);
      await pumpForm(tester, ModulesConfig.byKey('posts'), postRecord);

      expect(find.byKey(const ValueKey('post_preview_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('post_section_preview_button')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('post_preview_button')));
      await tester.pumpAndSettle();

      expect(find.text('Canlı Site Önizlemesi (elly-tenant)'), findsOneWidget);
      expect(find.byKey(const ValueKey('post_preview_frame_mobile')), findsOneWidget);
      expect(find.text('Spring Boot ve Kubernetes Rehberi'), findsWidgets);
      expect(find.text('Adım adım üretim ortamı kurulumu'), findsWidgets);
      expect(find.text('DevOps'), findsWidgets);
      expect(find.text('6 dk okuma'), findsOneWidget);
      expect(find.textContaining('mikroservis'), findsWidgets);

      // Switch to Desktop viewport
      await tester.tap(find.byKey(const ValueKey('post_preview_viewport_desktop')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post_preview_frame_desktop')), findsOneWidget);

      // Toggle Light/Dark theme
      await tester.tap(find.byKey(const ValueKey('post_preview_theme_toggle')));
      await tester.pumpAndSettle();

      // Close preview
      await tester.tap(find.byKey(const ValueKey('post_preview_close')));
      await tester.pumpAndSettle();
      expect(find.text('Canlı Site Önizlemesi (elly-tenant)'), findsNothing);
    });
  });
}
