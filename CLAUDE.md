# Elly Mobile App — Claude Code Proje Rehberi

`elly-admin` yönetim panelinin **Flutter** mobil karşılığı: sayfa, bileşen, post, içerik, widget, banner,
form ve asset yönetimi. Backend: `elly-backend` (Spring Boot, db-per-tenant). Bu repo `elly-studio`
orchestrator'ının bir parçasıdır; çapraz repo kuralları kökteki `AGENTS.md`'dedir.

## Stack

| Katman | Teknoloji |
|---|---|
| Framework | Flutter 3.x (Dart `^3.13`), Material 3, koyu tema |
| State | `provider` (`ChangeNotifier`) — `AuthProvider` |
| HTTP | `http` + `http_parser`/`mime` (multipart) |
| Güvenli depo | `flutter_secure_storage` (accessToken, refreshToken, tenantId) |
| Dosya seçimi | `file_picker` |
| Zengin metin | `flutter_quill` 11.6.0 (MIT) + `html` 0.15.7 (BSD) — kendi HTML ↔ Delta kodeği |
| Test | `flutter_test`, `integration_test` |
| Lint | `flutter_lints` (`analysis_options.yaml`) |

## Dizin yapısı

```
lib/
├── main.dart                      # MultiProvider + AuthWrapper (login ↔ dashboard; çıkışta yığın temizliği)
├── config/
│   ├── app_theme.dart             # TEK renk kaynağı: AppColors + appTheme (colorScheme)
│   ├── modules_config.dart        # CRUD modül tanımları (tek kaynak); başlıklar admin sidebar etiketleri
│   └── nav_config.dart            # drawer menüsü: admin Sidebar grupları/sırası/permission'ları (NavGroup/NavItem)
├── models/                        # crud_module.dart (CrudModule/FieldConfig/RequestMode), login_response.dart
├── providers/auth_provider.dart   # login (+2FA adımı) / logout / oturum + permission durumu
├── services/
│   ├── api_service.dart           # tüm HTTP istekleri, header'lar, 401 → refresh
│   ├── crud_payload.dart          # saf: getPath/setPath, buildPayload (ilişki semantiği), extractItems, paging, compareByKey
│   ├── rich_text_codec.dart       # saf: Tiptap HTML ↔ Quill Delta, analyzeHtml (desteklenmeyen içerik tespiti)
│   ├── form_schema.dart           # saf: form şeması kuralları, koşul değerlendirici (admin/tenant JS anlamı), formatPayloadValue
│   └── text_format.dart           # saf: foldTr (Türkçe arama anahtarı), upperTr, formatBytes, slugify, formatDateTimeTr
├── screens/
│   ├── login_screen.dart
│   ├── dashboard_screen.dart      # admin dashboard özet kartları + son e-postalar/yazılar (permission'a göre)
│   ├── coming_soon_screen.dart    # mobilde henüz olmayan admin alanları için yer tutucu
│   ├── assets_screen.dart         # Medya: klasör, sunucu araması, çoklu yükleme, toplu silme (generic'e sığmıyor)
│   ├── forms/                     # form builder alt ekranları: alanlar + alan düzenleme, önizleme, gönderimler (+ detay)
│   └── crud/generic_crud_{list,form}_screen.dart
└── widgets/                       # ortak bileşenler — yeni ekranlar bunları kullanır
    ├── app_scaffold.dart          # AppScaffold (cam AppBar + AmbientBackground + opsiyonel drawer + bottomNavigationBar)
    ├── app_snack_bar.dart         # showAppSnackBar (tek SnackBar yolu) · reportInvalidFields (kaydır + "N alan hatalı: Etiket")
    ├── reorder_controls.dart      # ReorderableRow (ekran okuyucu "Yukarı/Aşağı taşı") · ReorderControls (Taşı menüsü + tutamaç)
    ├── app_drawer.dart            # AppDrawer(currentId) + openNavItem + isNavItemVisible + avatarInitials
    ├── state_views.dart           # LoadingView (semanticsLabel) · ErrorView (Tekrar Dene) · EmptyView
    ├── confirm_dialog.dart        # showConfirmDialog (destructive: kırmızı onay) · confirmLeaveForm (Çık/Kal)
    ├── save_bar.dart              # SaveBar: formların sabit alt Kaydet çubuğu
    ├── form_schema_editor.dart    # FormField<Map>: form şeması builder'ı (düzen, adımlar, alanlar, önizleme)
    ├── searchable_paged_list.dart # liste gövdesi: arama, filtre/sıralama, pull-to-refresh, /list/paged sonsuz kaydırma
    ├── relation_multi_select.dart # FormField<List<Object>>: ilişki id listesi seçici (componentIds, …)
    ├── rich_text_field.dart       # HTML gövde editörü (Quill; desteklenmeyen HTML → ham HTML modu)
    └── asset_picker.dart          # showAssetPicker (görsel assetten mutlak URL), AssetThumbnail, isImageAsset
test/                              # unit/widget testleri (helpers/fake_backend.dart) + opt-in canlı sözleşme testi
└── fixtures/                      # admin TS kaynağından üretilen beklenen sonuçlar (gen_form_fixtures.ts, bun) + admin form JSON'u
integration_test/                  # cihaz/simülatörde uçtan uca test
```

