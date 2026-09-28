"""Da dove prendiamo lo stato delle colonnine, adesso che TomTom non basta.

`Ocpi.leggiLocations` nel nucleo legge già lo stato in tempo reale di ogni
presa nel formato OCPI 2.2.1 — è scritto e non è mai stato collegato a
niente, perché manca l'indirizzo di un feed. In Italia quel feed dovrebbe
essere la PUN, la piattaforma nazionale che il regolamento AFIR obbliga a
pubblicare lo stato dei punti di ricarica.

Questa sonda va a cercarlo. Dalla macchina di chi scrive il codice non si
esce (il proxy blocca tutto tranne GitHub), dal runner della CI sì: apre il
portale, si legge i suoi script, tira fuori gli indirizzi che sembrano
un'API, e li prova uno per uno dicendo cosa risponde.

Non manda credenziali e non ne ha: cerca solo quello che è pubblico.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

# I nomi dei servizi ArcGIS hanno trattini lunghi e accenti. Due conseguenze,
# tutte e due viste in CI: un indirizzo con un carattere non ASCII non entra
# nella riga di richiesta HTTP (e la richiesta muore prima di partire), e
# l'uscita della CI e' ASCII di suo.
for flusso in (sys.stdout, sys.stderr):
    try:
        flusso.reconfigure(encoding="utf-8", errors="replace")
    except Exception:  # noqa: BLE001
        pass

TESTA = {"User-Agent": "gdanav-sonda/1 (+https://github.com/danigio15/gdanav)"}
PORTALE = "https://www.piattaformaunicanazionale.it/"

# Indirizzi da provare comunque, oltre a quelli che si trovano nel portale.
# L'ArcGIS `services9.../Iko2iF79CuZQnhht` non si prova piu': la CI ha
# elencato i suoi 51 servizi e sono Route 66, le Crociate, la Valle dei
# Templi. E' un inquilino ArcGIS del turismo, non le ricariche.
NOTI = [
    "https://www.piattaformaunicanazionale.it/ocpi/versions",
    "https://www.piattaformaunicanazionale.it/api/ocpi/versions",
]


# GitHub mostra una decina di avvisi per passo e butta gli altri: quello che
# questa sonda trova si scrive anche in un file, che va nella release e si
# legge intero.
QUADERNO = os.path.join(os.environ.get("GDANAV_ANTEPRIME", "."), "colonnine_sonda.txt")
_righe: list[str] = []


def avviso(titolo: str, testo: str) -> None:
    print(f"::notice title={titolo}::{testo}"[:3900])
    _righe.append(f"{titolo}: {testo}")


def scrivi_quaderno() -> None:
    try:
        with open(QUADERNO, "w", encoding="utf-8") as f:
            f.write("\n".join(_righe) + "\n")
        print(f"::notice title=Colonnine::tutto quanto in {os.path.basename(QUADERNO)}, {len(_righe)} righe")
    except Exception as e:  # noqa: BLE001
        print(f"::warning title=Colonnine::non ho potuto scrivere il file: {e}")


def prendi(url: str, secondi: int = 25) -> tuple[int, bytes]:
    # Gli indirizzi arrivano da un elenco di servizi altrui: dentro ci sono
    # trattini lunghi e accenti, che vanno percentati o la richiesta non parte.
    url = urllib.parse.quote(url, safe=":/?#[]@!$&'()*+,;=%~")
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=TESTA), timeout=secondi) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception as e:  # noqa: BLE001
        print(f"::warning title=Colonnine::{url[:120]} — {e}")
        return 0, b""


# 1. Il portale, e i suoi script: dentro ci sono gli indirizzi che chiama.
stato, corpo = prendi(PORTALE)
avviso("Colonnine portale", f"{PORTALE} → HTTP {stato}, {len(corpo)} byte")
testo = corpo.decode("utf-8", "replace")
script = re.findall(r'src="([^"]+\.js[^"]*)"', testo)[:8]
for s in script:
    pieno = s if s.startswith("http") else PORTALE.rstrip("/") + "/" + s.lstrip("/")
    st, b = prendi(pieno, 20)
    testo += b.decode("utf-8", "replace")
avviso("Colonnine script", f"{len(script)} script letti, {len(testo)} caratteri in tutto")

# 2. Gli indirizzi che sembrano un'API.
trovati = sorted(
    {
        u.rstrip("',\")")
        for u in re.findall(r'https?://[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]{12,160}', testo)
        if any(k in u.lower() for k in ("api", "arcgis", "rest", "ocpi", "service", "feature", "geoserver"))
    }
)
avviso("Colonnine indirizzi", " · ".join(trovati[:20]) if trovati else "nessun indirizzo che sembri un'API")

# 3. Si provano: i trovati e i noti.
for url in (trovati[:10] + NOTI):
    st, b = prendi(url, 20)
    if st != 200 or not b:
        avviso("Colonnine prova", f"{url[:110]} → HTTP {st}")
        continue
    try:
        j = json.loads(b)
    except Exception:  # noqa: BLE001
        inizio = b[:90].decode("utf-8", "replace").replace("\n", " ").strip()
        html = b.lstrip()[:15].lower().startswith((b"<!doctype", b"<html"))
        # Una pagina web che risponde a qualunque indirizzo non è un'API.
        coda = " (è la pagina del sito, non un servizio)" if html else f": {inizio}"
        avviso("Colonnine prova", f"{url[:110]} → HTTP 200, {len(b)} byte, non JSON{coda}")
        continue
    # Com'è fatto: le chiavi di primo livello bastano a riconoscere OCPI
    # (`data`/`status_code`) da ArcGIS (`services`/`layers`/`features`).
    forma = sorted(j)[:12] if isinstance(j, dict) else f"lista di {len(j)}"
    ocpi = isinstance(j, dict) and ("status_code" in j or "versions" in j)
    avviso("Colonnine prova", f"{url[:110]} → HTTP 200, {len(b)} byte, chiavi {forma}{' ← sembra OCPI' if ocpi else ''}")

    # Un elenco di servizi ArcGIS: i nomi sono la cosa che serve.
    if isinstance(j, dict) and isinstance(j.get("services"), list):
        nomi = [f"{x.get('name')}({x.get('type')})" for x in j["services"]]
        avviso("Colonnine servizi", f"{len(nomi)}: " + " · ".join(nomi[:40]))
        base = url.split("?")[0].rstrip("/")
        cerca = ("ricaric", "charg", "colonnin", "elettric", "_ev", "ev_", "pun", "mobilit")
        for x in j["services"]:
            nome = str(x.get("name", ""))
            if not any(k in nome.lower() for k in cerca):
                continue
            # Dentro il servizio: gli strati e, del primo, i campi. Se c'è
            # uno stato in tempo reale, è lì che si vede.
            st2, b2 = prendi(f"{base}/{nome.split('/')[-1]}/{x.get('type')}?f=pjson", 20)
            try:
                dentro = json.loads(b2)
            except Exception:  # noqa: BLE001
                avviso("Colonnine servizio", f"{nome} → HTTP {st2}, non leggibile")
                continue
            strati = [f"{l.get('id')}:{l.get('name')}" for l in (dentro.get("layers") or [])]
            avviso("Colonnine servizio", f"{nome} → strati {strati[:10]}")
            if not strati:
                continue
            st3, b3 = prendi(f"{base}/{nome.split('/')[-1]}/{x.get('type')}/0?f=pjson", 20)
            try:
                strato = json.loads(b3)
            except Exception:  # noqa: BLE001
                continue
            campi = [str(c.get("name")) for c in (strato.get("fields") or [])]
            avviso("Colonnine campi", f"{nome}/0: " + " · ".join(campi[:40]))



# 4. La domanda vera, adesso che si sa che la PUN non espone OCPI: senza
#    TomTom Search, quanto stato riusciamo a mostrare lo stesso? Open Charge
#    Map dichiara uno stato per presa (`StatusType`), e la chiave ce l'abbiamo
#    gia'. Non e' il tempo reale, ma e' gratis e senza contatore stretto: se
#    copre abbastanza colonnine, la mappa smette di essere tutta grigia.
def quanto_stato_da_ocm() -> None:
    chiave = os.environ.get("OCM", "")
    q = {
        "output": "json",
        "countrycode": "IT",
        "maxresults": "300",
        "compact": "true",
        "verbose": "false",
        "latitude": "40.8518",
        "longitude": "14.2681",
        "distance": "50",
        "distanceunit": "KM",
    }
    if chiave:
        q["key"] = chiave
    st, b = prendi("https://api.openchargemap.io/v3/poi/?" + urllib.parse.urlencode(q), 30)
    if st != 200 or not b:
        avviso("Colonnine OCM", f"HTTP {st}{' (senza chiave)' if not chiave else ''}")
        return
    try:
        elenco = json.loads(b)
    except Exception as e:  # noqa: BLE001
        avviso("Colonnine OCM", f"risposta non leggibile: {e}")
        return
    if not isinstance(elenco, list):
        avviso("Colonnine OCM", f"risposta inattesa: {type(elenco).__name__}")
        return

    # StatusTypeID: 50 in servizio, 75 fuori servizio, 100 operativa,
    # 0/None non dichiarato. Conta quante colonnine dicono qualcosa.
    conStato = conPrese = prese = 0
    stati: dict[str, int] = {}
    for c in elenco:
        if not isinstance(c, dict):
            continue
        suoi = [x for x in (c.get("Connections") or []) if isinstance(x, dict)]
        prese += len(suoi)
        dichiarati = [x.get("StatusTypeID") for x in suoi if x.get("StatusTypeID")]
        conPrese += 1 if suoi else 0
        if dichiarati:
            conStato += 1
        for d in dichiarati:
            stati[str(d)] = stati.get(str(d), 0) + 1
        s = c.get("StatusType")
        if isinstance(s, dict) and s.get("Title"):
            stati[str(s["Title"])] = stati.get(str(s["Title"]), 0) + 1

    avviso(
        "Colonnine OCM",
        f"{len(elenco)} colonnine intorno a Napoli, {prese} prese; "
        f"con uno stato dichiarato: {conStato} su {conPrese or len(elenco)}"
        f"{' (senza chiave)' if not chiave else ''}",
    )
    avviso("Colonnine OCM stati", str(dict(sorted(stati.items(), key=lambda x: -x[1])[:12])) or "nessuno")


quanto_stato_da_ocm()
# 5. Il caso dal campo: il Centro Direzionale di Napoli. «Non te le porta le
#    colonnine e ci sono.» Quante ce ne sono davvero, secondo ogni fonte che
#    si può interrogare? Senza filtri: tutte, con la potenza scritta accanto,
#    così si vede anche quante sono lente (che era il motivo per cui non
#    entravano nei dati di gdanav).
CENTRO_DIREZIONALE = (40.8548, 14.2855)
RAGGIO_M = 1200


def quante_al_centro_direzionale() -> None:
    lat, lon = CENTRO_DIREZIONALE

    # OpenStreetMap, senza nessun filtro. Due tag, non uno: gdanav raccoglie
    # solo `amenity=charging_station`, ma in OpenStreetMap le singole spine
    # dentro un impianto si mappano anche come `man_made=charge_point`, e
    # quelle non le chiediamo proprio. Qui si contano tutte e due, per sapere
    # quanto vale aggiungere il secondo.
    overpass = (
        f"[out:json][timeout:60];("
        f'nwr["amenity"="charging_station"](around:{RAGGIO_M},{lat},{lon});'
        f'nwr["man_made"="charge_point"](around:{RAGGIO_M},{lat},{lon});'
        f");out center tags;"
    )
    for server in ("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"):
        try:
            richiesta = urllib.request.Request(
                server, data=urllib.parse.urlencode({"data": overpass}).encode(), headers=TESTA
            )
            with urllib.request.urlopen(richiesta, timeout=60) as r:
                j = json.load(r)
        except Exception as e:  # noqa: BLE001
            avviso("Centro Direzionale OSM", f"{server.split('/')[2]}: {e}")
            continue
        tutti = j.get("elements", [])
        stazioni = [e for e in tutti if e.get("tags", {}).get("amenity") == "charging_station"]
        spine = [e for e in tutti if e.get("tags", {}).get("man_made") == "charge_point"]
        # Quante prese si contano oggi (solo `socket:*`), e quante se ne
        # conterebbero usando anche `capacity` e le spine mappate a parte.
        def prese(e: dict) -> int:
            tag = e.get("tags", {})
            n = 0
            for k, v in tag.items():
                if k.startswith("socket:") and ":" not in k[7:] and str(v).isdigit():
                    n += int(v)
            return n

        conSocket = sum(prese(e) for e in stazioni)
        conCapacity = sum(
            prese(e) or int(str(e.get("tags", {}).get("capacity", "")) or 0) or 1 for e in stazioni
        )
        avviso(
            "Centro Direzionale prese",
            f"{len(stazioni)} stazioni + {len(spine)} spine mappate a parte (man_made=charge_point); "
            f"prese dai soli socket: {conSocket}; contando anche capacity: {conCapacity}; "
            f"con le spine: {conCapacity + len(spine)}",
        )
        quanteCapacity = sum(1 for e in stazioni if e.get("tags", {}).get("capacity"))
        avviso("Centro Direzionale capacity", f"{quanteCapacity} stazioni su {len(stazioni)} hanno capacity scritto")

        elementi = stazioni
        potenze = []
        operatori: dict[str, int] = {}
        for e in elementi:
            tag = e.get("tags", {})
            nome = str(tag.get("operator") or tag.get("brand") or tag.get("network") or "senza operatore")
            operatori[nome] = operatori.get(nome, 0) + 1
            for k, v in tag.items():
                if k.endswith(":output") or k == "charging_station:output":
                    potenze.append(f"{k.split(':')[-2] if ':' in k else k}={v}")
        # Quante sarebbero passate con la vecchia regola di gdanav.
        rapide = [
            e
            for e in elementi
            if any(k.startswith(("socket:type2_combo", "socket:chademo", "socket:tesla_supercharger")) for k in e.get("tags", {}))
            or re.search(RETI_RAPIDE, str(e.get("tags", {}).get("operator", "")), re.I)
            or re.search(RETI_RAPIDE, str(e.get("tags", {}).get("brand", "")), re.I)
        ]
        avviso(
            "Centro Direzionale OSM",
            f"{len(elementi)} colonnine entro {RAGGIO_M} m; con la vecchia regola «solo rapide» ne passavano "
            f"{len(rapide)}",
        )
        avviso("Centro Direzionale operatori", str(dict(sorted(operatori.items(), key=lambda x: -x[1])[:15])))
        if potenze:
            avviso("Centro Direzionale potenze", " · ".join(sorted(set(potenze))[:20]))
        break

    # Open Charge Map, la fonte che usa anche ABRP come rinforzo.
    chiave = os.environ.get("OCM", "")
    q = {
        "output": "json",
        "compact": "true",
        "verbose": "false",
        "latitude": str(lat),
        "longitude": str(lon),
        "distance": "1.2",
        "distanceunit": "KM",
        "maxresults": "200",
    }
    if chiave:
        q["key"] = chiave
    st, b = prendi("https://api.openchargemap.io/v3/poi/?" + urllib.parse.urlencode(q), 30)
    if st != 200:
        avviso("Centro Direzionale OCM", f"HTTP {st}")
        return
    try:
        elenco = json.loads(b)
    except Exception as e:  # noqa: BLE001
        avviso("Centro Direzionale OCM", f"risposta non leggibile: {e}")
        return
    kw = []
    for c in elenco if isinstance(elenco, list) else []:
        for x in c.get("Connections") or []:
            if isinstance(x, dict) and x.get("PowerKW"):
                kw.append(float(x["PowerKW"]))
    rapide = [p for p in kw if p >= 40]
    avviso(
        "Centro Direzionale OCM",
        f"{len(elenco) if isinstance(elenco, list) else 0} colonnine, {len(kw)} prese; "
        f"da 40 kW in su: {len(rapide)}; potenze {sorted(set(kw))[:14]}",
    )


RETI_RAPIDE = (
    r"Ionity|Tesla|Free To X|Electra|Fastned|Ewiva|Atlante|Allego|"
    r"Plenitude|Be Charge|Enel X|A2A|Neogy|Zunder|Powerdot|Duferco"
)

quante_al_centro_direzionale()
scrivi_quaderno()
