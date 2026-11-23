#!/bin/zsh
# Flutter oyununu bağlı iPhone'a release build olarak kurar ve başlatır.
# Kullanım: tool/install_ios_device.sh [cihaz adı parçası]   ör. tool/install_ios_device.sh "Mr.DOL 16"
# Boş bırakılırsa: Geliştirici Modu açık, eşleşmiş iPhone'lardan kablolu olan seçilir.
set -eo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.huseyindol.ellyMobileApp          # ios/Runner.xcodeproj → PRODUCT_BUNDLE_IDENTIFIER
MATCH=${1:-}

# --- cihaz bul -------------------------------------------------------------
JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null
DEV=$(python3 - "$JSON" "$MATCH" <<'PY'
import json, sys
path, match = sys.argv[1], sys.argv[2].lower()
cands = []
for d in json.load(open(path))["result"]["devices"]:
    hp, cp, dp = d.get("hardwareProperties", {}), d.get("connectionProperties", {}), d.get("deviceProperties", {})
    name = dp.get("name") or ""
    if hp.get("platform") != "iOS" or cp.get("pairingState") != "paired":
        continue
    if cp.get("transportType") not in ("wired", "localNetwork"):
        continue
    if match and match not in name.lower():
        continue
    dev_off = dp.get("developerModeStatus") != "enabled"
    wired = cp.get("transportType") == "wired"
    cands.append((dev_off, not wired, d["identifier"], hp.get("udid"), name, wired))
if not cands:
    sys.exit("iPhone bulunamadı: kabloyla bağla, kilidini aç, 'Bu Bilgisayara Güven' de.")
cands.sort()
dev_off, _, ident, udid, name, wired = cands[0]
if dev_off:
    sys.exit(f"{name}: Geliştirici Modu kapalı (Ayarlar > Gizlilik ve Güvenlik > Geliştirici Modu).")
print(ident, udid, "kablo" if wired else "ağ", name)
PY
)
rm -f "$JSON"
DC_ID=${DEV%% *}; REST=${DEV#* }; UDID=${REST%% *}; REST=${REST#* }; LINK=${REST%% *}; NAME=${REST#* }
echo "→ Cihaz: $NAME ($LINK)"

# --- derle, kur, başlat ----------------------------------------------------
# Release şart: iOS'ta Flutter debug build'i ana ekrandan açılmaz (yalnızca bağlı debugger ile çalışır).
flutter build ios --release
APP=build/ios/iphoneos/Runner.app
xcrun devicectl device install app --device "$DC_ID" "$APP"
xcrun devicectl device process launch --device "$DC_ID" "$BUNDLE_ID"
echo "✔ Kuruldu ve başlatıldı: $BUNDLE_ID → $NAME"
