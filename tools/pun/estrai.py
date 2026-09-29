#!/usr/bin/env python3
"""La PUN di oggi, per l'archivio delle colonnine.

La fotografia di onData è dell'ottobre 2024: 48.916 punti di ricarica. La
mappa pubblica della PUN oggi ne conta 75.765. Da giugno 2026 il bottone
«Esporta dati» non c'è più, e i dati si leggono solo dall'API del portale,
con le credenziali «ospite» che il sito stesso pubblica in /config.json —
nessun login, le stesse di chi apre la mappa.

È il modo in cui li legge AgID nel suo Cruscotto Italia
(github.com/AgID/cruscotto-italia, etl/sources/pun.py), ogni giorno, e con
la licenza che AgID ci mette: CC BY 4.0, per l'art. 52 c. 2 del CAD (i dati
che la PA pubblica senza una licenza espressa sono aperti) e le Linee Guida
Open Data AgID. Si cita «GSE — Piattaforma Unica Nazionale (PUN)».

Si chiede quello che chiede il sito, al passo di una persona: le pagine
della mappa da 12.000 punti come le chiede lui, i dettagli a blocchi di
100 come li chiede lui, con una pausa fra un blocco e l'altro. Gira in CI
solo quando si rifà l'archivio (commit con «[colonnine]»), non nell'app.

Scrive un CSV con le colonne che legge `Pun.leggiCsv` nel nucleo, più
`operatore` (il nome dell'azienda) e `tempo_reale` (se il gestore manda lo
stato di adesso), e un riassunto sullo standard output.
Le credenziali non si stampano mai.

    pip install requests requests-aws4auth
    python3 tools/pun/estrai.py pun_oggi.csv
"""

from __future__ import annotations

import csv
import json
import math
import re
import sys
import time
from collections import Counter

import requests
from requests_aws4auth import AWS4Auth

SITO = "https://www.piattaformaunicanazionale.it"
API = "https://api.pun.piattaformaunicanazionale.it"
AGENTE = "gdanav-colonnine/1 (+https://github.com/danigio15/gdanav)"
# Quelli che AgID ha letto da /config.json: servono solo se il sito non
# risponde, e se sono cambiati Cognito lo dice subito.
REGIONE_NOTA = "eu-south-1"
POOL_NOTO = "eu-south-1:e3b2ab05-2046-43dd-8ed0-c0f14c69d507"

PAGINA = 12000  # come le chiede la mappa del sito
BLOCCO = 100  # come li chiede il sito (slice(0, 100) nel suo codice)
PAUSA = 0.2  # secondi fra una richiesta e l'altra
MASSIMO_PAGINE = 40

CENTRO_DIREZIONALE = (40.8548, 14.2855)
RAGGIO_M = 1200

COLONNE = [
    "id_location",
    "nome_location",
    "indirizzo",
    "id_evse",
    "stato",
    "standard_del_connettore",
    "potenza_erogabile",
    "latitudine_evse",
    "longitudine_evse",
    "operatore",
    "tempo_reale",
]


def avviso(titolo: str, testo: str) -> None:
    print(f"::warning title={titolo}::{testo}")


def configurazione() -> tuple[str, str]:
    """Regione e identity pool dal /config.json del sito, come fa lui."""
    try:
        r = requests.get(f"{SITO}/config.json", headers={"User-Agent": AGENTE}, timeout=30)
        r.raise_for_status()
        testo = r.text
        # Il nome della chiave non conta: si cerca il valore, che ha una forma sola.
        m = re.search(r"([a-z]{2}-[a-z]+-\d):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", testo)
        if m:
            return m.group(1), m.group(0)
        avviso("PUN", "nel config.json del sito non c'è un identity pool: si usa quello noto")
    except (requests.RequestException, ValueError) as e:
        avviso("PUN", f"config.json non letto ({type(e).__name__}): si usa quello noto")
    return REGIONE_NOTA, POOL_NOTO


def credenziali(regione: str, pool: str) -> AWS4Auth:
    """Credenziali ospite di Cognito: le stesse che riceve chi apre la mappa."""
    url = f"https://cognito-identity.{regione}.amazonaws.com/"

    def chiama(azione: str, corpo: dict) -> dict:
        r = requests.post(
            url,
            headers={
                "Content-Type": "application/x-amz-json-1.1",
                "X-Amz-Target": f"AWSCognitoIdentityService.{azione}",
                "User-Agent": AGENTE,
            },
            data=json.dumps(corpo),
            timeout=30,
        )
        r.raise_for_status()
        return r.json()

    identita = chiama("GetId", {"IdentityPoolId": pool})["IdentityId"]
    c = chiama("GetCredentialsForIdentity", {"IdentityId": identita})["Credentials"]
    return AWS4Auth(c["AccessKeyId"], c["SecretKey"], regione, "execute-api", session_token=c["SessionToken"])


