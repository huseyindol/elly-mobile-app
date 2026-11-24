#!/bin/bash
# Flutter oyununu TestFlight'a yükler: flutter build ios --config-only → xcodebuild archive → xcodebuild -exportArchive (upload).
# Kullanım: tool/upload_testflight.sh [--dry-run] [TEAM_ID]
#   TEAM_ID    Ücretli Apple Developer takım kimliği (10 karakter; developer.apple.com/account → Membership details).
#              Argüman ya da ortam değişkeni TEAM_ID. Proje dosyasına YAZILMAZ: xcodebuild'e DEVELOPMENT_TEAM= olarak
#              verilir; ios/Runner.xcodeproj'daki takım (kablolu kurulum) olduğu gibi kalır.
#   --dry-run  Yalnız imzasız archive (CODE_SIGNING_ALLOWED=NO) + ExportOptions.plist. Apple'a hiçbir şey gitmez.
# Yükleme, Xcode → Settings → Accounts'ta oturumu açık Apple hesabıyla yapılır (App Store Connect API anahtarı yok).
# Build numarası ARTIRILMAZ: pubspec.yaml → version: X.Y.Z+N (N = build numarası).
# Neden `flutter build ipa --export-options-plist` değil: o yol archive'ı projedeki takımla imzalar; takım geçici olarak
# ezilemez. Proje kalıcı olarak ücretli takıma geçince `flutter build ipa --release --export-options-plist=<bu betiğin
# ürettiği plist>` aynı işi tek satırda yapar.
# Durum: hamur-usta'da dry-run (2026-10-05) ve gerçek yüklemeler (2026-10-06'dan beri); tumble-trail dry-run (2026-10-10).
# Kaynak: .claude/skills/ios-device-delivery/templates/upload_testflight_flutter.sh (studio şablonu)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/testflight
LEDGER=${LEDGER:-docs/TESTFLIGHT.md}          # başarılı yüklemelerin kaydı (aynı build numarasını ikinci kez yüklememek için)
PB=/usr/libexec/PlistBuddy
APP_NAME=Runner
# Flutter: PATH'te yoksa (orkestratörün login olmayan kabuğu) studio Mac'indeki yerleşik kurulum. Ezmek: FLUTTER=/yol/flutter
FLUTTER=${FLUTTER:-$(command -v flutter || echo "$HOME/development/flutter/bin/flutter")}

die() { echo "✘ $*" >&2; exit 1; }
[ -x "$FLUTTER" ] || die "flutter bulunamadı ($FLUTTER). FLUTTER=/yol/flutter ile ver."

DRY=0
MSG=""
TEAM_ID=${TEAM_ID:-}
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) die "Bilinmeyen seçenek: $a (kullanım: tool/upload_testflight.sh [--dry-run] [TEAM_ID])" ;;
    *) TEAM_ID=$a ;;
  esac
done

# --- pubspec + Xcode projesinden uygulama bilgisi -----------------------------------
INFO=$(python3 - <<'PY'
import re, sys
pub = open("pubspec.yaml", encoding="utf-8").read()
m = re.search(r"^version:\s*([0-9][^+\s]*)\+(\d+)\s*$", pub, re.M)
if not m:
    sys.exit("pubspec.yaml'da 'version: X.Y.Z+N' satırı yok (N = build numarası).")
pbx = open("ios/Runner.xcodeproj/project.pbxproj", encoding="utf-8").read()
ids = [i for i in re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = \"?([^\";]+)\"?;", pbx) if "RunnerTests" not in i]
teams = re.findall(r"DEVELOPMENT_TEAM = \"?([A-Z0-9]+)\"?;", pbx)
if not ids:
    sys.exit("ios/Runner.xcodeproj'da PRODUCT_BUNDLE_IDENTIFIER yok.")
print(ids[0], m.group(1), m.group(2), teams[0] if teams else "-")
PY
) || die "Proje bilgisi okunamadı (yukarıdaki satıra bak)."
read -r BUNDLE_ID VERSION BUILD PROJECT_TEAM <<<"$INFO"
echo "→ $BUNDLE_ID · $VERSION ($BUILD)"

