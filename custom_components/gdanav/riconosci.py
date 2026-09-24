"""Le entità dell'auto riconosciute da sole, dal dispositivo scelto.

Ogni integrazione chiama le cose a modo suo («Battery», «State of charge»,
«Livello batteria», «Ladestand»): si guarda il dominio, la classe, l'unità e
le parole del nome, in più lingue. È solo una proposta: nel passo dopo
l'utente vede tutto e può cambiare.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
import unicodedata

from .const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_IN_CARICA,
    CONF_ODOMETRO,
    CONF_POSIZIONE,
    CONF_POTENZA,
    CONF_POTENZA_CARICA,
    CONF_TEMPERATURA_BATTERIA,
    CONF_TEMPERATURA_ESTERNA,
    CONF_VELOCITA,
)


@dataclass(frozen=True)
class Entita:
    entity_id: str
    nome: str = ""
    unita: str | None = None
    classe: str | None = None

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

# Cose che si chiamano «batteria» ma non sono la batteria di trazione.
_NON_TRAZIONE = _c(r"12 ?v", "aux", "phone", "telefono", "key", "chiave", "remote", "sensor battery", "tpms")
_OBIETTIVO = _c("target", "limit", "limite", "obiettivo", "max", "min", "health", "salute", r"\bsoh\b", "capacity")


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
        and bool(_c("battery", "batteria", "akku", "batterie", r"\bbms\b", "pack").search(e.testo))
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


# Nell'ordine: prima le più facili da confondere, così ognuna prende la sua.
_REGOLE = (
    (CONF_TEMPERATURA_BATTERIA, _temperatura_batteria),
    (CONF_TEMPERATURA_ESTERNA, _temperatura_esterna),
    (CONF_POTENZA_CARICA, _potenza_carica),
    (CONF_POTENZA, _potenza),
    (CONF_ODOMETRO, _odometro),
    (CONF_AUTONOMIA, _autonomia),
    (CONF_VELOCITA, _velocita),
    (CONF_IN_CARICA, _in_carica),
    (CONF_BATTERIA, _batteria),
    (CONF_POSIZIONE, lambda e: e.dominio == "device_tracker"),
)


def proponi(entita: list[Entita]) -> dict[str, str]:
    """Da tutte le entità del dispositivo, una per casella; nessuna due volte."""
    proposta: dict[str, str] = {}
    prese: set[str] = set()
    for conf, regola in _REGOLE:
        # A parità, i sensori binari per «in carica», e l'ordine dell'integrazione.
        candidate = [e for e in entita if e.entity_id not in prese and regola(e)]
        if conf == CONF_IN_CARICA:
            candidate.sort(key=lambda e: e.dominio != "binary_sensor")
        if candidate:
            proposta[conf] = candidate[0].entity_id
            prese.add(candidate[0].entity_id)
    return proposta
