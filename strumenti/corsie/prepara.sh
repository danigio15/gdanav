#!/usr/bin/env bash
# L'archivio delle corsie da un estratto di OpenStreetMap: le tessere z14 del
# relay, compresse, in <uscita>/corsie/v1/14/<x>/<y>.json.gz, e il manifesto
# in <uscita>/corsie/v1/manifesto.json (vedi archivio.mjs).
#
#   strumenti/corsie/prepara.sh <estratto .osm.pbf o .osm> <uscita> [<poligono .poly>] [<fonte>]
#
# Servono osmium-tool (1.16 va bene) e node 22. Variabili:
#   LAVORO          la cartella dei file di appoggio (di norma accanto a <uscita>)
#   TOGLI_INGRESSO  1: cancella l'estratto appena filtrato (sul runner, per il disco)
#   MEMORIA_NODE_MB il tetto di memoria di node (4096)
set -euo pipefail

qui=$(cd "$(dirname "$0")" && pwd)
ingresso=$1
uscita=$2
poly=${3:-}
fonte=${4:-}
lavoro=${LAVORO:-$(dirname "$uscita")/lavoro-corsie}
mkdir -p "$lavoro" "$uscita"

# La data dell'estratto (Geofabrik la scrive nell'intestazione del pbf).
estratto=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$ingresso" 2>/dev/null || true)
echo "estratto: ${estratto:-senza data}"

# 1. Solo le vie e i nodi che possono servire (le vie coi loro nodi).
mapfile -t filtri < <(node "$qui/archivio.mjs" --filtri)
osmium tags-filter --overwrite --progress -o "$lavoro/filtrato.osm.pbf" "$ingresso" "${filtri[@]}"
if [ "${TOGLI_INGRESSO:-}" = 1 ]; then rm -f "$ingresso"; fi
ls -l "$lavoro/filtrato.osm.pbf"

# 2. I luoghi dei nodi sulle vie, in OPL, dritti dentro il convertitore
#    (niente file intermedio: l'OPL dell'Italia sono parecchi GB).
argomenti=(--opl - --uscita "$uscita" --appoggio "$lavoro/appoggio")
if [ -n "$poly" ]; then argomenti+=(--poly "$poly"); fi
if [ -n "$estratto" ]; then argomenti+=(--estratto "$estratto"); fi
if [ -n "$fonte" ]; then argomenti+=(--fonte "$fonte"); fi
osmium add-locations-to-ways --ignore-missing-nodes -f opl,add_metadata=false -o - "$lavoro/filtrato.osm.pbf" \
  | node --max-old-space-size="${MEMORIA_NODE_MB:-4096}" "$qui/archivio.mjs" "${argomenti[@]}"