## Mimari kurallar

- **Tüm istekler `ApiService` üzerinden.** `X-Tenant-Id` ve `Authorization: Bearer` header'larını o ekler;
  401'de tek bir `/auth/refresh` çağrısını paylaştırır, başarısızsa `onSessionExpired` → logout.
  Ekranlarda doğrudan `http` kullanma.
- Yanıtlar `{ "result": true, "data": ... }` sarmalıdır; `ApiService` `data`'yı döner, sayfalı listelerde
  `data.content` → `extractItems`. Hatalar backend `ErrorResponse`'tan (`message`, `validationErrors`,
  `details`) `ApiException` mesajına çevrilir.
- **Dinamik CRUD:** yönetim ekranları `ModulesConfig.allModules`'tan render edilir
  (`GenericCrudListScreen` / `GenericCrudFormScreen`). Yeni modül/alan = önce `modules_config.dart`.
  - Her modül backend'deki `Dto*IU` sınıfını yansıtır (`elly-backend/src/main/java/com/cms/dto`).
  - Gönderilen payload **yalnız `payloadKeys`** içerir (kayıt ⊕ form değerleri; formda olmayan alanlar
    kayıttan korunur).
  - **İlişki id listeleri — backend semantiği farklı, karıştırma** (`FieldType.relation`):
    - `pages.componentIds`: backend `null` = dokunma, `[]` = temizle → `relationKeepsOnNull: true`, yalnız
      seçim değişince gönderilir.
    - `components` (`pageIds/bannerIds/widgetIds/formIds`) ve `widgets` (`bannerIds/postIds`): backend
      `null` = **TEMİZLE** → her kayıtta gönderilir; dokunulmamışsa detay kaydındaki id'ler
      (`relationSource`: `banners`, `widgets`…) aynen geri gider. `pageIds`'in alanı yok, kayıttan geri gider.
    - `visibleWhen` ile gizlenen ilişki (component/widget tipi değişince) `[]` gönderilir (admin de öyle;
      backend tip uyuşmazlığını reddeder). Gizlenen diğer alanlar yazılmaz.
    - Bu yüzden component/widget/page düzenlemesi **mutlaka detay endpoint'inden** yapılır (`detailEndpoint`).
  - `RequestMode`: `json` · `multipartData` (banners: `data` JSON part + dosyalar) ·
    `multipartFields` (assets: düz alanlar + `file`).
  - Alan tipleri: `relation` · `richText` · `date` (`YYYY-MM-DD`) · `tags` (virgülle → `List<String>`) ·
    `imageUrl` (önizleme + "Assetlerden seç", `assets:read` varsa) · `formSchema` (form builder, aşağıda).
    `requiredWhen` (örn. `{'notificationEnabled': true}`) koşullu zorunluluk; uzak dropdown'da
    `optionsPermission` yoksa seçenek istenmez, `optionLabelOf` etiketi, `currentOptionLabel` listede olmayan
    mevcut değeri gösterir. `CrudModule.recordLink` liste satırına ve düzenleme AppBar'ına kayda bağlı ekran
    ekler (formlar → Yanıtlar). `_` ile başlayan anahtar yerel form
    durumudur, gönderilmez ve kayıttan okunmaz (banner `_imageMode`: `initialValueOf` → kayıtta görsel varsa
    `url`, yoksa `upload`). `slugFrom` yalnız yeni kayıtta, slug elle değişene kadar. Dosya alanı `imageOnly`
    → görsel filtresi + 5 MB (admin `ImageUploadBox`), `currentImageKey` mevcut görseli önizler.
  - Tamamen boş SEO bloğu, kayıtta `seoInfo` yoksa gönderilmez; varsa düzenlendiği gibi gider.
  - **Form UX:** her değişiklik (metin, dropdown, switch, tarih, dosya, ilişki, zengin metin) formu kirletir;
    `PopScope` kirliyken ya da kayıt sürerken çıkışta yıkıcı onay ister. Doğrulama hatasında
    `validateGranularly` → `reportInvalidFields`: ilk hatalı alana kaydırma + "N alan hatalı: <ilk alanın
    etiketi>". Kaydet sabit alt çubukta: `AppScaffold(bottomNavigationBar: SaveBar(...))` — Scaffold
    SnackBar'ı çubuğun **üstünde** gösterir (butonu örtmez), çubuk klavyenin üstüne çıkar; SaveBar'ı body'ye
    koyma. Başarılı kayıt/uygula pop'tan önce `clearSnackBars()` (eski hata sonraki ekrana taşınmaz).
    Yeni form ekranları aynı parçaları kullanır: `SaveBar`, `confirmLeaveForm`, `fieldDecoration` (app_theme;
    `"Etiket *"` etiketi ekran okuyucuda "zorunlu" okunur).
  - Banner görselleri: backend dosya gelince URL'leri yok sayar (create'te tamamen düşürür) → admin gibi
    "Dosya yükle / URL gir" modu; yalnız görünen dosya alanları gönderilir.
  - İçerikler: metadata alanları `contentType`'a göre (admin `schemas/dynamic` skills/experience); tip
    düzenlemede kilitli; kayıttaki bilinmeyen metadata anahtarları korunur.
  - Şablon (`template`) serbest metin: admin listeyi tenant sitesinden sunucu env'iyle çeker, mobilde yok.
