"""L'integrazione dentro Home Assistant: configurazione, sensori, eventi, comandi."""

from __future__ import annotations

from typing import Any

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.exceptions import HomeAssistantError
import pytest
from pytest_homeassistant_custom_component.common import MockConfigEntry, async_capture_events, async_mock_service

from custom_components.gdanav import protocollo as p
from custom_components.gdanav.const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_CHIAVE,
    CONF_COMANDI,
    CONF_IN_CARICA,
    CONF_NOME_AUTO,
    CONF_ODOMETRO,
    CONF_POSIZIONE,
    CONF_POTENZA,
    CONF_RELAY,
    CONF_TEMPERATURA_ESTERNA,
    CONF_VELOCITA,
    DOMAIN,
    EVENTO,
)
from custom_components.gdanav.hub import Hub

CHIAVE = bytes(range(32))
RELAY = "wss://relay.esempio.dev"


def _voce(**opzioni: Any) -> MockConfigEntry:
    a = p.Abbinamento(CHIAVE, RELAY, "Model Y")
    return MockConfigEntry(
        domain=DOMAIN,
        title="Model Y",
        unique_id=a.canale,
        data={
            CONF_NOME_AUTO: "Model Y",
            CONF_RELAY: RELAY,
            CONF_CHIAVE: p.b64(CHIAVE),
            CONF_BATTERIA: "sensor.auto_batteria",
            CONF_AUTONOMIA: "sensor.auto_autonomia",
            CONF_IN_CARICA: "binary_sensor.auto_in_carica",
            CONF_POSIZIONE: "device_tracker.auto",
        },
        options=opzioni,
    )


async def _installa(hass: HomeAssistant, **opzioni: Any) -> tuple[MockConfigEntry, Hub]:
    hass.states.async_set("sensor.auto_batteria", "72", {"device_class": "battery", "unit_of_measurement": "%"})
    hass.states.async_set("sensor.auto_autonomia", "310.5")
    hass.states.async_set("binary_sensor.auto_in_carica", "off")
    hass.states.async_set("device_tracker.auto", "home", {"latitude": 45.46, "longitude": 9.19})
    voce = _voce(**opzioni)
    voce.add_to_hass(hass)
    assert await hass.config_entries.async_setup(voce.entry_id)
    await hass.async_block_till_done()
    return voce, voce.runtime_data


class FintoWs:
    """Al posto del WebSocket: tiene quello che la casa manda."""

    closed = False

    def __init__(self) -> None:
        self.inviati: list[str] = []

    async def send_str(self, testo: str) -> None:
        self.inviati.append(testo)

    async def close(self) -> None:
        self.closed = True

    def aperti(self) -> list[p.Messaggio]:
        busta = p.Busta(p.Abbinamento(CHIAVE, RELAY))
        return [busta.apri(t, p.MITTENTE_CASA) for t in self.inviati]


def _dall_app(tipo: str, dati: dict[str, Any]) -> str:
    return p.Busta(p.Abbinamento(CHIAVE, RELAY)).chiudi(p.Messaggio(tipo, dati), p.MITTENTE_APP)


async def test_configurazione(hass: HomeAssistant, senza_relay: None) -> None:
    hass.states.async_set("sensor.auto_batteria", "50", {"device_class": "battery"})
    flusso = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    assert flusso["type"] is FlowResultType.FORM

    sbagliato = await hass.config_entries.flow.async_configure(
        flusso["flow_id"], {CONF_NOME_AUTO: "Kona", CONF_BATTERIA: "sensor.auto_batteria", CONF_RELAY: "https://x"}
    )
    assert sbagliato["errors"] == {CONF_RELAY: "relay_non_valido"}

    fatto = await hass.config_entries.flow.async_configure(
        flusso["flow_id"], {CONF_NOME_AUTO: "Kona", CONF_BATTERIA: "sensor.auto_batteria", CONF_RELAY: RELAY}
    )
    assert fatto["type"] is FlowResultType.CREATE_ENTRY
    assert fatto["title"] == "Kona"
    chiave = p.da_b64(fatto["data"][CONF_CHIAVE])
    assert len(chiave) == 32
    assert fatto["result"].unique_id == p.Abbinamento(chiave, RELAY).canale


async def test_entita_create(hass: HomeAssistant, senza_relay: None) -> None:
    await _installa(hass)
    for entity_id in (
        "sensor.gdanav_destinazione",
        "sensor.gdanav_eta",
        "sensor.gdanav_soc_arrivo",
        "sensor.gdanav_prossima_sosta",
        "sensor.gdanav_soc_necessario",
        "binary_sensor.gdanav_in_viaggio",
        "binary_sensor.gdanav_app_collegata",
        "image.gdanav_abbinamento",
    ):
        assert hass.states.get(entity_id) is not None, entity_id
    assert hass.states.get("binary_sensor.gdanav_in_viaggio").state == "off"