# --- takım kimliği --------------------------------------------------------------
team_status() {
  python3 - "$1" <<'PY'
import plistlib, subprocess, sys
team = sys.argv[1]
try:
    prefs = plistlib.loads(subprocess.run(["defaults", "export", "com.apple.dt.Xcode", "-"],
                                          capture_output=True, check=True).stdout)
except Exception:
    print("bilinmiyor -"); sys.exit(0)
teams = []
for key in ("IDEProvisioningTeamByIdentifier", "IDEProvisioningTeams"):
    for lst in prefs.get(key, {}).values():
        teams += lst
known = sorted({f"{t.get('teamID')}({'ücretsiz' if t.get('isFreeProvisioningTeam') else 'ücretli'})" for t in teams})
hit = [t for t in teams if t.get("teamID") == team]
state = "yok" if not hit else ("ucretsiz" if all(t.get("isFreeProvisioningTeam") for t in hit) else "ucretli")
print(state, ",".join(known) or "-")
PY
}

if [ "$DRY" = 0 ]; then
  [ -n "$TEAM_ID" ] || die "Takım kimliği yok. Kullanım: tool/upload_testflight.sh <TEAM_ID> (ya da TEAM_ID=... ortam değişkeni).
  Kimlik: developer.apple.com/account → Membership details → Team ID (10 karakter). Ücretsiz Personal Team TestFlight'a yükleyemez."
fi
if [ -n "$TEAM_ID" ]; then
  [[ $TEAM_ID =~ ^[A-Z0-9]{10}$ ]] || die "Takım kimliği 10 karakter (büyük harf/rakam) olmalı: '$TEAM_ID'"
  read -r TSTATE TKNOWN <<<"$(team_status "$TEAM_ID")"
  case $TSTATE in
    ucretli) echo "→ Takım: $TEAM_ID (Xcode'da ücretli takım olarak görünüyor)" ;;
    ucretsiz) MSG="$TEAM_ID ücretsiz Personal Team: TestFlight/App Store'a yükleyemez. Ücretli takımın kimliğini ver." ;;
    yok) MSG="Takım bulunamadı: $TEAM_ID Xcode hesabında görünmüyor (Xcode'un bildikleri: $TKNOWN).
  Xcode → Settings → Accounts → Apple ID → takım listesinde ücretli takım çıkmalı. Kayıt yeni onaylandıysa Xcode'u kapatıp aç
  ya da hesabı çıkarıp yeniden ekle. (Kontrolü atlamak için: SKIP_TEAM_CHECK=1)" ;;
    *) echo "→ Takım: $TEAM_ID (Xcode tercihleri okunamadı, kontrol atlandı)" ;;
  esac
  if [ -n "$MSG" ]; then
    if [ "$DRY" = 1 ] || [ "${SKIP_TEAM_CHECK:-0}" = 1 ]; then echo "! $MSG"; else die "$MSG"; fi
  fi
else
  TEAM_ID=$PROJECT_TEAM
  echo "→ Dry-run: TEAM_ID verilmedi; ExportOptions.plist'e yer tutucu olarak proje takımı ($PROJECT_TEAM) yazılacak."
fi

# --- build numarası daha önce yüklendi mi (yerel kayıt) ---------------------------
if [ -f "$LEDGER" ]; then
  PREV=$(awk -F'|' -v v="$VERSION" '$3 ~ /[0-9]/ { gsub(/ /,"",$3); gsub(/ /,"",$4); if ($3 == v && $4+0 > m) m = $4+0 } END { print m+0 }' "$LEDGER")
  if [ "$PREV" -ge "$BUILD" ]; then
    MSG="$VERSION+$BUILD yüklenemez: bu sürümde $PREV numaralı build daha önce yüklenmiş ($LEDGER).
  pubspec.yaml → version'ı $VERSION+$((PREV + 1)) yap, docs/RELEASES.md'ye yaz, tekrar çalıştır."
    if [ "$DRY" = 1 ]; then echo "! $MSG"; else die "$MSG"; fi
  fi
fi