- **Formlar (form builder):** generic CRUD ekranı + `FieldType.formSchema` (`FormSchemaEditor`). Şema backend
  `FormSchema` (`{config, fields, steps}`) **ham map** olarak düzenlenir — tenant sitesi formu bu JSON ile render
  eder: dokunulmamış şema bayt bayt geri gider (backend şema değişince `version` artırır), bilinmeyen alan
  tipi/anahtar (`config` serbest map dahil) korunur; yalnız düzenlenen alan admin modalı gibi normalize edilir
  (`normalizeField`: seçenek yalnız select/radio/multi_checkbox, boş validation/condition → null, boş stepId yok).
  Koşul değeri/seçenek değeri metni değişmediyse orijinal tipli değer (`18`) kalır. `validation.min/max` tam
  sayı (backend `Integer`), pattern geçerli RegExp olmalı (geçersiz pattern sitede formu kırar). Alan ID'si
  değişince ona bakan koşullar taşınır (admin taşımaz). Kayıt kontrolü (`schemaError`): ≥1 alan; sihirbazda ≥1
  adım ve her alan **var olan** bir adımda. Sihirbazdan çıkınca `steps` gönderilmez (admin gibi), geri dönünce
  geri gelir. Alan listesi ayrı ekranda (`FormFieldsScreen`, sürükle-sırala otomatik kaydırsın diye
  ReorderableListView ekranın kaydırıcısı; "Değişiklikler formu Kaydet'te gönderilir" notu; silme/taşıma sonrası
  "Geri al" SnackBar'ı); alan düzenleme tam ekran (`FieldEditScreen`, "Uygula"; mevcut alanda değişiklik yoksa
  alana dokunmaz, **yeni alan her zaman doğrulanır**; min > max reddedilir). Şema hatası gösterilirken her
  değişiklikte yeniden doğrulanır (düzelen hata hemen kalkar). Zorunlu uzak dropdown boşsa sebep helper metninde
  (`emptyOptionsHint` / izin yok). Önizleme `evaluateCondition`/`isFormFieldVisible` ile (admin/tenant
  `condition-evaluator.ts` JavaScript `String()`/`Number()` anlamı; fixture testi 1875 vaka) — doğrulama ve
  adım sayfalama yok, "Gönder" görünür alanların payload'ını gösterir. Bildirim: gönderici/alıcı yalnız
  `notificationEnabled` açıkken zorunlu (backend `validateNotificationConfig`; admin Zod her zaman istiyor),
  gönderici `/mail-accounts/active` (`mail:read`). Silme: yalnız **409**'da zorla silme önerilir
  (`/forms/{id}/force`, backend ADMIN/SUPER_ADMIN rolü ister). Gönderimler (`forms:read`):
  `/forms/{id}/submissions/paged?sort=submittedAt,desc` + `/count`; değerler şema etiketi/seçenek etiketiyle
  (`formatPayloadValue` = admin), detayda şemada olmayan payload anahtarları da görünür. Admin'de ve backend'de
  gönderim silme/dışa aktarma yok → mobilde de yok.
