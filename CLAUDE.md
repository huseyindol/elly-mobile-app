# Elly Mobile App — Claude Code Proje Rehberi

`elly-admin` yönetim panelinin **Flutter** mobil karşılığı: sayfa, bileşen, post, içerik, widget, banner,
form, asset, mail hesabı, e-posta şablonu, e-posta logu, kullanıcı/rol, profil, ayarlar (2FA, depolama) ve RabbitMQ
yönetimi. Backend: `elly-backend` (Spring Boot,
db-per-tenant). Bu repo `elly-studio` orchestrator'ının bir parçasıdır; çapraz repo kuralları kökteki `AGENTS.md`'dedir.

## Stack

| Katman | Teknoloji |
|---|---|
| Framework | Flutter 3.x (Dart `^3.13`), Material 3, koyu tema |
| State | `provider` (`ChangeNotifier`) — `AuthProvider` |
| HTTP | `http` + `http_parser`/`mime` (multipart) |
| Güvenli depo | `flutter_secure_storage` (accessToken, refreshToken, tenantId) |
| Dosya seçimi | `file_picker` |
| Zengin metin | `flutter_quill` 11.6.0 (MIT) + `html` 0.15.7 (BSD) — kendi HTML ↔ Delta kodeği |
| HTML önizleme | `webview_flutter` 4.14 (BSD-3, flutter.dev) — yalnız `SafeHtmlView` üzerinden (e-posta şablonu önizlemesi) |
| Harici link | `url_launcher` 6.3 (BSD-3, flutter.dev) — yalnız 2FA `otpauth://` linki (doğrulanmış URI) |
| Yerelleştirme | `flutter_localizations` (Flutter SDK) — uygulama sabit `tr` |
| Test | `flutter_test`, `integration_test` |
| Lint | `flutter_lints` (`analysis_options.yaml`) |

## Dizin yapısı

