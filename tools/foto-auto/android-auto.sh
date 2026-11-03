#!/usr/bin/env bash
# Le foto vere di Android Auto (foto-auto.yml), dentro l'emulatore acceso da
# android-emulator-runner.
#
#   tools/foto-auto/android-auto.sh <nome> <app.apk> <cartella delle foto>
#
# Lo schermo dell'auto lo disegna l'app Android Auto del telefono
# (com.google.android.projection.gearhead) e lo mostra la Desktop Head Unit
# (DHU) dell'SDK, collegata con `adb forward tcp:5277`. Se l'app Android Auto
# nell'emulatore non c'è, lo si scrive e ci si ferma: senza di lei la DHU
# resta nera.
set -uo pipefail

nome="$1"
apk="$2"
out="$3"
mkdir -p "$out"
rapporto="$out/$nome-android-auto.txt"
# Nessun comando di adb resta appeso per sempre.
a() { timeout 240 adb "$@"; }
echo "$(date -u +%T) inizio" >"$rapporto"

timeout 600 adb wait-for-device
a shell getprop ro.build.fingerprint | tee -a "$rapporto"
a install -r -g "$apk"
pacchetto="$(a shell pm list packages | tr -d '\r' | sed -n 's/^package://p' | grep '^it\.gdanav\.gdanav' | head -1)"
echo "GdANav: $pacchetto" | tee -a "$rapporto"
a shell pm grant "$pacchetto" android.permission.ACCESS_FINE_LOCATION || true
a emu geo fix 12.39 42.478 || true
a shell monkey -p "$pacchetto" -c android.intent.category.LAUNCHER 1
sleep 30
a exec-out screencap -p >"$out/$nome-telefono.png"

echo "--- Android Auto nel telefono?" | tee -a "$rapporto"
a shell pm list packages | tr -d '\r' | grep -i -E 'gearhead|projection|android\.car|templates' | tee -a "$rapporto" || true
if ! a shell pm list packages | grep -q com.google.android.projection.gearhead; then
  {
    echo "NO: com.google.android.projection.gearhead (Android Auto) non c'è in questa immagine dell'emulatore."
    echo "La DHU mostra solo quello che manda Android Auto del telefono: senza, niente schermo dell'auto."
  } | tee -a "$rapporto"
  echo "::warning::Android Auto non c'è nell'emulatore: niente foto dello schermo dell'auto"
  exit 0
fi

# C'è, ma nelle immagini dell'emulatore è solo il «segnaposto» (versione
# «-stub»): l'app vera arriva dal Play Store, con un account Google.
versione="$(a shell dumpsys package com.google.android.projection.gearhead | tr -d '\r' | sed -n 's/.*versionName=//p' | head -1)"
echo "Android Auto: $versione" | tee -a "$rapporto"
if [[ "$versione" == *stub* ]]; then
  {
    echo "NO: Android Auto nell'emulatore è il segnaposto ($versione), senza la proiezione."
    echo "La DHU si collega ma nessuno le risponde («Failed to read from transport»)."
    echo "Serve l'app vera dal Play Store (account Google) o un telefono vero collegato."
  } | tee -a "$rapporto"
  echo "::warning::Android Auto nell'emulatore è solo il segnaposto ($versione)"
fi
a shell am start-foreground-service -n com.google.android.projection.gearhead/.headunit.HeadUnitServerService \
  2>&1 | tee -a "$rapporto" || true
a forward tcp:5277 tcp:5277
dhu="$ANDROID_SDK_ROOT/extras/google/auto/desktop-head-unit"
if [ ! -x "$dhu" ]; then
  echo "NO: la DHU non c'è in $dhu" | tee -a "$rapporto"
  exit 0
fi
export DISPLAY=:99
(Xvfb :99 -screen 0 1920x1080x24 >/dev/null 2>&1 &)
sleep 3
("$dhu" >"$out/$nome-dhu.txt" 2>&1 &)
sleep 40
import -window root "$out/$nome-android-auto.png" || true
a exec-out screencap -p >"$out/$nome-telefono-dopo.png"
pkill -f desktop-head-unit || true
pkill Xvfb || true
