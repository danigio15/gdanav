"""Le entità dell'auto riconosciute da sole, dal dispositivo scelto.

Ogni integrazione chiama le cose a modo suo («Battery», «State of charge»,
«Livello batteria», «Ladestand»): si guarda il dominio, la classe, l'unità e
le parole del nome, in più lingue. È solo una proposta: nel passo dopo
l'utente vede tutto e può cambiare.

Le entità di GdAAuto si riconoscono invece dalla chiave (``translation_key``),
che è la stessa in ogni lingua e con ogni nome dell'auto: è il contratto fra
GdAAuto, gdanav e GdAHome (``docs/DATI-AUTO.md`` di GdAAuto).
"""

from __future__ import annotations

from dataclasses import dataclass
import re
import unicodedata

from .const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_BATTERIA_IN_RISCALDAMENTO,
    CONF_CAPACITA_BATTERIA,
    CONF_CLIMA_ACCESO,
    CONF_CONSUMO_MEDIO,
    CONF_ENERGIA_RESIDUA,
    CONF_IN_CARICA,
    CONF_ODOMETRO,
    CONF_POSIZIONE,
    CONF_POTENZA,
    CONF_POTENZA_CARICA,
    CONF_POTENZA_CLIMA,
    CONF_TEMPERATURA_BATTERIA,
    CONF_TEMPERATURA_ESTERNA,
    CONF_TEMPERATURA_INTERNA,
    CONF_VELOCITA,
)

# La piattaforma delle entità di GdAAuto nel registro di Home Assistant.
GDAAUTO = "gdaauto"

# Per ogni casella, le entità di GdAAuto come «dominio.chiave», dalla migliore.
# Senza il sensore binario «in carica» va bene lo stato della ricarica
# (``in_carica`` fra i suoi stati); senza «clima acceso», l'interruttore del
# clima, che GdAAuto mette al suo posto quando il clima si comanda.
_CHIAVI_GDAAUTO: dict[str, tuple[str, ...]] = {
    CONF_BATTERIA: ("sensor.batteria",),
    CONF_AUTONOMIA: ("sensor.autonomia",),
    CONF_IN_CARICA: ("binary_sensor.in_carica", "sensor.stato_ricarica"),
    CONF_POTENZA_CARICA: ("sensor.potenza_ricarica",),
    CONF_TEMPERATURA_BATTERIA: ("sensor.temperatura_batteria",),
    CONF_POSIZIONE: ("device_tracker.posizione",),
    CONF_TEMPERATURA_ESTERNA: ("sensor.temperatura_esterna",),
    CONF_VELOCITA: ("sensor.velocita",),
    CONF_POTENZA: ("sensor.potenza",),
    CONF_ODOMETRO: ("sensor.odometro",),
    CONF_ENERGIA_RESIDUA: ("sensor.energia_residua",),
    CONF_CAPACITA_BATTERIA: ("sensor.capacita_batteria",),
    CONF_CONSUMO_MEDIO: ("sensor.consumo_medio",),
    CONF_POTENZA_CLIMA: ("sensor.potenza_riscaldatore",),
    CONF_CLIMA_ACCESO: ("binary_sensor.clima_acceso", "switch.clima"),
    CONF_BATTERIA_IN_RISCALDAMENTO: ("binary_sensor.batteria_in_riscaldamento",),
    CONF_TEMPERATURA_INTERNA: ("sensor.temperatura_interna",),
}


@dataclass(frozen=True)
class Entita:
    entity_id: str
    nome: str = ""
    unita: str | None = None
    classe: str | None = None
    # Dal registro delle entità: chi l'ha creata e con che chiave. Bastano
    # per GdAAuto; per le altre integrazioni contano le parole.
    piattaforma: str | None = None
    chiave: str | None = None

    @property
    def dominio(self) -> str:
        return self.entity_id.split(".", 1)[0]

    @property
    def testo(self) -> str:
        """Nome e id, minuscoli e senza accenti: «Velocità» e «velocita» sono uguali."""
        grezzo = f"{self.nome} {self.entity_id.split('.', 1)[-1].replace('_', ' ')}".lower()
        return "".join(c for c in unicodedata.normalize("NFKD", grezzo) if not unicodedata.combining(c))


def _c(*parole: str) -> re.Pattern[str]:
    return re.compile("|".join(parole))


_TEMPERATURE = {"°C", "°F", "K"}
_POTENZE = {"W", "kW"}
_DISTANZE = {"km", "mi", "m"}
_VELOCITA = {"km/h", "mph", "m/s"}
_ENERGIE = {"kWh", "Wh"}
# Il consumo medio, comunque lo scriva l'integrazione (senza spazi, minuscolo).
CONSUMI = {"kwh/100km", "wh/km", "kwh/km", "kwh/100mi", "wh/mi", "km/kwh", "mi/kwh"}