explain() {
  local log=$1
  echo "--- $log (hata satırları) ---" >&2
  grep -E "error:|ERROR|ITMS-|Error Domain|failed" "$log" | tail -8 >&2 || true
  echo "---" >&2
  if grep -qiE "Redundant Binary Upload|bundle version must be higher|ITMS-4238|ITMS-90189|ITMS-90062|has already been uploaded|build .* already exists" "$log"; then
    echo "Neden: $VERSION+$BUILD App Store Connect'e daha önce yüklenmiş. pubspec.yaml build numarasını artır, tekrar çalıştır."
  elif grep -qiE "missing Xcode-Token|Xcode-Token|Failed to Use Accounts" "$log"; then
    echo "Neden: Xcode'daki Apple hesabı belirteci (Xcode-Token) geçersiz/eksik. Xcode → Settings → Accounts'ta hesabı seç, gerekirse çıkar-ekle ve yeniden giriş yap; sonra betiği tekrar çalıştır (build numarası artırmaya gerek yok)."
  elif grep -qiE "Error Downloading App Information|No suitable application records|application record|No App Store Connect app|app record .* not found|Could not find .*app" "$log"; then
    echo "Neden: App Store Connect'te uygulama kaydı yok. appstoreconnect.apple.com → Uygulamalar → + → Yeni Uygulama, paket kimliği $BUNDLE_ID."
  elif grep -qiE "is not available|cannot be registered to your development team|identifier .* (already in use|not available)" "$log"; then
    echo "Neden: $BUNDLE_ID başka bir takımda kayıtlı (büyük olasılıkla ücretsiz Personal Team). developer.apple.com → Identifiers'ta ücretli takıma kaydetmeyi dene; olmuyorsa Apple Developer desteğine yaz ya da bundle id değiştir."
  elif grep -qiE "Cloud signing permission|not permitted to|does not have permission|insufficient (permission|privilege)" "$log"; then
    echo "Neden: Hesabın dağıtım sertifikası oluşturma yetkisi yok. Takımda rolün Account Holder/Admin olmalı; ya da Xcode → Settings → Accounts → Manage Certificates → + → Apple Distribution."
  elif grep -qiE "(iOS|Apple) Distribution|distribution certificate" "$log"; then
    echo "Neden: Distribution sertifikası yok. Xcode -allowProvisioningUpdates ile normalde kendisi oluşturur; olmadıysa Xcode → Settings → Accounts → takım → Manage Certificates → + → Apple Distribution."
  elif grep -qiE "No Account for Team|No Accounts|not a member of|Unable to find a team|team .* (not found|could not be found)|requires a development team|No signing certificate" "$log"; then
    echo "Neden: Takım bulunamadı / imza kimliği yok. Xcode → Settings → Accounts'ta ücretli takım ($TEAM_ID) görünmeli."
  elif grep -qE "(^|[^A-Za-z])PLA([^A-Za-z]|$)|Program License Agreement|agreement" "$log"; then
    echo "Neden: Bekleyen Apple sözleşmesi. developer.apple.com/account ve App Store Connect → İş (Business)'te güncel sözleşmeyi kabul et."
  elif grep -qiE "authenticat|session (has )?expired|sign in" "$log"; then
    echo "Neden: Xcode'daki Apple hesabı oturumu düşmüş. Xcode → Settings → Accounts'ta yeniden giriş yap."
  elif grep -qiE "No profiles for|provisioning profile" "$log"; then
    echo "Neden: Provisioning profili oluşturulamadı. Xcode → Settings → Accounts'ta takım seçili mi; bundle id ($BUNDLE_ID) ücretli takımda kayıtlı mı bak."
  elif grep -qiE "ITMS-90022|ITMS-90713|ITMS-90717|AppIcon" "$log"; then
    echo "Neden: Uygulama ikonu sorunu (1024 px, alfa kanalı yok olmalı)."
  elif grep -qiE "pod install|CocoaPods" "$log"; then
    echo "Neden: CocoaPods kurulumu. cd ios && pod install --repo-update, sonra tekrar çalıştır."
  else
    echo "Neden: tanınmadı — tam günlük: $log"
  fi
}

# --- 1) Flutter yapılandırması (Generated.xcconfig: sürüm + build numarası, pod'lar) ---
mkdir -p "$OUT"
echo "→ flutter build ios --release --config-only — log: $OUT/flutter.log"
"$FLUTTER" build ios --release --config-only >"$OUT/flutter.log" 2>&1 || { explain "$OUT/flutter.log" >&2; die "flutter build ios --config-only başarısız."; }

