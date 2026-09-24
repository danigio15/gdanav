"""Il cuore dell'integrazione: tiene il filo col relay e traduce.

Casa → app: lo stato dell'auto, letto dalle entità scelte, e i comandi
consentiti. App → casa: il viaggio (diventa sensori), gli eventi (diventano
``gdanav_evento`` sul bus) e i comandi (solo quelli della lista).
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import json
import logging
from typing import Any

import aiohttp
from homeassistant.components import persistent_notification
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import STATE_ON, STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import Event, EventStateChangedData, HomeAssistant, State, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_call_later, async_track_state_change_event
from homeassistant.util import dt as dt_util

from . import protocollo as p
from .const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_CHIAVE,
    CONF_COMANDI,
    CONF_IN_CARICA,
    CONF_NOME_AUTO,
    CONF_ODOMETRO,
    CONF_POSIZIONE,
    CONF_POTENZA,
    CONF_POTENZA_CARICA,
    CONF_RELAY,
    CONF_TEMPERATURA_BATTERIA,
    CONF_TEMPERATURA_ESTERNA,
    CONF_VELOCITA,
    ENTITA_AUTO,
    EVENTI_APP,
    EVENTO,
    segnale_aggiornamento,
)

_LOGGER = logging.getLogger(__name__)

ATTESE = (1, 2, 5, 10, 30, 60)
RITARDO_INVIO = 2.0
AGGIORNA_OGNI = timedelta(seconds=30)


@dataclass
class Viaggio:
    """L'ultimo viaggio raccontato dall'app."""

    in_viaggio: bool = False
    destinazione: str | None = None
    eta: datetime | None = None
    batteria_arrivo: float | None = None
    prossima_sosta: dict[str, Any] | None = None
    soc_necessario: float | None = None
    soc_necessario_per: str | None = None
    app_collegata: bool = False
    extra: dict[str, Any] = field(default_factory=dict)


def _numero(stato: State | None) -> float | None:
    if stato is None or stato.state in (STATE_UNKNOWN, STATE_UNAVAILABLE):
        return None
    try:
        return float(stato.state)
    except ValueError:
        return None


# Le unità che l'app vuole, da quelle che Home Assistant può avere.
_CONVERSIONI: dict[str, float] = {
    "W": 0.001,
    "kW": 1.0,
    "mph": 1.609344,
    "km/h": 1.0,
    "m/s": 3.6,
    "mi": 1.609344,
    "km": 1.0,
    "m": 0.001,
}


def _misura(stato: State | None) -> float | None:
    """Il numero nell'unità dell'app: kW, km/h, km, °C."""
    valore = _numero(stato)
    if valore is None or stato is None:
        return None
    unita = stato.attributes.get("unit_of_measurement")
    if unita == "°F":
        return round((valore - 32) * 5 / 9, 2)
    return round(valore * _CONVERSIONI.get(unita, 1.0), 4)


def _data(testo: Any) -> datetime | None:
    if not isinstance(testo, str):
        return None
    try:
        return datetime.fromisoformat(testo)
    except ValueError:
        return None


class Hub:
    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self.abbinamento = p.Abbinamento(
            p.da_b64(entry.data[CONF_CHIAVE]), entry.data[CONF_RELAY], entry.data.get(CONF_NOME_AUTO, "")
        )
        self.busta = p.Busta(self.abbinamento)
        self.viaggio = Viaggio()
        self._ws: aiohttp.ClientWebSocketResponse | None = None
        self._attivo = False
        self._annulla_invio: Any = None
        # Il codice da scrivere nell'app al posto del QR, finché vale.
        self._ultimo_aggiornamento: datetime | None = None
        self.codice: str | None = None
        self.codice_scade: datetime | None = None
        self._annulla_codice: Any = None

    # --- ciclo di vita ---------------------------------------------------

    @property
    def entita_auto(self) -> dict[str, str]:
        return {k: v for k in ENTITA_AUTO if (v := self.entry.data.get(k))}

    @property
    def comandi(self) -> list[str]:
        return list(self.entry.options.get(CONF_COMANDI, []))

    async def async_avvia(self) -> None:
        self._attivo = True
        self.entry.async_on_unload(
            async_track_state_change_event(self.hass, list(self.entita_auto.values()), self._auto_cambiata)
        )
        self.entry.async_create_background_task(self.hass, self._ciclo(), f"gdanav relay {self.entry.title}")

    async def async_ferma(self) -> None:
        self._attivo = False
        self._togli_codice()
        if self._annulla_invio:
            self._annulla_invio()
        if self._ws is not None:
            await self._ws.close()

    async def _ciclo(self) -> None:
        sessione = async_get_clientsession(self.hass)
        tentativi = 0
        while self._attivo:
            try:
                async with sessione.ws_connect(self.abbinamento.indirizzo_relay("casa"), heartbeat=30) as ws:
                    self._ws = ws
                    tentativi = 0
                    _LOGGER.debug("Collegato al relay")
                    await self._manda_tutto()
                    async for msg in ws:
                        if msg.type == aiohttp.WSMsgType.TEXT:
                            await self.async_ricevi(msg.data)
                        elif msg.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
                            break
            except (aiohttp.ClientError, TimeoutError) as err:
                _LOGGER.debug("Relay non raggiungibile: %s", err)
            finally:
                self._ws = None
                self._imposta_app(False)
            if not self._attivo:
                return
            await asyncio.sleep(ATTESE[min(tentativi, len(ATTESE) - 1)])
            tentativi += 1

    # --- casa → app ------------------------------------------------------

    async def async_manda(self, tipo: str, dati: dict[str, Any]) -> bool:
        if self._ws is None or self._ws.closed:
            return False
        await self._ws.send_str(self.busta.chiudi(p.Messaggio(tipo, dati), p.MITTENTE_CASA))
        return True

    async def _manda_tutto(self) -> None:
        await self.async_manda(p.STATO_AUTO, self.stato_auto())
        await self.async_manda(p.COMANDI_DISPONIBILI, {"comandi": self._elenco_comandi()})

    def stato_auto(self) -> dict[str, Any]:
        e = self.entita_auto
        get = self.hass.states.get
        batteria = get(e[CONF_BATTERIA]) if CONF_BATTERIA in e else None
        dati: dict[str, Any] = {"batteria": _numero(batteria)}
        if batteria is not None:
            letto = getattr(batteria, "last_reported", None) or batteria.last_updated
            dati["letto"] = letto.isoformat()
        if CONF_AUTONOMIA in e:
            dati["autonomia_km"] = _numero(get(e[CONF_AUTONOMIA]))
        s = get(e[CONF_IN_CARICA]) if CONF_IN_CARICA in e else None
        if s is not None and s.state not in (STATE_UNKNOWN, STATE_UNAVAILABLE):
            dati["in_carica"] = s.state in (STATE_ON, "charging")
        if CONF_POTENZA_CARICA in e:
            dati["potenza_carica_kw"] = _numero(get(e[CONF_POTENZA_CARICA]))
        if CONF_TEMPERATURA_BATTERIA in e:
            dati["temperatura_batteria_c"] = _numero(get(e[CONF_TEMPERATURA_BATTERIA]))
        for conf, chiave in (
            (CONF_TEMPERATURA_ESTERNA, "temperatura_esterna_c"),
            (CONF_VELOCITA, "velocita_kmh"),
            (CONF_POTENZA, "potenza_kw"),
            (CONF_ODOMETRO, "odometro_km"),
        ):
            if conf in e:
                dati[chiave] = _misura(get(e[conf]))
        if CONF_POSIZIONE in e and (s := get(e[CONF_POSIZIONE])) is not None:
            dati["latitudine"] = s.attributes.get("latitude")
            dati["longitudine"] = s.attributes.get("longitude")
        return {k: v for k, v in dati.items() if v is not None}

    def _elenco_comandi(self) -> list[dict[str, str]]:
        elenco = []
        for entity_id in self.comandi:
            s = self.hass.states.get(entity_id)
            elenco.append({"id": entity_id, "nome": s.name if s else entity_id})
        return elenco

    @callback
    def _auto_cambiata(self, _event: Event[EventStateChangedData]) -> None:
        # Più entità cambiano insieme quando l'integrazione dell'auto
        # aggiorna: si aspetta un attimo e si manda una volta sola.
        if self._annulla_invio is None:
            self._annulla_invio = async_call_later(self.hass, RITARDO_INVIO, self._invia_stato)

    async def _invia_stato(self, _now: Any) -> None:
        self._annulla_invio = None
        await self.async_manda(p.STATO_AUTO, self.stato_auto())

    # --- app → casa ------------------------------------------------------

    async def async_ricevi(self, testo: str) -> None:
        try:
            grezzo = json.loads(testo)
        except ValueError:
            return
        if isinstance(grezzo, dict) and "relay" in grezzo:
            if grezzo.get("ruolo") == "app":
                presente = grezzo["relay"] == "presente"
                self._imposta_app(presente)
                if presente:
                    await self._manda_tutto()
            return
        try:
            m = self.busta.apri(testo, p.MITTENTE_APP)
        except p.ErroreProtocollo as err:
            _LOGGER.debug("Busta scartata: %s", err)
            return
        self._imposta_app(True)
        await self._gestisci(m)

    async def _gestisci(self, m: p.Messaggio) -> None:
        d = m.dati
        if m.tipo == p.RICHIEDI_STATO:
            await self._manda_tutto()
            if d.get("aggiorna"):
                self._aggiorna_auto()
        elif m.tipo == p.VIAGGIO:
            v = self.viaggio
            v.in_viaggio = bool(d.get("in_viaggio"))
            dest = d.get("destinazione")
            v.destinazione = dest.get("nome") if isinstance(dest, dict) else None
            v.eta = _data(d.get("eta"))
            v.batteria_arrivo = d.get("batteria_arrivo")
            sosta = d.get("prossima_sosta")
            v.prossima_sosta = sosta if isinstance(sosta, dict) else None
            self._aggiorna()
        elif m.tipo == p.SOC_NECESSARIO:
            self.viaggio.soc_necessario = d.get("batteria")
            self.viaggio.soc_necessario_per = d.get("destinazione")
            self._aggiorna()
        elif m.tipo == p.EVENTO:
            if d.get("evento") in EVENTI_APP:
                self.hass.bus.async_fire(EVENTO, {**d, "config_entry_id": self.entry.entry_id})
        elif m.tipo == p.COMANDO:
            await self._esegui(m)

    async def _esegui(self, m: p.Messaggio) -> None:
        entity_id = m.dati.get("comando")
        esito: dict[str, Any] = {"richiesta": m.id, "ok": False}
        if entity_id not in self.comandi:
            esito["errore"] = "comando non consentito"
            _LOGGER.warning("L'app ha chiesto un comando non consentito: %s", entity_id)
        else:
            dominio = entity_id.split(".", 1)[0]
            servizio = {"script": "turn_on", "button": "press", "scene": "turn_on"}.get(dominio)
            if servizio is None:
                esito["errore"] = "tipo di entità non supportato"
            else:
                try:
                    await self.hass.services.async_call(dominio, servizio, {"entity_id": entity_id}, blocking=True)
                except HomeAssistantError as err:
                    esito["errore"] = str(err)
                else:
                    esito["ok"] = True
        await self.async_manda(p.ESITO_COMANDO, esito)

    # --- dati freschi in viaggio -----------------------------------------

    @callback
    def _aggiorna_auto(self) -> None:
        """L'app in viaggio chiede dati freschi: si fanno rileggere le entità
        dell'auto (come il pulsante «Aggiorna»), al massimo ogni 30 secondi, e
        si rimanda lo stato anche se i valori non sono cambiati."""
        ora = dt_util.utcnow()
        if self._ultimo_aggiornamento and ora - self._ultimo_aggiornamento < AGGIORNA_OGNI:
            return
        self._ultimo_aggiornamento = ora
        self.entry.async_create_background_task(self.hass, self._rileggi(), "gdanav aggiorna auto")

    async def _rileggi(self) -> None:
        entita = list(self.entita_auto.values())
        if entita:
            try:
                async with asyncio.timeout(20):
                    await self.hass.services.async_call(
                        "homeassistant", "update_entity", {"entity_id": entita}, blocking=True
                    )
            except (HomeAssistantError, TimeoutError) as err:
                _LOGGER.debug("Aggiornamento dell'auto non riuscito: %s", err)
        await self.async_manda(p.STATO_AUTO, self.stato_auto())

    # --- il codice al posto del QR ---------------------------------------

    @property
    def _id_notifica(self) -> str:
        return f"gdanav_codice_{self.entry.entry_id}"

    async def async_nuovo_codice(self) -> str:
        """Un codice nuovo: l'abbinamento cifrato va sul relay per dieci minuti."""
        codice = p.nuovo_codice()
        # PBKDF2: qualche decina di millisecondi, fuori dal ciclo degli eventi.
        (_, id_), busta = await self.hass.async_add_executor_job(
            lambda: (p.deriva_codice(codice), p.chiudi_codice(self.abbinamento, codice))
        )
        sessione = async_get_clientsession(self.hass)
        try:
            async with sessione.put(
                p.indirizzo_codice(self.abbinamento.relay, id_),
                data=busta,
                headers={"content-type": "application/json"},
                timeout=aiohttp.ClientTimeout(total=20),
            ) as r:
                if r.status != 201:
                    raise HomeAssistantError(f"Il relay di gdanav ha risposto {r.status}")
        except (aiohttp.ClientError, TimeoutError) as err:
            raise HomeAssistantError(f"Il relay di gdanav non risponde: {err}") from err
        self._togli_codice()
        self.codice = codice
        self.codice_scade = dt_util.utcnow() + p.DURATA_CODICE
        self._annulla_codice = async_call_later(self.hass, p.DURATA_CODICE, self._codice_scaduto)
        persistent_notification.async_create(
            self.hass,
            f"Nell'app gdanav: menu → Home Assistant → «Scrivi il codice», e scrivi\n\n"
            f"**{p.mostra_codice(codice)}**\n\nVale dieci minuti, una volta sola.",
            title=f"Codice per collegare {self.entry.title}",
            notification_id=self._id_notifica,
        )
        self._aggiorna()
        return codice

    def _togli_codice(self) -> None:
        if self._annulla_codice:
            self._annulla_codice()
            self._annulla_codice = None
        if self.codice is not None:
            persistent_notification.async_dismiss(self.hass, self._id_notifica)
        self.codice = None
        self.codice_scade = None

    @callback
    def _codice_scaduto(self, _now: Any) -> None:
        self._annulla_codice = None
        self._togli_codice()
        self._aggiorna()

    @callback
    def _imposta_app(self, presente: bool) -> None:
        # L'app si è collegata: il codice è servito.
        if presente and self.codice is not None:
            self._togli_codice()
            self._aggiorna()
        if self.viaggio.app_collegata != presente:
            self.viaggio.app_collegata = presente
            self._aggiorna()

    @callback
    def _aggiorna(self) -> None:
        async_dispatcher_send(self.hass, segnale_aggiornamento(self.entry.entry_id))
