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
tutti.sort(key=lambda kx: kx[0])
print(tutti[-1][1]["udid"])
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
xcrun simctl launch "$udid" "$pacchetto"
sleep 20
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
apri() {
  if xy="$(tocca trova "$out/$nome-mac-1.png" GdANav)"; then
    read -r fx fy <<<"$xy"
    read -r lw lh <<<"$(tocca schermo)"
    x="$(python3 -c "print($fx*$lw)")"
    y="$(python3 -c "print($fy*$lh)")"
    echo "GdANav sul Mac in $x,$y"
    tocca clic "$x" "$y"
    return 0
  fi
  if xy="$(tocca trova "$out/$nome-carplay-casa.png" GdANav)"; then
    read -r fx fy <<<"$xy"
    finestra="$(osascript -e 'tell application "System Events" to tell process "Simulator"
      repeat with w in windows
        if name of w contains "CarPlay" then
          set p to position of w
          set s to size of w
          return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
        end if
      end repeat
    end tell' || true)"
    echo "finestra CarPlay: $finestra"
    [ -n "$finestra" ] || return 1
    read -r wx wy ww wh <<<"$finestra"
    # La barra del titolo in alto, alta 28 punti.
    x="$(python3 -c "print($wx + $fx*$ww)")"
    y="$(python3 -c "print($wy + 28 + $fy*($wh-28))")"
    echo "GdANav nella finestra CarPlay in $x,$y"
    tocca clic "$x" "$y"
    osascript -e "tell application \"System Events\" to click at {$x, $y}" || true
    return 0
  fi
  return 1
}
apri || echo "::warning::l'icona di GdANav non si trova"
sleep 20
screencapture -x "$out/$nome-mac-2.png" || true
xcrun simctl io "$udid" screenshot --display=external "$out/$nome-carplay-guida.png" || true
sleep 30
xcrun simctl io "$udid" screenshot --display=external "$out/$nome-carplay-guida-2.png" || true
xcrun simctl io "$udid" screenshot "$out/$nome-telefono-guida.png" || true
xcrun simctl spawn "$udid" log show --last 3m --predicate 'process == "Runner"' --style compact \
  >"$out/$nome-log.txt" 2>&1 || true
ls -la "$out"
