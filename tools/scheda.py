#!/usr/bin/env python3
"""Le schede dei negozi (docs/negozio/*.md) stanno nelle caselle?

Ogni sezione ha nel titolo il limite dei negozi fra parentesi: si conta il
testo sotto e si dice quale sfora. Si lancia da solo, senza argomenti.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

CARTELLA = Path(__file__).resolve().parent.parent / "docs" / "negozio"


def sezioni(testo: str) -> list[tuple[str, int, str]]:
    """(titolo, limite, testo) per ogni «## Titolo (…N)»."""
    trovate = []
    pezzi = re.split(r"^## (.+)$", testo, flags=re.MULTILINE)
    for titolo, corpo in zip(pezzi[1::2], pezzi[2::2], strict=True):
        numeri = [int(n) for n in re.findall(r"\d+", titolo)]
        if numeri:
            trovate.append((titolo.strip(), min(numeri), corpo.strip()))
    return trovate


def main() -> int:
    errori = 0
    for scheda in sorted(CARTELLA.glob("*.md")):
        for titolo, limite, corpo in sezioni(scheda.read_text(encoding="utf-8")):
            quanto = len(corpo)
            stato = "ok" if quanto <= limite else "TROPPO LUNGO"
            if quanto > limite:
                errori += 1
            print(f"{scheda.name}: {titolo}: {quanto}/{limite} {stato}")
    return 1 if errori else 0


if __name__ == "__main__":
    sys.exit(main())