async def test_dati_per_il_consumo_con_le_unita_giuste(hass: HomeAssistant, senza_relay: None) -> None:
    hass.states.async_set("sensor.auto_batteria", "72", {"device_class": "battery", "unit_of_measurement": "%"})
    hass.states.async_set("sensor.fuori", "50", {"unit_of_measurement": "°F"})
    hass.states.async_set("sensor.velocita", "60", {"unit_of_measurement": "mph"})
    hass.states.async_set("sensor.potenza", "15200", {"unit_of_measurement": "W"})
    hass.states.async_set("sensor.contachilometri", "10000", {"unit_of_measurement": "mi"})
    voce = _voce()
    voce = MockConfigEntry(
        domain=DOMAIN,
        title=voce.title,
        unique_id=voce.unique_id,
        data={
            **voce.data,
            CONF_TEMPERATURA_ESTERNA: "sensor.fuori",
            CONF_VELOCITA: "sensor.velocita",
            CONF_POTENZA: "sensor.potenza",
            CONF_ODOMETRO: "sensor.contachilometri",
        },
    )
    voce.add_to_hass(hass)
    assert await hass.config_entries.async_setup(voce.entry_id)
    await hass.async_block_till_done()
    stato = voce.runtime_data.stato_auto()
    assert stato["temperatura_esterna_c"] == 10
    assert abs(stato["velocita_kmh"] - 96.56) < 0.01
    assert stato["potenza_kw"] == 15.2
    assert abs(stato["odometro_km"] - 16093.44) < 0.01


async def test_stato_auto(hass: HomeAssistant, senza_relay: None) -> None:
    _, hub = await _installa(hass)
    stato = hub.stato_auto()
    assert stato["batteria"] == 72
    assert stato["autonomia_km"] == 310.5
    assert stato["in_carica"] is False
    assert stato["latitudine"] == 45.46
    assert "letto" in stato

    hass.states.async_set("sensor.auto_batteria", "unavailable")
    assert "batteria" not in hub.stato_auto()


async def test_viaggio_diventa_sensori(hass: HomeAssistant, senza_relay: None) -> None:
    _, hub = await _installa(hass)
    await hub.async_ricevi(
        _dall_app(
            p.VIAGGIO,
            {
                "in_viaggio": True,
                "destinazione": {"nome": "Bologna", "lat": 44.49, "lon": 11.34},
                "eta": "2026-09-23T12:30:00Z",
                "batteria_arrivo": 24,
                "prossima_sosta": {"nome": "Area Secchia", "batteria_arrivo": 18},
            },
        )
    )
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.gdanav_in_viaggio").state == "on"
    assert hass.states.get("sensor.gdanav_destinazione").state == "Bologna"
    assert hass.states.get("sensor.gdanav_eta").state == "2026-09-23T12:30:00+00:00"
    assert hass.states.get("sensor.gdanav_soc_arrivo").state == "24"
    sosta = hass.states.get("sensor.gdanav_prossima_sosta")
    assert sosta.state == "Area Secchia"
    assert sosta.attributes["batteria_arrivo"] == 18
    assert hass.states.get("binary_sensor.gdanav_app_collegata").state == "on"

    await hub.async_ricevi(_dall_app(p.VIAGGIO, {"in_viaggio": False}))
    await hass.async_block_till_done()
    assert hass.states.get("sensor.gdanav_destinazione").state == "unknown"


async def test_soc_necessario(hass: HomeAssistant, senza_relay: None) -> None:
    _, hub = await _installa(hass)
    await hub.async_ricevi(_dall_app(p.SOC_NECESSARIO, {"batteria": 65, "destinazione": "Roma"}))
    await hass.async_block_till_done()
    s = hass.states.get("sensor.gdanav_soc_necessario")
    assert s.state == "65"
    assert s.attributes["destinazione"] == "Roma"


async def test_eventi(hass: HomeAssistant, senza_relay: None) -> None:
    voce, hub = await _installa(hass)
    eventi = async_capture_events(hass, EVENTO)
    await hub.async_ricevi(_dall_app(p.EVENTO, {"evento": "arrivo_vicino", "minuti": 10}))
    await hub.async_ricevi(_dall_app(p.EVENTO, {"evento": "inventato"}))
    await hass.async_block_till_done()
    assert [e.data for e in eventi] == [{"evento": "arrivo_vicino", "minuti": 10, "config_entry_id": voce.entry_id}]


