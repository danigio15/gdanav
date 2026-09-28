"""Chi, fra gli operatori italiani, espone un OCPI a cui si possa bussare.

Da una foto del campo (l'app EVDC, al Centro Direzionale di Napoli) esce un
identificativo: `IT*PLN*EW002913*1`. Non e' un numero interno di
quell'app: e' un EVSE ID in formato eMI3/OCPI — paese, operatore (PLN,
Plenitude), stazione, presa. Vuol dire che quei dati circolano gia' via
OCPI, e che a noi manca solo l'indirizzo a cui chiederli.

`Ocpi.leggiLocations` nel nucleo quel formato lo legge gia', ed e' scritto
e collaudato. Questa sonda cerca la porta: prova i percorsi di scoperta
che lo standard prescrive sui domini degli operatori italiani, e dice chi
risponde qualcosa che somigli a OCPI.

Non manda credenziali e non ne ha. OCPI vuole un token per i dati veri:
`/versions` senza token risponde 401 o 2000 «Client error», ed e' gia'
una risposta utile — vuol dire che la porta c'e' e si puo' chiedere di
entrare. Una GET a un indirizzo di scoperta e' quello per cui lo standard
lo prevede: non si insiste, un tentativo per indirizzo.
"""

import json
import ssl
import sys
import urllib.error
import urllib.request

for flusso in (sys.stdout, sys.stderr):
    try:
        flusso.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass

TESTA = {
    "User-Agent": "gdanav-sonda/1 (+https://github.com/danigio15/gdanav)",
    "Accept": "application/json",
}

# I percorsi che lo standard OCPI prescrive per la scoperta.
PERCORSI = [
    "/ocpi/versions",
    "/ocpi/cpo/versions",
    "/ocpi/emsp/versions",
    "/ocpi/2.2.1/versions",
    "/ocpi/2.2/versions",
    "/api/ocpi/versions",
    "/.well-known/ocpi/versions",
]

# Gli operatori che si incontrano in Italia, col loro party ID dove si sa.
# Plenitude (PLN) e' quello della foto: la sua colonnina al Centro
# Direzionale su OpenStreetMap non c'e'.
OPERATORI = [
    ("Plenitude", "PLN", ["plenitude.com", "eniplenitude.com", "ocpi.plenitude.com"]),
    ("Be Charge", "BEC", ["becharge.it", "ocpi.becharge.it"]),
    ("Enel X Way", "ENX", ["enelxway.com", "ocpi.enelx.com"]),
    ("Ewiva", "EWI", ["ewiva.it", "ocpi.ewiva.it"]),
    ("Free To X", "FTX", ["freetox.it", "ocpi.freetox.it"]),
    ("Atlante", "ATL", ["atlante.energy", "ocpi.atlante.energy"]),
    ("Ionity", "ION", ["ionity.eu", "ocpi.ionity.eu"]),
    ("Electra", "ELC", ["go-electra.com", "ocpi.electra.com"]),
    ("Neogy", "NEO", ["neogy.it"]),
    ("Duferco", "DUF", ["dufercoenergia.com"]),
    ("A2A E-moving", "A2A", ["a2aenergia.eu", "emoving.a2a.eu"]),
    ("Ignitis ON", "IGN", ["ignitison.com", "ignitis.lt"]),
]

_righe: list[str] = []


def avviso(titolo: str, testo: str) -> None:
    print(f"::notice title={titolo}::{testo}"[:3900])
    _righe.append(f"{titolo}: {testo}")


def prova(url: str, secondi: int = 12) -> tuple[int, bytes]:
    contesto = ssl.create_default_context()
    try:
        richiesta = urllib.request.Request(url, headers=TESTA)
        with urllib.request.urlopen(richiesta, timeout=secondi, context=contesto) as r:
            return r.status, r.read(4000)
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read(2000)
        except Exception:  # noqa: BLE001
            return e.code, b""
    except Exception:  # noqa: BLE001
        return 0, b""


def sembra_ocpi(stato: int, corpo: bytes) -> str | None:
    """Cosa dice questa risposta: è una porta OCPI, e di che tipo?"""
    testo = corpo.decode("utf-8", "replace").strip()
    try:
        j = json.loads(testo)
    except Exception:  # noqa: BLE001
        # 401 senza JSON è comunque una porta che chiede le credenziali.
        if stato in (401, 403):
            return f"HTTP {stato}: chiede le credenziali (la porta c'è)"
        return None
    if not isinstance(j, dict):
        return None
    # La busta OCPI: status_code 1000 va bene, 2000/2001 è un errore suo.
    if "status_code" in j:
        codice = j.get("status_code")
        dati = j.get("data")
        versioni = (
            " · ".join(str(v.get("version")) for v in dati if isinstance(v, dict))
            if isinstance(dati, list)
            else ""
        )
        return f"OCPI! status_code {codice}{f' — versioni {versioni}' if versioni else ''}"
    if stato in (401, 403):
        return f"HTTP {stato}: chiede le credenziali (la porta c'è)"
    return None


trovati = 0
for nome, party, domini in OPERATORI:
    esiti = []
    for dominio in domini:
        for percorso in PERCORSI:
            stato, corpo = prova(f"https://{dominio}{percorso}")
            if stato == 0:
                continue
            quale = sembra_ocpi(stato, corpo)
            if quale:
                esiti.append(f"https://{dominio}{percorso} → {quale}")
                trovati += 1
    if esiti:
        avviso(f"OCPI {nome} ({party})", " | ".join(esiti[:4]))
    else:
        avviso(f"OCPI {nome} ({party})", "nessuna porta di scoperta risponde")

avviso("OCPI in tutto", f"{trovati} porte che rispondono qualcosa di OCPI su {len(OPERATORI)} operatori provati")

try:
    import os

    with open(os.path.join(os.environ.get("GDANAV_ANTEPRIME", "."), "ocpi_sonda.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(_righe) + "\n")
except Exception as e:  # noqa: BLE001
    print(f"::warning title=OCPI::non ho potuto scrivere il file: {e}")