# --- 2) Archive -------------------------------------------------------------------
ARCHIVE=$OUT/$APP_NAME.xcarchive
rm -rf "$ARCHIVE"
if [ "$DRY" = 1 ]; then
  SIGN=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
else
  SIGN=(-allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development")
fi
echo "→ xcodebuild archive$([ "$DRY" = 1 ] && echo " (imzasız, dry-run)") — log: $OUT/archive.log"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" "${SIGN[@]}" archive >"$OUT/archive.log" 2>&1 ||
  { explain "$OUT/archive.log" >&2; die "Archive başarısız."; }
APP=$ARCHIVE/Products/Applications/$APP_NAME.app
[ -d "$APP" ] || die "Archive içinde $APP yok (log: $OUT/archive.log)"

check_key() {
  local got
  got=$($PB -c "Print :$1" "$APP/Info.plist" 2>/dev/null || echo "(yok)")
  [ "$got" = "$2" ] || die "Archive Info.plist $1 = '$got', beklenen '$2'${3:-}"
}
check_key CFBundleIdentifier "$BUNDLE_ID"
check_key CFBundleShortVersionString "$VERSION"
check_key CFBundleVersion "$BUILD"
check_key ITSAppUsesNonExemptEncryption false \
  " — ios/Runner/Info.plist'e ekle: <key>ITSAppUsesNonExemptEncryption</key><false/> (yoksa her build'de 'Missing Compliance')"
[ -f "$APP/PrivacyInfo.xcprivacy" ] ||
  echo "! Uygulama düzeyinde PrivacyInfo.xcprivacy yok (Flutter ve eklentiler kendi manifestini taşır; uygulama gerekçeli API kullanıyorsa ios/Runner'a ekle — store-release)."
echo "→ Archive tamam: $ARCHIVE ($BUNDLE_ID $VERSION ($BUILD))"

# --- 3) ExportOptions.plist ---------------------------------------------------------
EO=$OUT/ExportOptions.plist
cat >"$EO" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
EOF
plutil -lint "$EO" >/dev/null || die "ExportOptions.plist geçersiz: $EO"
echo "→ ExportOptions.plist: $EO (app-store-connect, upload, takım $TEAM_ID)"

if [ "$DRY" = 1 ]; then
  echo "✔ Dry-run tamam: imzasız archive + ExportOptions.plist. Apple'a hiçbir şey gönderilmedi."
  exit 0
fi

# --- 4) İmzala + App Store Connect'e yükle ------------------------------------------
echo "→ App Store Connect'e yükleniyor (dağıtım imzası + upload, birkaç dakika) — log: $OUT/upload.log"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EO" -exportPath "$OUT/export" \
  -allowProvisioningUpdates >"$OUT/upload.log" 2>&1 ||
  { explain "$OUT/upload.log" >&2; die "Yükleme başarısız."; }
grep -q "EXPORT SUCCEEDED" "$OUT/upload.log" || { explain "$OUT/upload.log" >&2; die "Yükleme sonucu belirsiz (EXPORT SUCCEEDED yok)."; }
UP=$(grep -iE "upload(ed)? (succeeded|successful)|uploaded (package|.*\.ipa)|Progress.*Upload" "$OUT/upload.log" | tail -1 || true)
echo "${UP:-→ (xcodebuild ayrı bir 'Upload succeeded' satırı yazmadı; EXPORT SUCCEEDED + destination=upload = yüklendi)}"
grep -E "ITMS-[0-9]+" "$OUT/upload.log" | sed 's/^/! uyarı: /' || true

if [ ! -f "$LEDGER" ]; then
  mkdir -p "$(dirname "$LEDGER")"
  printf '# TestFlight yüklemeleri\n\n`tool/upload_testflight.sh` başarılı her yüklemeden sonra bir satır ekler. Aynı sürümde build numarası tekrar yüklenemez.\n\n| Tarih | Sürüm | Build | Takım |\n|---|---|---|---|\n' >"$LEDGER"
fi
echo "| $(date '+%Y-%m-%d %H:%M') | $VERSION | $BUILD | $TEAM_ID |" >>"$LEDGER"
echo "✔ TestFlight'a yüklendi: $BUNDLE_ID $VERSION ($BUILD). App Store Connect işlemesi ~5–30 dk; bitince dahili test grubuna düşer."
