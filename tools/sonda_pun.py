"""Da dove prende i punti la mappa della PUN.

La Piattaforma Unica Nazionale (MASE + GSE + RSE) mappa oltre 32.000 punti
di ricarica: operatore, potenza, stato. E' esattamente quello che manca a
gdanav, ed e' raccolto per obbligo di legge.

Il primo giro di sonda aveva provato a indovinare gli indirizzi OCPI e
aveva trovato solo la pagina del sito. Questo giro non indovina: apre il
portale, si legge i suoi script, e tira fuori **tutti** gli indirizzi che
la sua stessa mappa chiama per disegnarsi. Se la mappa i punti li prende
da qualche parte, quella parte e' li' dentro.

Serve a sapere **cosa chiedere al MASE**: con l'indirizzo in mano la
domanda non e' piu' «avete un'API?» ma «possiamo usare questa, e a quali
condizioni?». Legge solo quello che il portale serve a chiunque lo apra,
una volta, senza insistere.
"""

import collections
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

for flusso in (sys.stdout, sys.stderr):
    try:
        flusso.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass

TESTA = {
    "User-Agent": "Mozilla/5.0 (compatible; gdanav-sonda/1; +https://github.com/danigio15/gdanav)",
    "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
    "Accept-Language": "it-IT,it;q=0.9",
}

PORTALI = [
    "https://www.piattaformaunicanazionale.it/",
    "https://www.piattaformaunicanazionale.it/mappa",
    "https://www.piattaformaunicanazionale.it/it/mappa",
]

_righe: list[str] = []


def avviso(titolo: str, testo: str) -> None:
    print(f"::notice title={titolo}::{testo}"[:3900])
    _righe.append(f"{titolo}: {testo}")


def prendi(url: str, secondi: int = 25) -> tuple[int, bytes, str]:
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=TESTA), timeout=secondi) as r:
            return r.status, r.read(3_000_000), r.headers.get("content-type", "")
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read(20000), e.headers.get("content-type", "")
        except Exception:  # noqa: BLE001
            return e.code, b"", ""
    except Exception as e:  # noqa: BLE001
        print(f"::warning title=PUN::{url[:110]} — {e}")
        return 0, b"", ""


# 1. Il portale e tutto quello che carica.
testo = ""
base = PORTALI[0]
risorse: set[str] = set()
for portale in PORTALI:
    stato, corpo, _ = prendi(portale)
    if stato != 200 or not corpo:
        avviso("PUN portale", f"{portale} → HTTP {stato}")
        continue
    html = corpo.decode("utf-8", "replace")
    testo += html
    avviso("PUN portale", f"{portale} → HTTP {stato}, {len(corpo)} byte")
    # Gli script e i fogli: nelle app moderne il nome ha l'impronta dentro
    # (main.4f3a.js), e stanno quasi sempre sotto /assets, /static, /_next.
    for trovato in re.findall(r'(?:src|href)="([^"]+\.(?:js|mjs|json))(?:\?[^"]*)?"', html):
        risorse.add(urllib.parse.urljoin(portale, trovato))
    # Anche i pezzi nominati dentro al codice della pagina.
    for trovato in re.findall(r'["\'](/(?:assets|static|_next|js|build)/[A-Za-z0-9._/-]+\.(?:js|mjs|json))["\']', html):
        risorse.add(urllib.parse.urljoin(portale, trovato))

avviso("PUN risorse", f"{len(risorse)} fra script e dati: " + " · ".join(sorted(r.split('/')[-1] for r in risorse)[:14]))

# 2. Dentro ogni script: tutto quello che somiglia a un indirizzo chiamato.
for r in sorted(risorse)[:25]:
    stato, corpo, _ = prendi(r, 30)
    if stato == 200 and corpo:
        testo += corpo.decode("utf-8", "replace")

avviso("PUN letto", f"{len(testo)} caratteri fra pagina e script")

# Indirizzi interi, e percorsi relativi che sembrano un'API.
interi = collections.Counter(
    u.rstrip("'\",);")
    for u in re.findall(r'https?://[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]{10,140}', testo)
)
relativi = collections.Counter(
    p for p in re.findall(r'["\'](/(?:api|rest|v\d|ocpi|services|data|geoserver|wfs|arcgis)[A-Za-z0-9._/{}$-]{0,80})["\']', testo)
)

ospiti = collections.Counter(urllib.parse.urlparse(u).netloc for u in interi)
avviso("PUN domini", str(dict(ospiti.most_common(14))))
avviso("PUN percorsi", " · ".join(p for p, _ in relativi.most_common(18)) or "nessun percorso che sembri un'API")

# Quelli che nominano la ricarica: sono i candidati buoni.
parole = ("ricaric", "charg", "colonn", "stazion", "punti", "ocpi", "infrastruttur", "pdr", "evse")
candidati = [u for u in interi if any(k in u.lower() for k in parole)]
candidati += [urllib.parse.urljoin(base, p) for p in relativi if any(k in p.lower() for k in parole)]
# E comunque tutti i percorsi relativi trovati: sono pochi e vale la pena.
candidati += [urllib.parse.urljoin(base, p) for p in relativi if "{" not in p and "$" not in p]
candidati = sorted(dict.fromkeys(candidati))
avviso("PUN candidati", f"{len(candidati)}: " + " · ".join(c[:90] for c in candidati[:10]))

# 3. Si provano, e si dice cosa rispondono.
buoni = 0
for url in candidati[:25]:
    stato, corpo, tipo = prendi(url, 25)
    if stato == 0:
        continue
    if "json" not in tipo.lower():
        html = corpo.lstrip()[:15].lower().startswith((b"<!doctype", b"<html"))
        avviso("PUN prova", f"{url[:100]} → HTTP {stato}, {len(corpo)} byte, {'la pagina del sito' if html else tipo or 'senza tipo'}")
        continue
    try:
        j = json.loads(corpo)
    except Exception:  # noqa: BLE001
        avviso("PUN prova", f"{url[:100]} → HTTP {stato}, dice JSON ma non lo è")
        continue
    forma = sorted(j)[:12] if isinstance(j, dict) else f"lista di {len(j)}"
    avviso("PUN prova", f"{url[:100]} → HTTP {stato}, {len(corpo)} byte, JSON: {forma}")
    buoni += 1

avviso("PUN esito", f"{buoni} indirizzi che rispondono JSON su {min(len(candidati), 25)} provati")

try:
    with open(os.path.join(os.environ.get("GDANAV_ANTEPRIME", "."), "pun_sonda.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(_righe) + "\n")
except Exception as e:  # noqa: BLE001
    print(f"::warning title=PUN::non ho potuto scrivere il file: {e}")