async def test_busta_estranea_ignorata(hass: HomeAssistant, senza_relay: None) -> None:
    _, hub = await _installa(hass)
    altra = p.Busta(p.Abbinamento.nuovo(RELAY))
    await hub.async_ricevi(altra.chiudi(p.Messaggio(p.VIAGGIO, {"in_viaggio": True}), p.MITTENTE_APP))
    await hub.async_ricevi("{rotto")
    await hass.async_block_till_done()
    assert hass.states.get("binary_sensor.gdanav_in_viaggio").state == "off"


async def test_comando_consentito(hass: HomeAssistant, senza_relay: None) -> None:
    chiamate = async_mock_service(hass, "script", "turn_on")
    _, hub = await _installa(hass, **{CONF_COMANDI: ["script.preriscalda_auto"]})
    ws = FintoWs()
    hub._ws = ws
    await hub.async_ricevi(_dall_app(p.COMANDO, {"comando": "script.preriscalda_auto"}))
    await hass.async_block_till_done()
    assert [c.data["entity_id"] for c in chiamate] == ["script.preriscalda_auto"]
    (esito,) = ws.aperti()
    assert esito.tipo == p.ESITO_COMANDO
    assert esito.dati["ok"] is True


async def test_comando_non_consentito(hass: HomeAssistant, senza_relay: None) -> None:
    chiamate = async_mock_service(hass, "script", "turn_on")
    _, hub = await _installa(hass, **{CONF_COMANDI: ["script.preriscalda_auto"]})
    ws = FintoWs()
    hub._ws = ws
    await hub.async_ricevi(_dall_app(p.COMANDO, {"comando": "script.apri_garage"}))
    await hass.async_block_till_done()
    assert chiamate == []
    (esito,) = ws.aperti()
    assert esito.dati == {"richiesta": esito.dati["richiesta"], "ok": False, "errore": "comando non consentito"}


async def test_app_presente_riceve_tutto(hass: HomeAssistant, senza_relay: None) -> None:
    _, hub = await _installa(hass, **{CONF_COMANDI: ["script.preriscalda_auto"]})
    ws = FintoWs()
    hub._ws = ws
    await hub.async_ricevi('{"relay":"presente","ruolo":"app"}')
    tipi = [m.tipo for m in ws.aperti()]
    assert tipi == [p.STATO_AUTO, p.COMANDI_DISPONIBILI]
    assert ws.aperti()[1].dati["comandi"][0]["id"] == "script.preriscalda_auto"


async def test_cambio_batteria_manda_stato(hass: HomeAssistant, senza_relay: None, freezer) -> None:
    from datetime import timedelta

    from pytest_homeassistant_custom_component.common import async_fire_time_changed

    _, hub = await _installa(hass)
    ws = FintoWs()
    hub._ws = ws
    hass.states.async_set("sensor.auto_batteria", "71")
    hass.states.async_set("sensor.auto_autonomia", "305")
    await hass.async_block_till_done()
    assert ws.inviati == []  # si aspetta che l'auto finisca di aggiornare
    freezer.tick(timedelta(seconds=3))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    (m,) = ws.aperti()
    assert m.dati["batteria"] == 71
    assert m.dati["autonomia_km"] == 305


async def test_qr(hass: HomeAssistant, senza_relay: None) -> None:
    from custom_components.gdanav.image import qr_svg

    _, hub = await _installa(hass)
    svg = qr_svg(hub.abbinamento.uri)
    assert svg.startswith((b"<?xml", b"<svg"))


async def test_pianifica_senza_app(hass: HomeAssistant, senza_relay: None) -> None:
    await _installa(hass)
    with pytest.raises(HomeAssistantError, match="non è collegata"):
        await hass.services.async_call(DOMAIN, "pianifica_viaggio", {"destinazione": "Torino"}, blocking=True)


async def test_pianifica_con_app(hass: HomeAssistant, senza_relay: None) -> None:
    _, hub = await _installa(hass)
    ws = FintoWs()
    hub._ws = ws
    await hass.services.async_call(
        DOMAIN, "pianifica_viaggio", {"destinazione": "Torino", "latitudine": 45.07, "longitudine": 7.69}, blocking=True
    )
    (m,) = ws.aperti()
    assert m.tipo == p.PIANIFICA_VIAGGIO
    assert m.dati == {"destinazione": "Torino", "latitudine": 45.07, "longitudine": 7.69}


async def test_scarica(hass: HomeAssistant, senza_relay: None) -> None:
    voce, _ = await _installa(hass)
    assert await hass.config_entries.async_unload(voce.entry_id)
    await hass.async_block_till_done()
    assert voce.state is config_entries.ConfigEntryState.NOT_LOADED