- **Zengin metin (posts `content`):** `RichTextField` + `rich_text_codec.dart`. Kodek yalnız admin Tiptap
  alt kümesini (p, h1–h6, ul/ol>li>p iç içe, blockquote>p, pre>code[language-*], hr, img[src,alt,title],
  br, strong/em/s/u/code/a) kabul eder; başka her şey (tablo, iframe, div, span, style/class…) →
  `analyzeHtml` desteklenmiyor der → uyarı + **ham HTML modu** (içerik bayt bayt korunur). Dokunulmamış
  gövde aynen geri gönderilir; yalnız değiştiyse Delta → Tiptap biçimli HTML. Yapıştırma düz metin
  (`enableExternalRichPaste: false`). Görsel imlecin satırını bölerek **kendi satırına** eklenir; alt metni
  embed op'unun özniteliğinde (`compose`; `formatText` registry dışı özniteliği uygulamaz). `opsToHtml`
  metinle aynı satıra düşmüş embed'i ayırır, embed satırına blok özniteliği vermez.
  **URL güvenliği** (site post HTML'ini sanitize etmeden basar): kodek `javascript:`/`vbscript:`/`data:`
  href/src'yi (boşluk/kontrol karakteri temizlenmiş şemada) reddeder → ham HTML modu; `opsToHtml` bunları
  yazmaz; editörde link `isAllowedUrl(link: true)` (http/https/mailto/tel/göreli), görsel http(s)/göreli.
  `MaterialApp` `FlutterQuillLocalizations.localizationsDelegates`
  ister (widget testlerinde de). `flutter_quill_delta_from_html` kullanma: Tiptap çıktısında inline code,
  kod satır sonları ve img alt'ı düşürüyor, `<br>`/`<hr>` sonrası paragrafları birleştiriyor.
- **Dosya URL'leri:** `ApiService.fileUrl(path)` — `assets/t/…` → `<api origin>/assets/t/…` (admin/tenant
  `getImageUrl` ile aynı; `/assets/**` auth'suz). Asset seçici mutlak URL döner.
- Endpoint'ler `/api/v1` köküne görelidir (`ApiService.baseUrl`; varsayılan prod, build'de
  `--dart-define=API_BASE_URL=...` ile değişir). Yeni bir kök/endpoint backend'de yoksa
  **kullanma** — sözleşme önce backend'de değişir (kök `AGENTS.md` → contract-first).