# Cose che si chiamano «batteria» ma non sono la batteria di trazione.
_NON_TRAZIONE = _c(r"12 ?v", "aux", "phone", "telefono", "key", "chiave", "remote", "sensor battery", "tpms")
_OBIETTIVO = _c("target", "limit", "limite", "obiettivo", "max", "min", "health", "salute", r"\bsoh\b", "capacity")
_BATTERIA = _c("battery", "batteria", "akku", "batterie", r"\bbms\b", "pack")
_CLIMA = _c("riscald", "heater", "heating", r"\bclima", "climat", "hvac", r"\bptc\b", "heizung", "chauffage", "klima")


def _batteria(e: Entita) -> bool:
    if e.dominio != "sensor" or _NON_TRAZIONE.search(e.testo) or _OBIETTIVO.search(e.testo):
        return False
    if e.classe == "battery":
        return True
    return e.unita == "%" and bool(
        _c(
            r"\bsoc\b", "battery", "batteria", "state of charge", "ladestand", "akku", "batterie", "charge level"
        ).search(e.testo)
    )


def _autonomia(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and e.unita in _DISTANZE
        and bool(_c("range", "autonomia", "reichweite", "autonomie", "remaining").search(e.testo))
        and not _c("target", "max", "full", "wltp").search(e.testo)
    )


def _in_carica(e: Entita) -> bool:
    parole = _c("charging", "in carica", "in ricarica", r"\blad(t|en|evorgang)", "en charge", "is charging")
    if e.dominio == "binary_sensor":
        return e.classe == "battery_charging" or bool(
            parole.search(e.testo) and not _c("plug", "cable", "cavo", "door", "port", "sportello").search(e.testo)
        )
    if e.dominio == "sensor":
        return bool(
            _c("charging state", "charging status", "charge state", "stato ricarica", "stato della ricarica").search(
                e.testo
            )
        )
    return False


def _potenza_carica(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and e.unita in _POTENZE
        and bool(_c("charg", "ricarica", "carica", "lade").search(e.testo))
    )


def _temperatura_batteria(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and (e.unita in _TEMPERATURE or e.classe == "temperature")
        and bool(_BATTERIA.search(e.testo))
    )


def _temperatura_esterna(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and (e.unita in _TEMPERATURE or e.classe == "temperature")
        and bool(
            _c("outside", "outdoor", "exterior", "external", "esterna", "ambient", "aussen", "exterieure").search(
                e.testo
            )
        )
    )


def _velocita(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and (e.unita in _VELOCITA or e.classe == "speed")
        and bool(_c("speed", "velocita", "geschwindigkeit", "vitesse").search(e.testo))
        and not _c("wind", "vento", "fan", "max", "average", "media").search(e.testo)
    )


def _potenza(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and e.unita in _POTENZE
        and bool(_c("power", "potenza", "leistung", "puissance").search(e.testo))
        and not _c("charg", "ricarica", "carica", "lade", "max").search(e.testo)
        and not _CLIMA.search(e.testo)
    )


def _odometro(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and e.unita in _DISTANZE
        and bool(
            _c(
                "odometer",
                "odometro",
                "contachilometri",
                "kilometerstand",
                "mileage",
                "total distance",
                "chilometraggio",
                "kilometrage",
            ).search(e.testo)
        )
    )


def _temperatura_interna(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and (e.unita in _TEMPERATURE or e.classe == "temperature")
        and bool(
            _c("interior", "inside", "indoor", "interna", "cabin", "abitacolo", "innen", "habitacle").search(e.testo)
        )
        and not _BATTERIA.search(e.testo)
        # Quella che si chiede al clima non è quella che c'è.
        and not _c("target", "setpoint", "impostat", "desider", "richiest").search(e.testo)
    )


# I dati nuovi sono più facili da sbagliare dei vecchi: ognuno vuole l'unità
# giusta e le sue parole, e non si propone se manca una delle due.


def _energia_residua(e: Entita) -> bool:
    """L'energia che resta, non quella di oggi, dell'ultima ricarica o la capacità."""
    return (
        e.dominio == "sensor"
        and e.unita in _ENERGIE
        and bool(
            _c(
                "remaining",
                "residu",
                "rimanente",
                "restante",
                "available",
                "disponibile",
                "energy left",
                "restenergie",
                "verbleibend",
            ).search(e.testo)
        )
        and not _c(
            "charg",
            "ricaric",
            "lade",
            "capacit",
            "kapazit",
            "oggi",
            "today",
            "giorni",
            "days",
            "week",
            "settiman",
            "ultim",
            "last",
            "total",
        ).search(e.testo)
    )


