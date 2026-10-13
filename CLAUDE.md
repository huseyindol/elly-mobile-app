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
│   └── text_format.dart           # saf: foldTr (Türkçe arama anahtarı), upperTr, formatBytes, slugify
├── screens/
│   ├── login_screen.dart
│   ├── dashboard_screen.dart      # admin dashboard özet kartları + son e-postalar/yazılar (permission'a göre)
│   ├── coming_soon_screen.dart    # mobilde henüz olmayan admin alanları için yer tutucu
│   ├── assets_screen.dart         # Medya: klasör, sunucu araması, çoklu yükleme, toplu silme (generic'e sığmıyor)
│   └── crud/generic_crud_{list,form}_screen.dart
└── widgets/                       # ortak bileşenler — yeni ekranlar bunları kullanır
    ├── app_scaffold.dart          # AppScaffold (cam AppBar + AmbientBackground + opsiyonel drawer)
    ├── app_drawer.dart            # AppDrawer(currentId) + openNavItem + isNavItemVisible + avatarInitials
    ├── state_views.dart           # LoadingView (semanticsLabel) · ErrorView (Tekrar Dene) · EmptyView
    ├── confirm_dialog.dart        # showConfirmDialog (destructive: kırmızı onay)
    ├── searchable_paged_list.dart # liste gövdesi: arama, filtre/sıralama, pull-to-refresh, /list/paged sonsuz kaydırma
    ├── relation_multi_select.dart # FormField<List<Object>>: ilişki id listesi seçici (componentIds, …)
    ├── rich_text_field.dart       # HTML gövde editörü (Quill; desteklenmeyen HTML → ham HTML modu)
    └── asset_picker.dart          # showAssetPicker (görsel assetten mutlak URL), AssetThumbnail, isImageAsset
test/                              # unit/widget testleri (helpers/fake_backend.dart) + opt-in canlı sözleşme testi
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
    `imageUrl` (önizleme + "Assetlerden seç", `assets:read` varsa). `_` ile başlayan anahtar yerel form
    durumudur, gönderilmez (banner `_imageMode`). `slugFrom` yalnız yeni kayıtta, slug elle değişene kadar.
  - Banner görselleri: backend dosya gelince URL'leri yok sayar (create'te tamamen düşürür) → admin gibi
    "Dosya yükle / URL gir" modu; yalnız görünen dosya alanları gönderilir.
  - İçerikler: metadata alanları `contentType`'a göre (admin `schemas/dynamic` skills/experience); tip
    düzenlemede kilitli; kayıttaki bilinmeyen metadata anahtarları korunur.
  - Şablon (`template`) serbest metin: admin listeyi tenant sitesinden sunucu env'iyle çeker, mobilde yok.
- **Zengin metin (posts `content`):** `RichTextField` + `rich_text_codec.dart`. Kodek yalnız admin Tiptap
  alt kümesini (p, h1–h6, ul/ol>li>p iç içe, blockquote>p, pre>code[language-*], hr, img[src,alt,title],
  br, strong/em/s/u/code/a) kabul eder; başka her şey (tablo, iframe, div, span, style/class…) →
  `analyzeHtml` desteklenmiyor der → uyarı + **ham HTML modu** (içerik bayt bayt korunur). Dokunulmamış
  gövde aynen geri gönderilir; yalnız değiştiyse Delta → Tiptap biçimli HTML. Yapıştırma düz metin
  (`enableExternalRichPaste: false`). `MaterialApp` `FlutterQuillLocalizations.localizationsDelegates`
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
  `statusKey` rozet, `thumbnailKey` görsel, `listMeta` ek satırlar; `ListFilter` çipleri sunucu
  (`endpointTemplate`, banner klasörü) ya da istemci (`key`, içerik tipi) filtresidir.
- **Assetler:** `AssetsScreen` (drawer `assets` öğesi). Klasör: `/assets/list/{klasör}/paged`; arama sunucuda:
  ad `/assets/{ad}/paged` (klasörle `/assets/{klasör}/{ad}/paged`), ID `/assets/id/{id}`; tek dosya
  `POST /assets` (`file`), çoklu `POST /assets/multi` (`files`), `subFolder` opsiyonel; değiştir `PUT
  /assets/{id}` (`file`); toplu silme `POST /assets/bulk-delete {ids}` → `failedIds` raporlanır. Depolama
  kartı yalnız dashboard'da (admin assets sayfasında yok).
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
