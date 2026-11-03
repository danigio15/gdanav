#!/usr/bin/env bash
# Le foto vere di CarPlay (foto-auto.yml): il simulatore dell'iPhone con lo
# schermo CarPlay acceso, GdANav in dimostrazione che guida da sola, e le
# foto dello schermo dell'auto.
#
#   tools/foto-auto/carplay.sh <nome> <Runner.app> <cartella delle foto>
#
# Ogni passo scrive cosa vede: se qualcosa non va, i log e le foto della
# cartella dicono dove.
set -uo pipefail

nome="$1"
app="$2"
# La stessa app com'è uscita da flutter, senza la firma ad hoc: se quella
# firmata non parte, si prova questa, per capire se è colpa della firma.
originale="${4:-}"
out="$3"
mkdir -p "$out"
qui="$(cd "$(dirname "$0")" && pwd)"
pacchetto=it.gdanav.gdanav
tocca() { swift "$qui/tocca.swift" "$@"; }

# Un iPhone qualsiasi fra quelli che ci sono, il più nuovo.
udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
tutti = [(k, x) for k, v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone")]
ultimo = max(k for k, _ in tutti)
nuovi = [x for k, x in tutti if k == ultimo]
pro = [x for x in nuovi if "Pro" in x["name"] and "Max" not in x["name"]]
print((pro or nuovi)[0]["udid"])
')"
echo "iPhone: $udid"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
open -a Simulator --args -CurrentDeviceUDID "$udid"
sleep 10

xcrun simctl install "$udid" "$app"
# La posizione: il permesso già dato, e il punto di partenza della dimostrazione.
xcrun simctl privacy "$udid" grant location-always "$pacchetto" || true
xcrun simctl privacy "$udid" grant location "$pacchetto" || true
xcrun simctl location "$udid" set 42.478,12.39 || true
# Perché un'app non è partita: il rapporto del crash, in breve.
crash() {
  echo "--- crash di Runner"
  for f in ~/Library/Logs/DiagnosticReports/Runner*.ips; do
    [ -f "$f" ] || continue
    echo "$f"
    python3 - "$f" <<'PY' || head -c 3000 "$f"
import json, sys
testo = open(sys.argv[1]).read()
corpo = json.loads(testo.split("\n", 1)[1])
print("eccezione:", corpo.get("exception"))
print("termine:", corpo.get("termination"))
print("asl:", corpo.get("asi"))
fili = corpo.get("threads", [])
immagini = corpo.get("usedImages", [])
for t in fili:
    if not t.get("triggered"):
        continue
    for fr in t.get("frames", [])[:25]:
        nome = immagini[fr["imageIndex"]].get("name", "?") if fr.get("imageIndex", -1) < len(immagini) else "?"
        print("  ", nome, fr.get("symbol", ""), fr.get("symbolLocation", ""))
PY
    rm -f "$f"
  done
}
parte() {
  xcrun simctl launch "$udid" "$pacchetto" && sleep 15 && xcrun simctl spawn "$udid" launchctl list | grep -q "$pacchetto"
}
if ! parte; then
  echo "::warning::GdANav firmata ad hoc non parte"
  crash
  if [ -n "$originale" ]; then
    xcrun simctl uninstall "$udid" "$pacchetto" || true
    xcrun simctl install "$udid" "$originale"
    xcrun simctl privacy "$udid" grant location-always "$pacchetto" || true
    parte || { echo "::warning::neanche quella di flutter parte"; crash; }
  fi
fi
sleep 10
xcrun simctl io "$udid" screenshot "$out/$nome-telefono.png"

# Lo schermo CarPlay: Simulator › I/O › External Displays › CarPlay. Si
# accende dal menu, con gli Eventi di Sistema.
echo "--- i menu del simulatore"
osascript -e 'tell application "Simulator" to activate' \
  -e 'tell application "System Events" to tell process "Simulator" to get name of every menu bar item of menu bar 1' || true
osascript -e 'tell application "System Events" to tell process "Simulator" to get name of every menu item of menu 1 of menu item "External Displays" of menu 1 of menu bar item "I/O" of menu bar 1' || true
osascript -e 'tell application "Simulator" to activate' \
  -e 'tell application "System Events" to tell process "Simulator" to click menu item "CarPlay" of menu 1 of menu item "External Displays" of menu 1 of menu bar item "I/O" of menu bar 1' \
  || echo "::warning::il menu CarPlay non si apre"
sleep 15

echo "--- le finestre"
osascript -e 'tell application "System Events" to tell process "Simulator" to get {name, position, size} of every window' || true
screencapture -x "$out/$nome-mac-1.png" || true
xcrun simctl io "$udid" screenshot --display=external "$out/$nome-carplay-casa.png" \
  || echo "::warning::niente foto dello schermo esterno"

# L'icona di GdANav sulla schermata di CarPlay: la si cerca per la scritta e
# la si tocca. Prima sulla foto di tutto il Mac (punti dello schermo), poi
# sulla foto di CarPlay riportata sulla sua finestra.
# Dove sta la finestra di CarPlay sul Mac: «x y larghezza altezza».
finestra() {
  osascript -e 'tell application "Simulator" to activate' -e 'tell application "System Events" to tell process "Simulator"
    repeat with w in windows
      if name of w contains "CarPlay" then
        perform action "AXRaise" of w
        set p to position of w
        set s to size of w
        return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
      end if
    end repeat
  end tell'
}
# Ancora sulla schermata delle app di CarPlay?
acasa() {
  xcrun simctl io "$udid" screenshot --display=external "$out/.prova.png" >/dev/null 2>&1
  tocca trova "$out/.prova.png" "Now Playing" >/dev/null 2>&1
}
apri() {
  xy="$(tocca trova "$out/$nome-carplay-casa.png" GdANav)" || return 1
  read -r fx fy <<<"$xy"
  f="$(finestra)" || return 1
  echo "finestra CarPlay: $f"
  read -r wx wy ww wh <<<"$f"
  # Lo schermo di CarPlay è 800×480: alto 0,6 della larghezza; sopra, la
  # barra del titolo. L'icona sta sopra la scritta, di 0,18 dello schermo.
  read -r x y <<<"$(python3 -c "
alto = $ww * 0.6
titolo = $wh - alto
print($wx + $fx * $ww, $wy + titolo + ($fy - 0.18) * alto)")"
  echo "l'icona di GdANav sul Mac: $x,$y"
  for modo in cgevent cliclick systemevents; do
    case $modo in
      cgevent) tocca clic "$x" "$y"; sleep 1; tocca clic "$x" "$y" ;;
      cliclick) command -v cliclick >/dev/null || brew install -q cliclick >/dev/null 2>&1
        cliclick "c:${x%.*},${y%.*}" ;;
      systemevents) osascript -e "tell application \"System Events\" to click at {${x%.*}, ${y%.*}}" ;;
    esac
    sleep 8
    if ! acasa; then
      echo "ESITO: GdANav aperta in CarPlay ($modo)"
      return 0
    fi
    echo "con $modo ancora la schermata delle app"
  done
  return 1
}
apri || echo "::warning::ESITO: GdANav non si apre in CarPlay"
sleep 20
screencapture -x "$out/$nome-mac-2.png" || true
xcrun simctl io "$udid" screenshot --display=external "$out/$nome-carplay-guida.png" || true
sleep 30
xcrun simctl io "$udid" screenshot --display=external "$out/$nome-carplay-guida-2.png" || true
xcrun simctl io "$udid" screenshot "$out/$nome-telefono-guida.png" || true
xcrun simctl spawn "$udid" log show --last 3m --predicate 'process == "Runner"' --style compact \
  >"$out/$nome-log.txt" 2>&1 || true
crash
rm -f "$out/.prova.png"
ls -la "$out"
