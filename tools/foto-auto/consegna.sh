#!/usr/bin/env bash
# Le foto fatte dalla CI, consegnate anche fuori dagli artefatti: un commit
# con la sola cartella delle foto, su un riferimento a parte
# (refs/foto-auto/<nome>), che non è un ramo e non fa partire niente.
# Si prende con `git fetch origin 'refs/foto-auto/*:refs/foto-auto/*'`.
#
#   tools/foto-auto/consegna.sh <cartella delle foto> <nome>
set -euo pipefail
cartella="$(cd "$1" && pwd)"
nome="$2"
radice="$(git rev-parse --show-toplevel)"
indice="$(mktemp -u)"
cd "$cartella"
GIT_INDEX_FILE="$indice" git --git-dir="$radice/.git" --work-tree="$cartella" add -A .
albero="$(GIT_INDEX_FILE="$indice" git --git-dir="$radice/.git" write-tree)"
commit="$(git --git-dir="$radice/.git" -c user.name="Le foto dell'auto" -c user.email=foto-auto@localhost \
  commit-tree "$albero" -m "Le foto dell'auto: $nome")"
git --git-dir="$radice/.git" push -f origin "$commit:refs/foto-auto/$nome"
echo "consegnate in refs/foto-auto/$nome ($commit)"
