"""Il cuore dell'integrazione: tiene il filo col relay e traduce.

Casa → app: lo stato dell'auto, letto dalle entità scelte, e i comandi
consentiti. App → casa: il viaggio (diventa sensori), gli eventi (diventano
``gdanav_evento`` sul bus) e i comandi (solo quelli della lista).
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime
import json
import logging
from typing import Any

import aiohttp
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import STATE_ON, STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import Event, EventStateChangedData, HomeAssistant, State, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.event import async_call_later, async_track_state_change_event

from . import protocollo as p
from .const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_CHIAVE,
    CONF_COMANDI,
    CONF_IN_CARICA,
    CONF_NOME_AUTO,
    CONF_POSIZIONE,
    CONF_POTENZA_CARICA,
    CONF_RELAY,
    CONF_TEMPERATURA_BATTERIA,
    ENTITA_AUTO,
    EVENTI_APP,
    EVENTO,
    segnale_aggiornamento,
)

_LOGGER = logging.getLogger(__name__)

ATTESE = (1, 2, 5, 10, 30, 60)
RITARDO_INVIO = 2.0


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

    @callback
    def _imposta_app(self, presente: bool) -> None:
        if self.viaggio.app_collegata != presente:
            self.viaggio.app_collegata = presente
            self._aggiorna()

    @callback
    def _aggiorna(self) -> None:
        async_dispatcher_send(self.hass, segnale_aggiornamento(self.entry.entry_id))