class Pun:
    def __init__(self) -> None:
        self.regione, self.pool = configurazione()
        self.auth = credenziali(self.regione, self.pool)
        self.richieste = 0

    def post(self, percorso: str, corpo: object) -> object:
        """Una richiesta, con un nuovo giro di credenziali se sono scadute e
        due tentativi in più se il server è occupato."""
        for tentativo in range(4):
            time.sleep(PAUSA if tentativo == 0 else 5 * tentativo)
            self.richieste += 1
            r = requests.post(
                f"{API}{percorso}",
                auth=self.auth,
                json=corpo,
                headers={"User-Agent": AGENTE, "Referer": f"{SITO}/"},
                timeout=60,
            )
            if r.status_code in (401, 403):
                self.auth = credenziali(self.regione, self.pool)
                continue
            if r.status_code == 429 or r.status_code >= 500:
                continue
            r.raise_for_status()
            return r.json()
        raise RuntimeError(f"{percorso}: nessuna risposta buona in quattro tentativi (ultima HTTP {r.status_code})")

    def evse(self) -> list[str]:
        """Tutti gli identificativi, pagina per pagina come la mappa."""
        visti: dict[str, None] = {}
        for pagina in range(MASSIMO_PAGINE):
            d = self.post("/v1/chargepoints/public/map/search", {"page": pagina, "size": PAGINA})
            contenuto = (d or {}).get("content") or []
            for p in contenuto:
                if p.get("evse_id"):
                    visti[p["evse_id"]] = None
            ultima = d.get("last")
            if ultima is None:
                ultima = len(contenuto) < PAGINA
            if ultima or not contenuto:
                break
        return list(visti)

    def dettagli(self, ids: list[str]) -> list[dict]:
        tutti: list[dict] = []
        for i in range(0, len(ids), BLOCCO):
            risposta = self.post("/v1/chargepoints/group", ids[i : i + BLOCCO])
            if isinstance(risposta, list):
                tutti.extend(x for x in risposta if isinstance(x, dict))
            if (i // BLOCCO) % 100 == 99:
                print(f"  {i + BLOCCO} di {len(ids)}…", flush=True)
        return tutti


def numero(x: object) -> float | None:
    try:
        v = float(x)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    return v if math.isfinite(v) else None


def indirizzo(luogo: dict) -> str:
    # Qualche indirizzo porta in coda un codice interno: «Via Salvo d'Acquisto, 5 | 2390».
    via = re.sub(r"\s*\|\s*\d+\s*$", "", str(luogo.get("address") or "")).strip()
    citta = str(luogo.get("city") or "").strip()
    if citta and citta.lower() not in via.lower():
        return f"{via}, {citta}" if via else citta
    return via


def riga(rec: dict) -> dict | None:
    """Un punto di ricarica della PUN in una riga del CSV di onData."""
    luogo = rec.get("location") or {}
    xy = rec.get("coordinates") or luogo.get("coordinates") or {}
    lat, lon = numero(xy.get("latitude")), numero(xy.get("longitude"))
    evse = str(rec.get("evse_id") or "").strip()
    if lat is None or lon is None or not evse:
        return None
    connettori = [c for c in rec.get("connectors") or [] if isinstance(c, dict)]
    # Senza un identificativo del posto, il punto fa posto da solo: metterlo
    # insieme a tutti gli altri senza identificativo ne farebbe uno enorme.
    if luogo.get("_id"):
        id_luogo = str(luogo["_id"])
    elif luogo.get("id"):
        id_luogo = f"{luogo.get('party_id') or ''}:{luogo['id']}"
    else:
        id_luogo = f"evse:{evse}"
    return {
        "id_location": id_luogo,
        "nome_location": str(luogo.get("name") or "").strip(),
        "indirizzo": indirizzo(luogo),
        "id_evse": evse,
        "stato": str(rec.get("status") or "").strip(),
        "standard_del_connettore": ",".join(str(c.get("standard") or "") for c in connettori),
        "potenza_erogabile": ",".join(str(c.get("max_electric_power") or 0) for c in connettori),
        "latitudine_evse": lat,
        "longitudine_evse": lon,
        "operatore": str(rec.get("businessName") or "").strip(),
        # «no» se il gestore non manda lo stato di adesso: la PUN ne ripete
        # uno fisso, e l'app non lo deve prendere per vero.
        "tempo_reale": {True: "si", False: "no"}.get(rec.get("realTime"), ""),
    }


def distanza_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    r = math.pi / 180
    h = math.sin((b[0] - a[0]) * r / 2) ** 2 + math.cos(a[0] * r) * math.cos(b[0] * r) * math.sin((b[1] - a[1]) * r / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def main() -> int:
    if len(sys.argv) != 2:
        print("uso: estrai.py uscita.csv", file=sys.stderr)
        return 2
    pun = Pun()
    ids = pun.evse()
    print(f"mappa: {len(ids)} punti di ricarica", flush=True)
    record = pun.dettagli(ids)
    righe = [x for x in map(riga, record) if x]
    with open(sys.argv[1], "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=COLONNE)
        w.writeheader()
        w.writerows(righe)

    stati = Counter(r["stato"] or "?" for r in righe)
    tempo_reale = Counter(r["tempo_reale"] or "?" for r in righe)
    operatori = Counter(r["operatore"] for r in righe if r["operatore"])
    vicine = [r for r in righe if distanza_m(CENTRO_DIREZIONALE, (r["latitudine_evse"], r["longitudine_evse"])) <= RAGGIO_M]
    luoghi = Counter(r["nome_location"] or r["indirizzo"] for r in vicine)
    print(f"dettagli: {len(record)} record, {len(righe)} righe scritte, {pun.richieste} richieste")
    print(f"stato: {dict(stati.most_common())}")
    print(f"stato in tempo reale: {dict(tempo_reale.most_common())}")
    print(f"operatori: {len(operatori)} — {dict(operatori.most_common(12))}")
    print(f"Centro Direzionale, entro {RAGGIO_M} m: {len(vicine)} punti in {len(luoghi)} posti")
    for nome, n in luoghi.most_common(16):
        print(f"  {n:4d}  {nome}")
    # Meno di così vuol dire che qualcosa si è rotto a metà: meglio fermarsi
    # che scrivere un archivio con mezza Italia.
    if len(righe) < 40000:
        print(f"::error title=PUN::solo {len(righe)} righe: l'estrazione non è completa")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
