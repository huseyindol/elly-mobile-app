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
| Test | `flutter_test`, `integration_test` |
| Lint | `flutter_lints` (`analysis_options.yaml`) |

## Dizin yapısı

```
lib/
├── main.dart                      # MultiProvider + AuthWrapper (login ↔ dashboard)
├── config/
│   ├── modules_config.dart        # CRUD modül tanımları (tek kaynak); başlıklar admin sidebar etiketleri
│   └── nav_config.dart            # drawer menüsü: admin Sidebar grupları/sırası/permission'ları (NavGroup/NavItem)
├── models/                        # crud_module.dart (CrudModule/FieldConfig/RequestMode), login_response.dart
├── providers/auth_provider.dart   # login (+2FA adımı) / logout / oturum + permission durumu
├── services/
│   ├── api_service.dart           # tüm HTTP istekleri, header'lar, 401 → refresh
│   └── crud_payload.dart          # saf yardımcılar: getPath/setPath, buildPayload, extractItems, paging
├── screens/
│   ├── login_screen.dart
│   ├── dashboard_screen.dart      # admin dashboard özet kartları + son e-postalar/yazılar (permission'a göre)
│   ├── coming_soon_screen.dart    # mobilde henüz olmayan admin alanları için yer tutucu
│   └── crud/generic_crud_{list,form}_screen.dart
└── widgets/                       # ortak bileşenler — yeni ekranlar bunları kullanır
    ├── app_drawer.dart            # AppDrawer + openNavItem + isNavItemVisible
    ├── state_views.dart           # LoadingView (semanticsLabel) · ErrorView (Tekrar Dene) · EmptyView
    ├── confirm_dialog.dart        # showConfirmDialog (destructive: kırmızı onay)
    ├── searchable_paged_list.dart # liste gövdesi: arama, pull-to-refresh, /list/paged sonsuz kaydırma
    └── relation_multi_select.dart # ilişki id listesi seçici (componentIds, widgetIds, …)
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
  - Gönderilen payload **yalnız `payloadKeys`** içerir; ilişki id listeleri (componentIds, pageIds…)
    bilinçli olarak gönderilmez (backend `null` = ilişkiye dokunma).
  - `RequestMode`: `json` · `multipartData` (banners: `data` JSON part + dosyalar) ·
    `multipartFields` (assets: düz alanlar + `file`).
- Endpoint'ler `/api/v1` köküne görelidir (`ApiService.baseUrl`; varsayılan prod, build'de
  `--dart-define=API_BASE_URL=...` ile değişir). Yeni bir kök/endpoint backend'de yoksa
  **kullanma** — sözleşme önce backend'de değişir (kök `AGENTS.md` → contract-first).
- Giriş `loginType: 'admin'` ile panel kullanıcısı gibi yapılır. **2FA destekleniyor (yalnız doğrulama
  adımı):** `mfaRequired=true` → login ekranı 6 haneli kod adımına geçer → `POST /auth/mfa/verify
  { mfaToken, code }` (Authorization yok, `X-Tenant-Id` login'deki tenant). 2FA kurulumu/kapatma panelden
  yapılır, mobilde yok. Panelde olduğu gibi sosyal giriş yok.
- **Navigasyon:** dashboard kök ekrandır; `AppDrawer` admin `Sidebar.tsx` gruplarını aynı sırayla gösterir
  (Gösterge Paneli · İçerik Yönetimi · Bileşenler · Medya · Etkileşim · İletişim · Sistem) + profil başlığı +
  çıkış. Drawer seçimi ekranı dashboard'un üstüne `push` eder. Bottom nav yok: 16 hedef 5 sekmeye sığmaz ve
  menü admin ile birebir kalır. Yeni alan = `nav_config.dart`'ta `NavItem` (CRUD ise `NavItem.crud(key)`);
  `module == null` olan öğe "Yakında" ekranını açar — faz tamamlanınca gerçek ekrana bağlanır.
- **Dashboard:** kartlar ve endpoint'ler admin `dashboard/page.tsx` ile aynıdır; yetkisi olmayan kart ne
  gösterilir ne istenir. Her kartın isteği bağımsızdır (hata → karta dokun = tekrar dene); pull-to-refresh
  permission'ları ve tüm kartları yeniler. Kartlar sabit en-boy oranı kullanmaz (büyük yazıda taşma yok).
- **Listeler:** `SearchablePagedList` — `paged: true` ise `page`/`size` eklenir (`PagedResponse.last`'a kadar
  sonraki sayfa). Arama istemci tarafındadır (backend list endpoint'lerinde arama parametresi yok).
  Dışarıdan yenileme `GlobalKey<SearchablePagedListState>().currentState.reload()`.
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
- Yükleme/hata/boş durumları ve onaylar için `lib/widgets/` bileşenlerini kullan; ilerleme göstergelerine
  `semanticsLabel` ver. Türkçe metinde `toUpperCase()` kullanma (`i` → `I`).

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