def _capacita_batteria(e: Entita) -> bool:
    """La capacità utile: quella lorda conta anche la riserva che l'auto non usa."""
    return (
        e.dominio == "sensor"
        and e.unita in _ENERGIE
        and bool(_c("capacity", "capacita", "kapazitat", "capacite").search(e.testo))
        and not _c("gross", "lorda", "brutto", "max").search(e.testo)
    )


def _consumo_medio(e: Entita) -> bool:
    """Un consumo dall'unità (kWh/100 km, Wh/km…), ma non quello istantaneo."""
    return (
        e.dominio == "sensor"
        and (e.unita or "").replace(" ", "").lower() in CONSUMI
        and not _c("instant", "istantane", "current", "attuale", "momentan").search(e.testo)
    )


def _potenza_clima(e: Entita) -> bool:
    return (
        e.dominio == "sensor"
        and e.unita in _POTENZE
        and bool(_CLIMA.search(e.testo))
        and not _c("charg", "ricarica", "lade", "max").search(e.testo)
    )


def _clima_acceso(e: Entita) -> bool:
    """Il clima acceso: un sensore binario o l'interruttore che lo comanda."""
    return (
        e.dominio in ("binary_sensor", "switch")
        and bool(_c(r"\bclima", "climat", "hvac", "air condition", "aria condizionata", "klima").search(e.testo))
        and not _BATTERIA.search(e.testo)
        and not _c(
            "defrost", "sbrinament", "seat", "sedil", "steering", "volante", "schedul", "programm", "timer"
        ).search(e.testo)
    )


def _batteria_in_riscaldamento(e: Entita) -> bool:
    return (
        e.dominio == "binary_sensor"
        and bool(_BATTERIA.search(e.testo))
        and not _NON_TRAZIONE.search(e.testo)
        and bool(_c("heat", "riscald", "warm", "heiz", "chauff", "precondition", "precondiz").search(e.testo))
    )


# Nell'ordine: prima le più facili da confondere, così ognuna prende la sua.
# La potenza del clima viene prima della potenza e di quella della ricarica:
# «Potenza riscaldatore» non deve diventare la potenza dell'auto.
_REGOLE = (
    (CONF_TEMPERATURA_BATTERIA, _temperatura_batteria),
    (CONF_TEMPERATURA_ESTERNA, _temperatura_esterna),
    (CONF_TEMPERATURA_INTERNA, _temperatura_interna),
    (CONF_POTENZA_CLIMA, _potenza_clima),
    (CONF_POTENZA_CARICA, _potenza_carica),
    (CONF_POTENZA, _potenza),
    (CONF_ODOMETRO, _odometro),
    (CONF_AUTONOMIA, _autonomia),
    (CONF_VELOCITA, _velocita),
    (CONF_IN_CARICA, _in_carica),
    (CONF_BATTERIA, _batteria),
    (CONF_POSIZIONE, lambda e: e.dominio == "device_tracker"),
    (CONF_CAPACITA_BATTERIA, _capacita_batteria),
    (CONF_ENERGIA_RESIDUA, _energia_residua),
    (CONF_CONSUMO_MEDIO, _consumo_medio),
    (CONF_BATTERIA_IN_RISCALDAMENTO, _batteria_in_riscaldamento),
    (CONF_CLIMA_ACCESO, _clima_acceso),
)

# A parità, quale preferire: i sensori binari per «in carica» e per il clima,
# il consumo medio di lungo periodo; poi l'ordine dell'integrazione.
_PREFERENZE = {
    CONF_IN_CARICA: lambda e: e.dominio != "binary_sensor",
    CONF_CLIMA_ACCESO: lambda e: e.dominio != "binary_sensor",
    CONF_CONSUMO_MEDIO: lambda e: not _c("average", "medi", "durchschnitt", "moyenne").search(e.testo),
}


def proponi(entita: list[Entita]) -> dict[str, str]:
    """Da tutte le entità del dispositivo, una per casella; nessuna due volte."""
    proposta: dict[str, str] = {}
    # GdAAuto prima, dalla chiave. Una sua entità che gdanav non usa resta
    # fuori anche dalle parole: «Energia di oggi per il clima» non è il clima.
    gdaauto = {f"{e.dominio}.{e.chiave}": e for e in entita if e.piattaforma == GDAAUTO and e.chiave}
    for conf, chiavi in _CHIAVI_GDAAUTO.items():
        if trovata := next((gdaauto[k] for k in chiavi if k in gdaauto), None):
            proposta[conf] = trovata.entity_id
    prese = set(proposta.values())
    altre = [e for e in entita if e.piattaforma != GDAAUTO]
    for conf, regola in _REGOLE:
        if conf in proposta:
            continue
        candidate = [e for e in altre if e.entity_id not in prese and regola(e)]
        if preferenza := _PREFERENZE.get(conf):
            candidate.sort(key=preferenza)
        if candidate:
            proposta[conf] = candidate[0].entity_id
            prese.add(candidate[0].entity_id)
    return proposta