- Giriş `loginType: 'admin'` ile panel kullanıcısı gibi yapılır. **2FA destekleniyor (yalnız doğrulama
  adımı):** `mfaRequired=true` → login ekranı 6 haneli kod adımına geçer → `POST /auth/mfa/verify
  { mfaToken, code }` (Authorization yok, `X-Tenant-Id` login'deki tenant). 2FA kurulumu/kapatma panelden
  yapılır, mobilde yok. Panelde olduğu gibi sosyal giriş yok.
- **Navigasyon:** dashboard kök ekrandır; `AppDrawer` admin `Sidebar.tsx` gruplarını aynı sırayla gösterir
  (Gösterge Paneli · İçerik Yönetimi · Bileşenler · Medya · Etkileşim · İletişim · Sistem) + profil başlığı
  (Türkçe baş harfler + rol etiketi) + çıkış. Her bölüm ekranında drawer vardır (`AppScaffold(navId:)`,
  aktif öğe vurgulu). `openNavItem` yığını `[dashboard, bölüm]` tutar (popUntil(isFirst) + push); alt ekranlar
  (form vb.) `navId` vermez → geri butonu. Bottom nav yok: 16 hedef 5 sekmeye sığmaz ve menü admin ile
  birebir kalır. Yeni alan = `nav_config.dart`'ta `NavItem` (CRUD ise `NavItem.crud(key)`);
  `module == null` olan öğe "Yakında" ekranını açar — faz tamamlanınca gerçek ekrana bağlanır.
- **Oturum sonu:** `EllyMobileApp.navigatorKey`; `AuthWrapper` oturum düşünce (logout ya da refresh başarısız)
  `popUntil(isFirst)` ile tüm ekran/dialog/sheet'leri kapatır — sonraki kullanıcı eski ekranı görmez.
- **Ekran iskeleti:** yeni ekranlar `AppScaffold` (ya da yalnız arka plan için `AmbientBackground`) kullanır;
  ambient ışık / blur AppBar kopyalanmaz.
- **Dashboard:** kartlar ve endpoint'ler admin `dashboard/page.tsx` ile aynıdır; yetkisi olmayan kart ne
  gösterilir ne istenir. Her kartın isteği bağımsızdır (hata → karta dokun = tekrar dene); pull-to-refresh
  permission'ları ve tüm kartları yeniler (çalışırken kilitli; izin yenileme hatası SnackBar). Kartlar sabit
  en-boy oranı kullanmaz; ölçekli genişlik ≥260 dp ise iki sütun (320–430 dp telefonlar), büyük yazıda tek.
  "Depolama Kullanımı" kartı admin `StorageUsageWidget` ile aynı: `GET /storage/tenant/{tenantId}/quota`
  (oturum tenant'ı yoksa `/storage/quota`), eşikler <70 yeşil · 70–90 amber · ≥90 kırmızı.
- **Listeler:** `SearchablePagedList` — `paged: true` ise `page`/`size` eklenir (`PagedResponse.last`'a kadar
  sonraki sayfa; mevcut query, tekrarlı `sort` dahil, korunur). Arama istemci tarafında ve `foldTr` iledir
  (backend list endpoint'lerinde arama parametresi yok); sorgu doluyken sonraki sayfa otomatik değil,
  "Daha fazla ara" ile yüklenir. Yenileme sırasında eski liste + ince ilerleme çubuğu; hata → SnackBar.
  Alt padding FAB payı bırakır. Dışarıdan yenileme `GlobalKey<SearchablePagedListState>().currentState.reload()`.
  Admin tabloları gibi istemci sıralaması `CrudModule.sortKey` (`compareByKey`: sayı/foldTr, eşitlikte id),
  `statusKey` rozet, `thumbnailKey` görsel, `listMeta` ek satırlar; çip satırları sabit yükseklik
  kullanmaz (yazı ölçeği); `ListFilter` çipleri sunucu
  (`endpointTemplate`, banner klasörü) ya da istemci (`key`, içerik tipi) filtresidir.
- **Assetler:** `AssetsScreen` (drawer `assets` öğesi). Klasör: `/assets/list/{klasör}/paged`; arama sunucuda:
  ad `/assets/{ad}/paged` (klasörle `/assets/{klasör}/{ad}/paged`), ID `/assets/id/{id}`; tek dosya
  `POST /assets` (`file`), çoklu `POST /assets/multi` (`files`), `subFolder` opsiyonel; değiştir `PUT
  /assets/{id}` (`file`; görsel asset yalnız görselle, ≤5 MB); toplu silme `POST /assets/bulk-delete {ids}` →
  `failedIds` raporlanır. Seçim modu (uzun bas): klasör/arama kilitli (değişirse seçim temizlenir), geri tuşu
  önce seçimi bırakır, "tümünü seç" yüklenen öğeleri seçer, onayda ilk 5 ad + "+N"; silme/değiştirme
  sürerken aksiyonlar kilitli. Yükleme sheet'i sürerken kapanmaz. Depolama kartı yalnız dashboard'da
  (admin assets sayfasında yok). Bilinen sınırlama: `/` içeren klasör adları path-variable
  endpoint'lerinde (`%2F`) çalışmayabilir (admin'de de aynı).
- **İlişki alanları:** `RelationMultiSelect` bir `FormField` (validator / `isRequired`, `Form.save/reset`).
  `paged: true` kaynakta tüm sayfalar baştan çekilir (seçili id'lerin etiketi her zaman çözülür; ~5000 kayda
  kadar uygun). İlk `maxChips` chip + "+K daha".
- **Roller:** `AuthProvider.roles` / `roleLabel` yalnız gösterim içindir; yetki her zaman permission'dan
  gelir (istemcide SUPER_ADMIN bypass'ı yok — backend süper admine tüm izinleri zaten verir).
- **Permission (UI gating):** `AuthProvider.can(module, action)` / `has('<module>:<action>')` — kaynak
  `GET /users/me/permissions` (login/mfa-verify sonrası ve açılışta token varsa yüklenir; logout'ta temizlenir).
  Her `CrudModule` `permissionKey` taşır (`PermissionConstants.java`'daki modül adı). `<key>:read` yoksa modül
  drawer'da görünmez (admin gibi: kullanıcılar `users:manage`, ayarlar/profil herkes);
  `:create`/`:update`/`:delete` yoksa yeni/düzenle/sil aksiyonları gizlenir. Yüklenemezse
  login yanıtındaki `permissions` kullanılır; o da yoksa modüller gizlenir ve "Tekrar Dene" gösterilir.
  Asıl yetki backend'de `@PreAuthorize` ile zorlanır; backend'de olmayan anahtar kullanma.

## Kodlama kuralları

- Dart dosyaları `snake_case.dart`, sınıflar `PascalCase`, private üyeler `_` önekli.
- `print` yok; hata kullanıcıya `ApiException` mesajıyla gösterilir.
- Yeni saf mantık (`crud_payload.dart` gibi) Flutter'a bağımlı olmadan yazılır ve unit test alır.
- Gizli bilgi koda yazılmaz. Test hesapları env / `--dart-define` ile verilir.
- Yeni kodda `withOpacity` yerine `withValues(alpha: …)` kullan.
- **Renkler yalnız `config/app_theme.dart`'ta.** Widget'larda `Theme.of(context).colorScheme` kullan
  (`error` = #D32F2F dolu yıkıcı buton/SnackBar, beyaz metin AA; hata metni/ikonu `onErrorContainer`);
  colorScheme'da karşılığı olmayan durum renkleri `AppColors.success/warning`. Sabit `Color(0x…)` /
  `Colors.redAccent` kopyalama.
- **SnackBar yalnız `showAppSnackBar(context, mesaj, error:, action:)` ile** (önceki SnackBar'ı kapatır, hata →
  `colorScheme.error` zemin). Metin/aksiyon rengi tek yerde: `appTheme.snackBarTheme` (zemin
  `AppColors.snackBar`, beyaz metin; hata zemininde de beyaz, AA). `ScaffoldMessenger…showSnackBar(SnackBar(…))`
  ve dağınık `backgroundColor` yazma.
- Sıralanabilir listeler (ReorderableListView) sürüklemeye ek olarak `ReorderableRow` (satır odağında
  "Yukarı/Aşağı taşı" semantik aksiyonları) + `ReorderControls` (görünür "Taşı" menüsü; tutamaç 48 dp,
  `ExcludeSemantics`) kullanır. Kod/ID alanlarında yazı tipi `'monospace'`.
- Yükleme/hata/boş durumları ve onaylar için `lib/widgets/` bileşenlerini kullan; ilerleme göstergelerine
  `semanticsLabel` ver. Türkçe metinde `toUpperCase()`/`toLowerCase()` yerine `upperTr` / `foldTr` kullan;
  baş harf gibi kesmelerde `characters` kullan.

## Komutlar

```bash
flutter pub get
flutter run                       # bağlı cihaz / simülatör (API: prod)
# Lokal backend (Android emülatör; debug build'de http açık). iOS simülatör: http://localhost:8080/api/v1
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1
flutter analyze --no-fatal-infos  # statik analiz (error/warning 0 olmalı; info'lar exit'i bozmaz)
flutter test                      # unit + widget testleri (canlı test atlanır)

# Canlı sözleşme testi — gerçek backend'e yazar ve siler, opt-in:
LIVE_API=1 ELLY_USER=... ELLY_PASS=... [ELLY_TENANT=tenant1] flutter test test/crud_live_contract_test.dart

# Uçtan uca (cihaz/simülatör):
flutter test integration_test --dart-define=ELLY_USER=... --dart-define=ELLY_PASS=...

flutter build ipa                 # iOS release
flutter build appbundle           # Android release
```

## Git

- `main` üzerinde çalış (feature branch açma), conventional commit + Türkçe açıklama
  (örn. `feat(crud): banner çoklu görsel desteği`).
- Commit öncesi: `flutter analyze --no-fatal-infos && flutter test`.
- **Push yok** — push yalnız Orchestrator üzerinden kullanıcı onayıyla.

## Agent'lar ve skill'ler

| Tür | Dosya | Amaç |
|---|---|---|
| Agent | `.claude/agents/test-writer.md` | Dart unit/widget testleri yazar |
| Agent | `.claude/agents/ui-reviewer.md` | Flutter UI/UX + a11y review (salt-okunur) |
| Skill | `.claude/skills/karpathy-guidelines/` | Düşün → sor, basit tut, cerrahi değiş, hedef odaklı |
| Skill | `.claude/skills/ponytail/` | Lazy senior dev modu — işi tam çözen en küçük değişiklik (`/ponytail lite\|full\|ultra`) |
| Skill | `.claude/skills/ponytail-review/` | Diff kalite review'u |

Orchestrator tarafındaki lead playbook'u: `../.agents/skills/mobile-lead/SKILL.md`.
Cursor karşılıkları `.cursor/rules/`, Antigravity karşılıkları `.agents/rules/` ve `.agents/skills/`.