```
lib/
├── main.dart                      # MultiProvider + AuthWrapper (login ↔ dashboard; çıkışta yığın temizliği) + appLocalizationsDelegates
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
│   ├── mail_payload.dart          # saf: mail hesabı / şablon payload'ı, e-posta durum etiketleri, log endpoint'i
│   ├── safe_html.dart             # saf: güvenilmez HTML → önizleme belgesi (CSP, betik/URL temizliği), gezinme kuralı
│   ├── user_admin.dart            # saf: rol hiyerarşisi, kullanıcı payload'ları, şifre/e-posta kuralı, hata metni, otpauth/secret
│   ├── rabbit_admin.dart          # saf: kuyruk path'i, peek sınırı, payload biçimi, republish payload/doğrulama, hata metni
│   └── text_format.dart           # saf: foldTr (Türkçe arama anahtarı), upperTr, formatBytes, slugify, formatDateTimeTr
├── screens/
│   ├── login_screen.dart
│   ├── dashboard_screen.dart      # admin dashboard özet kartları + son e-postalar/yazılar (permission'a göre)
│   ├── coming_soon_screen.dart    # mobilde henüz olmayan admin alanları için yer tutucu
│   ├── assets_screen.dart         # Medya: klasör, sunucu araması, çoklu yükleme, toplu silme (generic'e sığmıyor)
│   ├── forms/                     # form builder alt ekranları: alanlar + alan düzenleme, önizleme, gönderimler (+ detay)
│   ├── mail/                      # İletişim: mail hesapları (+ form), e-posta şablonları (+ form, önizleme), e-posta logları (+ detay)
│   ├── users/                     # Kullanıcılar (panel/tenant sekmesi) + kullanıcı formu (rol atama)
│   ├── account/                   # Profil (+ düzenle, şifre değiştir), Ayarlar (2FA kartı + kapatma dialog'u, depolama), 2FA kurulumu
│   ├── rabbit/                    # RabbitMQ: özet + kuyruklar, kuyruk detayı (peek), republish formu
│   └── crud/generic_crud_{list,form}_screen.dart
└── widgets/                       # ortak bileşenler — yeni ekranlar bunları kullanır
    ├── app_scaffold.dart          # AppScaffold (cam AppBar + AmbientBackground + opsiyonel drawer + bottomNavigationBar)
    ├── app_snack_bar.dart         # showAppSnackBar (tek SnackBar yolu) · reportInvalidFields (kaydır + "N alan hatalı: Etiket")
    ├── reorder_controls.dart      # ReorderableRow (ekran okuyucu "Yukarı/Aşağı taşı") · ReorderControls (Taşı menüsü + tutamaç)
    ├── app_drawer.dart            # AppDrawer(currentId) + openNavItem + isNavItemVisible + avatarInitials
    ├── state_views.dart           # LoadingView (semanticsLabel) · ErrorView (Tekrar Dene) · EmptyView
    ├── confirm_dialog.dart        # showConfirmDialog (destructive: kırmızı onay; requiredText: yazarak onay) · confirmLeaveForm (Çık/Kal)
    ├── status_badge.dart          # StatusBadge (Aktif/Pasif, Ana Hesap, e-posta durumu…)
    ├── safe_html_view.dart        # SafeHtmlView: güvenilmez HTML'i JS kapalı, ağsız WebView'da gösterir
    ├── save_bar.dart              # SaveBar: formların sabit alt Kaydet çubuğu
    ├── password_field.dart        # PasswordField: göster/gizle, öneri/autocorrect kapalı, autofill ipucu
    ├── info_note.dart             # InfoNote: formlardaki bilgi/uyarı kutusu (admin ℹ️ / ⚠️ notları)
    ├── storage_quota_card.dart    # StorageQuotaCard: dashboard "Yönet" ve ayarlar (SUPER_ADMIN limit/yeniden hesapla) + quotaColor
    ├── form_schema_editor.dart    # FormField<Map>: form şeması builder'ı (düzen, adımlar, alanlar, önizleme)
    ├── searchable_paged_list.dart # liste gövdesi: arama, filtre/sıralama, pull-to-refresh, sayfalı sonsuz kaydırma, onLoad
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
  `details`) `ApiException` mesajına çevrilir. **204 No Content** gövdesiz başarıdır → `null` döner
  (`DELETE /email-templates/{key}`, RabbitMQ purge). `patch(endpoint)` gövdesiz PATCH'tir (`/users/{id}/status`).
  **`/auth/*` kuralı (`isPublicAuthEndpoint`):** login/refresh/`/auth/mfa/verify` oturumsuzdur (Bearer yok, 401
  refresh tetiklemez). 2FA yönetimi (`/auth/mfa/status|setup|setup/verify|disable`) oturum ister: Bearer + 401'de
  refresh → tekrar; yanlış kod/şifre de 401 döner → refresh sonrası yine 401 → backend mesajı gösterilir, oturum
  düşmez (refresh token her yanlış denemede döner).
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
    SnackBar'ı çubuğun **üstünde** gösterir (butonu örtmez); **klavye açıkken** `AppScaffold` SaveBar'ı gizleyip
    aynı key'le AppBar'da kaydet ikonu gösterir (alan görünür kalır, landscape'te de; iOS çok satırlı alanda "bitti"
    tuşu yok). SaveBar'ı body'ye koyma. Başarılı kayıt/uygula pop'tan önce `clearSnackBars()` (eski hata sonraki ekrana taşınmaz).
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
- **İletişim (`screens/mail/`)** — generic CRUD'a sığmıyor (satır aksiyonları, yalnız-yazılır şifre, `templateKey`
  kimliği, önizleme), ortak bileşenlerle özel ekranlar:
  - **Mail hesapları** (`mail:*`): `GET /mail-accounts` (sayfasız; tenant çipleri veriden, istemci filtresi — admin
    gibi), detay `GET /mail-accounts/{id}`'den düzenlenir. **SMTP şifresi yalnız yazılır:** backend asla döndürmez,
    form asla doldurmaz/göstermez (obscure + göster/gizle, öneri/autocorrect kapalı); create'te zorunlu, edit'te
    boşsa **anahtar hiç gönderilmez** (`mailAccountPayload`; backend boş/null'da da mevcut şifreyi korur) — yazılırsa
    olduğu gibi (trim'siz) gider. Boş tenant → `null` (admin create'te `''` gönderiyor). Port 1–65535, metinler ≤255,
    tenant ≤50. Aksiyonlar backend yetkisine göre: Düzenle `mail:update`, **Test Et `mail:create`** (`POST
    /{id}/test {testTo}` gerçek e-posta gönderir; sonuç dialog içinde), Doğrula `mail:read` (`POST /{id}/verify`,
    yalnız SMTP handshake; pasif hesabı backend reddeder; sonuç başarı/hata **dialog**'u, hata metni backend'den),
    Sil `mail:delete`. Formdaki doğrulama **kayıtlı** ayarları test eder (kirliyken not gösterilir; sürerken Kaydet
    kilitli). Doğrula/Test `smtpTimeout` (30 sn) sonra anlaşılır hata verir. Test dialog'u gönderim sürerken
    kapanmaz (PopScope + `barrierDismissible: false` + "Kapat" kilitli), sonuç ikon + "Başarılı:/Hata:" önekiyle.
    Sonuç dialog'ları ve SnackBar'lar **ekran State'inin context'iyle** (liste yenilenince satır context'i ölür).
    Kart aksiyonlarının semantik etiketi kayıt adını içerir ("Sil: Hesap 1"); tenant rozeti `AppColors.primaryLight`.
    Admin/backend'de şifreleme (TLS/SSL) alanı yok — port'a göre (587/465).
  - **E-posta şablonları** (`email_templates:read|manage`): `GET /email-templates?page&size` (Spring `Page`),
    detay/PUT/DELETE `…/{templateKey}`. **PUT `templateKey`'i de gönderir** (`DtoEmailTemplateIU` `@NotBlank`;
    admin formu bunu düşürüyor) + kayıttaki `optimisticLockVersion` (backend şu an kullanmıyor). Gövde monospace kod
    alanı, ekranın ~%60'ı sabit yükseklikte kendi içinde kayar; gövde ve konu alanında autocorrect/öneri/smart
    quotes-dashes kapalı (Thymeleaf `"${…}"` bozulmasın). Kaydet edit'te ekranda kalır (admin gibi; yanıttaki yeni
    sürümle); yeni kayıt **aynı ekranda** düzenleme moduna geçer (pushReplacement yok → liste, kullanıcı çıkınca
    yenilenir). 409'da "Yenile" aksiyonlu SnackBar (düzenlemeler kaybolur). Silme sürerken Sil/Kaydet kilitli. `manage` yoksa salt okunur. Silme anahtarı
    **yazarak** onaylatır (`requiredText`, admin `DestructiveConfirmDialog`). Global şablon (`tenantId == null`) "Genel
    şablon" işaretli: düzenlemek tüm tenant'ları etkiler. Classpath şablon adları `GET /emails/templates`
    (`emails:read`) sheet'te. Admin'de değişken listesi yok → mobilde de yok.
  - **Önizleme:** `POST /email-templates/{key}/preview {data}` **kayıtlı** sürümü backend'de render eder (açılışta
    admin varsayılan verisiyle; "Test verisi" JSON nesnesi). Dönen HTML **güvenilmez** → yalnız `SafeHtmlView`:
    JavaScript kapalı, ilk `about:blank` yüklemesinden sonra her gezinme engelli (`isPreviewNavigationAllowed`),
    `safePreviewDocument` (**arka plan isolate'ında, 5 sn'de öldürülür**) → `<head>` başına CSP `default-src 'none'` (yalnız
    inline stil + `data:` görsel/font) + kendi viewport'umuz; script/noscript/iframe/frame/object/embed/applet/portal/
    link/base/`meta[http-equiv]`/şablonun viewport'u ile **svg, math** (html paketi foreign content `<style>`'ını
    tarayıcıdan farklı ayrıştırıyor → mXSS) ve SVG animasyon öğeleri (`animate`, `set`, `animateTransform`,
    `animateMotion`) silinir; `on*` ve URL öznitelikleri düşer (`a/area href="#"`, yalnız `data:image/` `src` kalır).
    CSS (`style` özniteliği + `<style>`): `cleanCss` önce CSS kaçışlarını çözer/yorumları siler, sonra `@import`
    kuralını düşürür, `data:image/` dışı `url()` → `none`, `expression(`/`behavior:`/`-moz-binding:` etkisiz. Çıktı
    yeniden parse + sanitize edilir, **sabit nokta** olana kadar (en çok 3 tur; olmazsa güvenli hata belgesi).
    **Sınırlar** (parse'tan önce, `previewLimitError`): >1 MB "çok büyük"; >10.000 `<harf` açılış etiketi ya da
    tahmini iç içelik >2000 "çok karmaşık" → ekranda mesaj, WebView açılmaz. `estimatedNestingDepth` WHATWG
    tokenizer'ı gibi tarar (yorum/`<!-->`/bogus yorum/CDATA, yalnız `=`'ten sonra tırnaklı öznitelik, raw text kendi
    kapanışına kadar, HTML öğesinde `/>` yok sayılır, SVG/MathML breakout) ve açık öğe yığını tutar: kapanış etiketi
    yalnız eşleşen açık öğeye kadar pop eder, "special" öğede durur — eşsiz kapanış derinliği düşürmez; tahmin
    parser'ın derinliğinin altına inmemeli (`safe_html_limits_test`: özellik testi + saldırı vektörleri). Tahminci
    en iyi çaba (egzotik yanlış iç içelikte — li/template/tablo karışımı — sapabilir); kesin üst sınır etiket sayısı
    tavanı + `sanitizePreviewInBackground`: sanitize öldürülebilir bir isolate'ta, 5 sn'de bitmezse öldürülür ve
    "hazırlama süresi aşıldı" gösterilir. Uzak görseller bilerek görünmez; ekrandaki
    daraltılabilir not "yerleşim bozuk görünebilir" der. Widget testlerinde WebView yerine `htmlViewBuilder` /
    `previewViewBuilder` seam'i.
  - **E-posta logları** (`emails:read`): `GET /emails?status=&sort=id,desc` + page/size; durum çipi sunucu filtresi
    (yeni liste), "Toplam N kayıt" `onLoad`'dan. Tekrar dene `POST /emails/{id}/retry` (`emails:retry`; SENT'te yok,
    detayda devre dışı + sebep; PENDING'de önce onay — iki kez gönderilebilir; hata backend mesajı). Detay ekranı liste satırından (backend'de detay endpoint'i yok);
    `DtoEmailLog`'da hata mesajı / gövde yok → gösterilmez. Durum etiketleri `emailStatusLabels` (dashboard ile ortak).
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
  `MaterialApp` Quill delegate'ini ister (widget testlerinde `FlutterQuillLocalizations.localizationsDelegates`). `flutter_quill_delta_from_html` kullanma: Tiptap çıktısında inline code,
  kod satır sonları ve img alt'ı düşürüyor, `<br>`/`<hr>` sonrası paragrafları birleştiriyor.
- **Dosya URL'leri:** `ApiService.fileUrl(path)` — `assets/t/…` → `<api origin>/assets/t/…` (admin/tenant
  `getImageUrl` ile aynı; `/assets/**` auth'suz). Asset seçici mutlak URL döner.
- Endpoint'ler `/api/v1` köküne görelidir (`ApiService.baseUrl`; varsayılan prod, build'de
  `--dart-define=API_BASE_URL=...` ile değişir). Yeni bir kök/endpoint backend'de yoksa
  **kullanma** — sözleşme önce backend'de değişir (kök `AGENTS.md` → contract-first).
- Giriş `loginType: 'admin'` ile panel kullanıcısı gibi yapılır. **2FA:** `mfaRequired=true` → login ekranı 6
  haneli kod adımına geçer → `POST /auth/mfa/verify { mfaToken, code }` (Authorization yok, `X-Tenant-Id` login'deki
  tenant). Kurulum/kapatma Ayarlar'da (aşağıda "Sistem & hesap"). Panelde olduğu gibi sosyal giriş yok.
  Login/mfa-verify sonrası ve açılışta token varsa `GET /users/me` de yüklenir (`AuthProvider.profile`;
  `displayName` = "Ad Soyad" yoksa kullanıcı adı, `userId`); drawer başlığı ve dashboard selamlaması bunu kullanır.
  Hata sessizdir (login yanıtındaki kullanıcı adına düşer); logout'ta temizlenir.
- **Sistem & hesap (`screens/users`, `screens/account`, `screens/rabbit`):**
  - **Kullanıcılar** (`users:manage`, backend SUPER_ADMIN + ADMIN): `GET /users?audience=panel|tenant` (iki sekme,
    sayfasız, istemci araması). **Rol hiyerarşisi** (`user_admin.dart`, backend `roleLevel`: SUPER_ADMIN 4 · ADMIN 3
    · EDITOR 2 · diğer 1; seviye `AuthProvider.roleLevel` = `/users/me/permissions` rolleri, bilinmiyorsa 1):
    formda yalnız `canAssignRole` rolleri (TENANT hiç; kendi seviyesinin üstü hiç); **kendi seviyesinin üstündeki
    kullanıcı** listede kilitli (düzenle/durum/sil yok — admin panelde ADMIN bir SUPER_ADMIN'i düzenlerse rol
    listesinde SUPER_ADMIN olmadığı için rolü sessizce düşer; backend hedef kullanıcının seviyesini kontrol
    etmiyor). Kendi hesabı: sil/pasifleştir yok, formda rol salt okunur ve şifre sıfırlama yok (Profil → Şifre
    Değiştir). Oluştur `POST /users` (panel: rol yoksa backend ADMIN atar → yalnız ADMIN atayabilen çağırana
    sunulur, değilse ≥1 rol zorunlu; tenant: `roleIds` gönderilmez). Düzenle `GET /users/{id}` → yalnız değişen
    alanlar `PUT /users/{id}` (dolu yeni şifre = admin sıfırlaması, oturumları kapatır) → roller değiştiyse
    `PUT /roles/users/{id}/roles` (≥1, tümünü değiştirir). Durum `PATCH /users/{id}/status?isActive=` (pasifleştirme
    onaylı), silme kullanıcı adı **yazılarak** onaylı. Hatalar `userErrorText` (bilinen İngilizce backend
    mesajları Türkçe; 403 hiyerarşiyi açıklar). Admin'de rol/izin tanımı yönetim ekranı yok → mobilde de yok.
  - **Profil** (herkes): `GET /users/me` (açılışta tazelenir), roller + modüle göre izinler (admin `moduleLabels`).
    Düzenle `PUT /users/me {firstName, lastName, email}` (admin formu; e-posta zorunlu — backend `@Email` boş
    metni kabul edip e-postayı silerdi). Şifre değiştir (yalnız `provider == 'local'`): `PUT /users/me/password
    {currentPassword, newPassword}`; kural backend `@Pattern` (≥8, büyük/küçük harf + rakam; baş/son boşluk
    reddedilir), mevcuttan farklı, iki kez yazılır; yanlış mevcut şifre 400 → "Mevcut şifre hatalı.".
  - **Ayarlar** (herkes): 2FA kartı `GET /auth/mfa/status`. Etkinleştir → `MfaSetupScreen`: `GET /auth/mfa/setup`
    (**her çağrı yeni secret üretir ve 2FA'yı kapatır** → yalnız durum kapalıyken açılır, canlı testte çağrılmaz)
    → `qrUri` yalnız `isValidOtpauthUri` (otpauth://totp, aynı secret) ise "Authenticator'da aç" (`url_launcher`,
    harici uygulama; açılamazsa kopyala önerisi). QR yok (authenticator genelde aynı telefonda; paket eklenmedi).
    Secret yalnız State'te: **varsayılan maskeli** (`formatSecret`), "göster" ile 4'lü gruplar, uygulama ön plandan
    çıkınca yeniden maskelenir, loglanmaz/saklanmaz; kopyalama kullanıcının eylemi. Kod 6 hane →
    `POST /auth/mfa/setup/verify {code}` (yanlış kod satır içi backend mesajı). Doğrulamadan çıkış onaylı.
    Kapat: şifreli dialog → `POST /auth/mfa/disable {password}` (yanlış şifre dialog içinde, sürerken kapanmaz).
    Depolama: `StorageQuotaCard(settings: true)`; limit (GB → `gbToBytes`, 1024³) `PUT …/quota/limit {limitBytes}`
    ve `POST …/quota/recompute` yalnız **SUPER_ADMIN rolünde** (backend `ROLE_SUPER_ADMIN` — permission değil rol;
    rol kontrolünün tek istisnası), diğerlerine admin'in salt-okunur notu.
  - **RabbitMQ** (`rabbit:read`; aksiyonlar `rabbit:manage`): özet `GET /admin/rabbit/overview` (liste başlığı,
    `SearchablePagedList.header`) + kuyruklar `GET /admin/rabbit/queues`; otomatik yenileme yok (admin 15–30 sn
    poll eder) → çek-yenile/Yenile. Detay `GET …/queues/{name}` (`queuePath`, ad tek path segmenti); mesajlar
    yalnız istekle **peek** `…/messages?count=1..100` (backend mesajları yeniden kuyruğa alır → "redelivered").
    Mesaj gövdesi/properties **güvenilmez düz metin**: `SelectableText` monospace, JSON ise girintili, 10.000
    karakterde kesilir; HTML asla render edilmez. Purge `POST …/purge` (204) kuyruk adı **yazılarak** onaylı, boş
    kuyrukta kapalı. Republish formu `POST …/republish {targetQueue, payload, contentType}` (varsayılan hedef
    `email-queue`, peek'ten doldurulur; JSON content type'ta geçersiz JSON reddedilir; gönderimden önce onay —
    tüketici yeniden işler, ör. e-posta tekrar gider); `base64` mesaj metin olarak republish edilemez.
- **Navigasyon:** dashboard kök ekrandır; `AppDrawer` admin `Sidebar.tsx` gruplarını aynı sırayla gösterir
  (Gösterge Paneli · İçerik Yönetimi · Bileşenler · Medya · Etkileşim · İletişim · Sistem) + profil başlığı
  (Türkçe baş harfler + rol etiketi) + çıkış. Her bölüm ekranında drawer vardır (`AppScaffold(navId:)`,
  aktif öğe vurgulu). `openNavItem` yığını `[dashboard, bölüm]` tutar (popUntil(isFirst) + push); alt ekranlar
  (form vb.) `navId` vermez → geri butonu. Bottom nav yok: 16 hedef 5 sekmeye sığmaz ve menü admin ile
  birebir kalır. Yeni alan = `nav_config.dart`'ta `NavItem` (CRUD ise `NavItem.crud(key)`); generic'e sığmayan
  ekran `app_drawer.dart` → `navScreen(item)` eşlemesine eklenir (assets, mail-accounts, email-templates,
  email-logs, users, rabbitmq, settings, profile). `navScreen` null dönen öğe "Yakında" etiketi taşır ve yer tutucu
  ekranı açar (şu an yalnız chat — Faz 5). Drawer başlığı "Ad Soyad" + iki kelimenin baş harfleri (admin sidebar).
- **Yerelleştirme:** `MaterialApp(locale: tr, supportedLocales: [tr], localizationsDelegates: appLocalizationsDelegates)`
  — Quill + `flutter_localizations` Global Material/Widgets/Cupertino, her biri bir kez. Cihaz dili ne olursa olsun
  sistem metinleri (tarih seçici, ReorderableListView "Yukarı/Aşağı/Başa/Sona taşı" aksiyonları) Türkçe; iOS
  `Info.plist` `CFBundleLocalizations: [tr]`.
- **Oturum sonu:** `EllyMobileApp.navigatorKey`; `AuthWrapper` oturum düşünce (logout ya da refresh başarısız)
  `popUntil(isFirst)` ile tüm ekran/dialog/sheet'leri kapatır — sonraki kullanıcı eski ekranı görmez.
- **Ekran iskeleti:** yeni ekranlar `AppScaffold` (ya da yalnız arka plan için `AmbientBackground`) kullanır;
  ambient ışık / blur AppBar kopyalanmaz.
- **Dashboard:** kartlar ve endpoint'ler admin `dashboard/page.tsx` ile aynıdır; yetkisi olmayan kart ne
  gösterilir ne istenir. Her kartın isteği bağımsızdır (hata → karta dokun = tekrar dene); pull-to-refresh
  permission'ları ve tüm kartları yeniler (çalışırken kilitli; izin yenileme hatası SnackBar). Kartlar sabit
  en-boy oranı kullanmaz; ölçekli genişlik ≥260 dp ise iki sütun (320–430 dp telefonlar), büyük yazıda tek.
  "Depolama Kullanımı" kartı admin `StorageUsageWidget` ile aynı (`StorageQuotaCard`, "Yönet" → Ayarlar):
  `GET /storage/tenant/{tenantId}/quota` (oturum tenant'ı yoksa `/storage/quota`), eşikler <70 yeşil · 70–90 amber
  · ≥90 kırmızı. "Kullanıcılar" kartı Kullanıcılar ekranını açar.
- **Listeler:** `SearchablePagedList` — `paged: true` ise `page`/`size` eklenir (`PagedResponse.last`'a kadar
  sonraki sayfa; mevcut query, tekrarlı `sort` dahil, korunur). Arama istemci tarafında ve `foldTr` iledir
  (backend list endpoint'lerinde arama parametresi yok); sorgu doluyken sonraki sayfa otomatik değil,
  "Daha fazla ara" ile yüklenir. Yenileme sırasında eski liste + ince ilerleme çubuğu; hata → SnackBar.
  Alt padding FAB payı bırakır. Dışarıdan yenileme `GlobalKey<SearchablePagedListState>().currentState.reload()`.
  `header` listeyle birlikte kayan üst bölümdür (RabbitMQ özeti); liste yüklenirken/hatadayken görünmez.
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
- **Roller:** `AuthProvider.roles` / `roleLabel` gösterim içindir; yetki her zaman permission'dan gelir
  (istemcide SUPER_ADMIN bypass'ı yok — backend süper admine tüm izinleri zaten verir). İki istisna, backend'in
  kendisi rol baktığı için: kullanıcı yönetiminde rol hiyerarşisi (`roleLevel`) ve `ROLE_SUPER_ADMIN` endpoint'leri
  (depolama limiti).
- **Permission (UI gating):** `AuthProvider.can(module, action)` / `has('<module>:<action>')` — kaynak
  `GET /users/me/permissions` (login/mfa-verify sonrası ve açılışta token varsa yüklenir; logout'ta temizlenir).
  Her `CrudModule` `permissionKey` taşır (`PermissionConstants.java`'daki modül adı). `<key>:read` yoksa modül
  drawer'da görünmez (admin gibi: kullanıcılar `users:manage`, ayarlar/profil herkes);
  `:create`/`:update`/`:delete` yoksa yeni/düzenle/sil aksiyonları gizlenir. Yüklenemezse
  login yanıtındaki `permissions` kullanılır; o da yoksa modüller gizlenir ve "Tekrar Dene" gösterilir.
  Asıl yetki backend'de `@PreAuthorize` ile zorlanır; backend'de olmayan anahtar kullanma.

## Kodlama kuralları

- Dart dosyaları `snake_case.dart`, sınıflar `PascalCase`, private üyeler `_` önekli.
- `print` yok; hata kullanıcıya `ApiException` mesajıyla gösterilir. Şifre, 2FA secret'ı ve token loglanmaz,
  `flutter_secure_storage` dışına yazılmaz.
- `setState` içinde Future döndüren arrow kullanma (`setState(() => _f = load())` assert atar): blok gövdesi.
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

# Canlı sözleşme testi — gerçek backend'e yazar ve siler, opt-in (sistem & hesap grubu salt okunur:
# kullanıcı oluşturmaz, 2FA kurulumu/purge/peek yapmaz):
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
