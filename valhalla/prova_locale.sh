#!/usr/bin/env bash
# Un Valhalla vero in un minuto, senza Docker: Valhalla da PyPI e la piccola
# mappa di Utrecht che Valhalla usa per le sue prove. Serve alle prove
# (GDANAV_VALHALLA=http://127.0.0.1:8002/), non a guidare.
#
#   pip install pyvalhalla
#   valhalla/prova_locale.sh /tmp/valhalla   # resta acceso in sottofondo
set -euo pipefail

cartella=${1:-/tmp/gdanav-valhalla}
mkdir -p "$cartella"
cd "$cartella"

bin=$(python -c 'import os, valhalla; print(os.path.join(os.path.dirname(valhalla.__file__), "bin"))')
export LD_LIBRARY_PATH="$bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ ! -f utrecht.osm.pbf ]; then
  curl -sSfL -o utrecht.osm.pbf \
    https://raw.githubusercontent.com/valhalla/valhalla/master/test/data/utrecht_netherlands.osm.pbf
fi
valhalla_build_config --mjolnir-tile-dir "$PWD/tiles" --mjolnir-tile-extract "$PWD/tiles.tar" \
  --mjolnir-timezone "$PWD/tz.sqlite" --mjolnir-admin "$PWD/admins.sqlite" > valhalla.json
[ -d tiles ] || "$bin/valhalla_build_tiles" -c valhalla.json utrecht.osm.pbf > build.log 2>&1

nohup "$bin/valhalla_service" valhalla.json 1 > service.log 2>&1 &
for _ in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8002/status > /dev/null; then
    echo "Valhalla acceso su http://127.0.0.1:8002/"
    exit 0
  fi
  sleep 1
done
cat service.log
exit 1
