"""L'integrazione dentro Home Assistant: configurazione, sensori, eventi, comandi."""

from __future__ import annotations

from typing import Any

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import device_registry as dr, entity_registry as er
import pytest
from pytest_homeassistant_custom_component.common import MockConfigEntry, async_capture_events, async_mock_service

from custom_components.gdanav import protocollo as p
from custom_components.gdanav.const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_BATTERIA_IN_RISCALDAMENTO,
    CONF_CAPACITA_BATTERIA,
    CONF_CHIAVE,
    CONF_CLIMA_ACCESO,
    CONF_COMANDI,
    CONF_CONSUMO_MEDIO,
    CONF_DISPOSITIVO,
    CONF_ENERGIA_RESIDUA,
    CONF_IN_CARICA,
    CONF_NOME_AUTO,
    CONF_ODOMETRO,
    CONF_POSIZIONE,
    CONF_POTENZA,
    CONF_POTENZA_CARICA,
    CONF_POTENZA_CLIMA,
    CONF_RELAY,
    CONF_TEMPERATURA_BATTERIA,
    CONF_TEMPERATURA_ESTERNA,
    CONF_TEMPERATURA_INTERNA,
    CONF_VELOCITA,
    DOMAIN,
    EVENTO,
)
from custom_components.gdanav.hub import Hub

from .test_protocollo import chiavi_stato_auto

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
    assert flusso["step_id"] == "user"
    # Senza dispositivo: le entità si scelgono a mano.
    flusso = await hass.config_entries.flow.async_configure(flusso["flow_id"], {})
    assert flusso["step_id"] == "entita"

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


async def test_dal_dispositivo_le_entita_si_propongono_da_sole(hass: HomeAssistant, senza_relay: None) -> None:
    voce_auto = MockConfigEntry(domain="leapmotor")
    voce_auto.add_to_hass(hass)
    dispositivo = dr.async_get(hass).async_get_or_create(
        config_entry_id=voce_auto.entry_id, identifiers={("leapmotor", "b10")}, name="Leapmotor B10"
    )
    registro = er.async_get(hass)
    for oggetto, nome, stato, attributi in [
        ("battery", "Battery", "64", {"unit_of_measurement": "%", "device_class": "battery"}),
        ("range", "Range", "280", {"unit_of_measurement": "km"}),
        ("charging", "Charging", "off", {"device_class": "battery_charging"}),
        ("battery_temperature", "Battery temperature", "22", {"unit_of_measurement": "°C"}),
        ("outside_temperature", "Outside temperature", "15", {"unit_of_measurement": "°C"}),
        ("odometer", "Odometer", "12345", {"unit_of_measurement": "km"}),
        ("key_battery", "Key battery", "90", {"unit_of_measurement": "%", "device_class": "battery"}),
    ]:
        dominio = "binary_sensor" if oggetto == "charging" else "sensor"
        e = registro.async_get_or_create(
            dominio, "leapmotor", oggetto, device_id=dispositivo.id, original_name=nome, config_entry=voce_auto
        )
        hass.states.async_set(e.entity_id, stato, attributi)

    flusso = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    flusso = await hass.config_entries.flow.async_configure(flusso["flow_id"], {CONF_DISPOSITIVO: dispositivo.id})
    assert flusso["step_id"] == "entita"
    assert flusso["description_placeholders"] == {"trovate": "6"}
    proposti = {str(k): k.description["suggested_value"] for k in flusso["data_schema"].schema if k.description}
    assert proposti[CONF_NOME_AUTO] == "Leapmotor B10"
    assert proposti[CONF_BATTERIA] == "sensor.leapmotor_battery"
    assert proposti[CONF_AUTONOMIA] == "sensor.leapmotor_range"
    assert proposti[CONF_IN_CARICA] == "binary_sensor.leapmotor_charging"
    assert proposti[CONF_ODOMETRO] == "sensor.leapmotor_odometer"
    assert proposti[CONF_TEMPERATURA_ESTERNA] == "sensor.leapmotor_outside_temperature"

    fatto = await hass.config_entries.flow.async_configure(flusso["flow_id"], {**proposti, CONF_RELAY: RELAY})
    assert fatto["type"] is FlowResultType.CREATE_ENTRY
    assert fatto["data"][CONF_BATTERIA] == "sensor.leapmotor_battery"


async def test_un_auto_gdaauto_si_riconosce_dalla_chiave(hass: HomeAssistant, senza_relay: None) -> None:
    """Come la crea GdAAuto: piattaforma ``gdaauto``, ``translation_key`` uguale
    alla chiave di docs/DATI-AUTO.md, e il nome dell'auto scelto dall'utente."""
    voce_auto = MockConfigEntry(domain="gdaauto")
    voce_auto.add_to_hass(hass)
    dispositivo = dr.async_get(hass).async_get_or_create(
        config_entry_id=voce_auto.entry_id, identifiers={("gdaauto", "VIN1")}, name="La rossa"
    )
    registro = er.async_get(hass)
    for dominio, chiave, stato, attributi in [
        ("sensor", "batteria", "64", {"unit_of_measurement": "%", "device_class": "battery"}),
        ("sensor", "autonomia", "280", {"unit_of_measurement": "km"}),
        ("binary_sensor", "in_carica", "off", {"device_class": "battery_charging"}),
        ("sensor", "energia_residua", "41.2", {"unit_of_measurement": "kWh"}),
        ("sensor", "energia_oggi_clima", "1.1", {"unit_of_measurement": "kWh"}),
        ("sensor", "capacita_batteria", "64.4", {"unit_of_measurement": "kWh"}),
        ("sensor", "consumo_medio", "16.2", {"unit_of_measurement": "kWh/100 km"}),
        ("sensor", "potenza_riscaldatore", "800", {"unit_of_measurement": "W"}),
        ("binary_sensor", "clima_acceso", "on", {}),
        ("binary_sensor", "batteria_in_riscaldamento", "off", {}),
        ("sensor", "temperatura_interna", "19", {"unit_of_measurement": "°C"}),
    ]:
        e = registro.async_get_or_create(
            dominio,
            "gdaauto",
            f"VIN1_{chiave}",
            suggested_object_id=f"la_rossa_{chiave}",
            device_id=dispositivo.id,
            original_name=chiave.replace("_", " ").title(),
            translation_key=chiave,
            config_entry=voce_auto,
        )
        hass.states.async_set(e.entity_id, stato, attributi)

    flusso = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    flusso = await hass.config_entries.flow.async_configure(flusso["flow_id"], {CONF_DISPOSITIVO: dispositivo.id})
    proposti = {str(k): k.description["suggested_value"] for k in flusso["data_schema"].schema if k.description}
    assert proposti == {
        CONF_NOME_AUTO: "La rossa",
        CONF_BATTERIA: "sensor.la_rossa_batteria",
        CONF_AUTONOMIA: "sensor.la_rossa_autonomia",
        CONF_IN_CARICA: "binary_sensor.la_rossa_in_carica",
        CONF_ENERGIA_RESIDUA: "sensor.la_rossa_energia_residua",
        CONF_CAPACITA_BATTERIA: "sensor.la_rossa_capacita_batteria",
        CONF_CONSUMO_MEDIO: "sensor.la_rossa_consumo_medio",
        CONF_POTENZA_CLIMA: "sensor.la_rossa_potenza_riscaldatore",
        CONF_CLIMA_ACCESO: "binary_sensor.la_rossa_clima_acceso",
        CONF_BATTERIA_IN_RISCALDAMENTO: "binary_sensor.la_rossa_batteria_in_riscaldamento",
        CONF_TEMPERATURA_INTERNA: "sensor.la_rossa_temperatura_interna",
    }

    fatto = await hass.config_entries.flow.async_configure(flusso["flow_id"], {**proposti, CONF_RELAY: RELAY})
    assert fatto["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()
    stato = fatto["result"].runtime_data.stato_auto()
    assert stato["energia_kwh"] == 41.2
    assert stato["capacita_kwh"] == 64.4
    assert stato["consumo_medio_kwh100"] == 16.2
    assert stato["potenza_clima_w"] == 800
    assert stato["clima_acceso"] is True
    assert stato["batteria_in_riscaldamento"] is False
    assert stato["temperatura_interna_c"] == 19


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
        "button.gdanav_nuovo_codice",
        "sensor.gdanav_codice",
    ):
        assert hass.states.get(entity_id) is not None, entity_id
    assert hass.states.get("binary_sensor.gdanav_in_viaggio").state == "off"
    assert hass.states.get("sensor.gdanav_codice").state == "Nessun codice"


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


async def _con_entita(hass: HomeAssistant, **entita: str) -> Hub:
    voce = _voce()
    voce = MockConfigEntry(domain=DOMAIN, title=voce.title, unique_id=voce.unique_id, data={**voce.data, **entita})
    voce.add_to_hass(hass)
    assert await hass.config_entries.async_setup(voce.entry_id)
    await hass.async_block_till_done()
    return voce.runtime_data


async def test_ogni_dato_nell_unita_dell_app(hass: HomeAssistant, senza_relay: None) -> None:
    """Prima l'autonomia in miglia, la potenza della ricarica in W e la
    temperatura della batteria in °F passavano così com'erano, e i kelvin mai."""
    hass.states.async_set("sensor.auto_batteria", "72", {"device_class": "battery", "unit_of_measurement": "%"})
    hass.states.async_set("sensor.auto_autonomia", "100", {"unit_of_measurement": "mi"})
    hass.states.async_set("sensor.ricarica", "7400", {"unit_of_measurement": "W"})
    hass.states.async_set("sensor.batteria_temp", "41", {"unit_of_measurement": "°F"})
    hass.states.async_set("sensor.fuori", "278.15", {"unit_of_measurement": "K"})
    hass.states.async_set("sensor.dentro", "70", {"unit_of_measurement": "°F"})
    hass.states.async_set("sensor.energia", "41250", {"unit_of_measurement": "Wh"})
    hass.states.async_set("sensor.capacita", "64.5", {"unit_of_measurement": "kWh"})
    hass.states.async_set("sensor.consumo", "6.25", {"unit_of_measurement": "km/kWh"})
    hass.states.async_set("sensor.riscaldatore", "1.5", {"unit_of_measurement": "kW"})
    hass.states.async_set("switch.clima", "on")
    hass.states.async_set("binary_sensor.batteria_scalda", "unavailable")
    hub = await _con_entita(
        hass,
        **{
            CONF_POTENZA_CARICA: "sensor.ricarica",
            CONF_TEMPERATURA_BATTERIA: "sensor.batteria_temp",
            CONF_TEMPERATURA_ESTERNA: "sensor.fuori",
            CONF_TEMPERATURA_INTERNA: "sensor.dentro",
            CONF_ENERGIA_RESIDUA: "sensor.energia",
            CONF_CAPACITA_BATTERIA: "sensor.capacita",
            CONF_CONSUMO_MEDIO: "sensor.consumo",
            CONF_POTENZA_CLIMA: "sensor.riscaldatore",
            CONF_CLIMA_ACCESO: "switch.clima",
            CONF_BATTERIA_IN_RISCALDAMENTO: "binary_sensor.batteria_scalda",
        },
    )
    stato = hub.stato_auto()
    assert abs(stato["autonomia_km"] - 160.93) < 0.01
    assert stato["potenza_carica_kw"] == 7.4
    assert stato["temperatura_batteria_c"] == 5
    assert stato["temperatura_esterna_c"] == 5
    assert abs(stato["temperatura_interna_c"] - 21.11) < 0.01
    assert stato["energia_kwh"] == 41.25
    assert stato["capacita_kwh"] == 64.5
    assert stato["consumo_medio_kwh100"] == 16
    assert stato["potenza_clima_w"] == 1500
    assert stato["clima_acceso"] is True
    # Non disponibile: non si dice, invece di dire «spento».
    assert "batteria_in_riscaldamento" not in stato


async def test_stato_auto_con_tutto_e_come_dice_il_protocollo(hass: HomeAssistant, senza_relay: None) -> None:
    hass.states.async_set("sensor.auto_batteria", "72", {"unit_of_measurement": "%"})
    entita = {
        CONF_POTENZA_CARICA: ("sensor.ricarica", "0", "kW"),
        CONF_TEMPERATURA_BATTERIA: ("sensor.batteria_temp", "20", "°C"),
        CONF_TEMPERATURA_ESTERNA: ("sensor.fuori", "12", "°C"),
        CONF_TEMPERATURA_INTERNA: ("sensor.dentro", "19", "°C"),
        CONF_VELOCITA: ("sensor.velocita", "0", "km/h"),
        CONF_POTENZA: ("sensor.potenza", "0", "kW"),
        CONF_ODOMETRO: ("sensor.odometro", "12345", "km"),
        CONF_ENERGIA_RESIDUA: ("sensor.energia", "46", "kWh"),
        CONF_CAPACITA_BATTERIA: ("sensor.capacita", "64", "kWh"),
        CONF_CONSUMO_MEDIO: ("sensor.consumo", "16", "kWh/100 km"),
        CONF_POTENZA_CLIMA: ("sensor.riscaldatore", "0", "W"),
        CONF_CLIMA_ACCESO: ("binary_sensor.clima", "off", None),
        CONF_BATTERIA_IN_RISCALDAMENTO: ("binary_sensor.batteria_scalda", "off", None),
    }
    for entity_id, stato, unita in entita.values():
        hass.states.async_set(entity_id, stato, {"unit_of_measurement": unita} if unita else {})
    hub = await _con_entita(hass, **{conf: v[0] for conf, v in entita.items()})
    hass.states.async_set("sensor.auto_autonomia", "300", {"unit_of_measurement": "km"})
    hass.states.async_set("binary_sensor.auto_in_carica", "off")
    hass.states.async_set("device_tracker.auto", "home", {"latitude": 45.46, "longitude": 9.19})
    assert set(hub.stato_auto()) == chiavi_stato_auto()


@pytest.mark.parametrize(
    ("unita", "valore", "atteso"),
    [("kWh/100 km", "15.5", 15.5), ("kWh/100km", "15.5", 15.5), ("Wh/km", "155", 15.5), ("kWh/100 mi", "24.94", 15.5)],
)
async def test_il_consumo_medio_in_kwh_ogni_100_km(
    hass: HomeAssistant, senza_relay: None, unita: str, valore: str, atteso: float
) -> None:
    hass.states.async_set("sensor.consumo", valore, {"unit_of_measurement": unita})
    hub = await _con_entita(hass, **{CONF_CONSUMO_MEDIO: "sensor.consumo"})
    hass.states.async_set("sensor.auto_batteria", "72")
    assert abs(hub.stato_auto()["consumo_medio_kwh100"] - atteso) < 0.01


@pytest.mark.parametrize(
    ("stato", "in_carica"),
    [
        ("Charging", True),
        ("in_carica", True),
        ("Charge in progress", True),
        ("charging", True),
        ("on", True),
        ("not_charging", False),
        ("non_in_carica", False),
        ("completata", False),
    ],
)
async def test_in_carica_da_un_sensore_dello_stato(
    hass: HomeAssistant, senza_relay: None, stato: str, in_carica: bool
) -> None:
    hass.states.async_set("sensor.stato_ricarica", stato)
    hub = await _con_entita(hass, **{CONF_IN_CARICA: "sensor.stato_ricarica"})
    hass.states.async_set("sensor.auto_batteria", "72")
    assert hub.stato_auto()["in_carica"] is in_carica


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
    assert hass.states.get("sensor.gdanav_destinazione").state == "Nessun viaggio"
    assert hass.states.get("sensor.gdanav_prossima_sosta").state == "Nessun viaggio"


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
    # A telefono chiuso l'auto cambia e non parte niente: il relay lo
    # butterebbe, e cifrare per nessuno è lavoro buttato.
    hass.states.async_set("sensor.auto_batteria", "73")
    freezer.tick(timedelta(seconds=3))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert ws.inviati == []
    # L'app arriva: riceve tutto, e da lì ogni cambiamento.
    await hub.async_ricevi('{"relay":"presente","ruolo":"app"}')
    assert [m.tipo for m in ws.aperti()] == [p.STATO_AUTO, p.COMANDI_DISPONIBILI]
    assert ws.aperti()[0].dati["batteria"] == 73
    ws.inviati.clear()
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
    # L'app se ne va: di nuovo niente.
    ws.inviati.clear()
    await hub.async_ricevi('{"relay":"assente","ruolo":"app"}')
    hass.states.async_set("sensor.auto_batteria", "70")
    freezer.tick(timedelta(seconds=3))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert ws.inviati == []


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


class FintaSessione:
    """Al posto di aiohttp verso il relay: tiene le buste lasciate."""

    def __init__(self, stato: int = 201) -> None:
        self.stato = stato
        self.lasciate: list[tuple[str, str]] = []

    def put(self, url: str, data: str, **_: Any) -> Any:
        self.lasciate.append((url, data))
        stato = self.stato

        class Risposta:
            status = stato

            async def __aenter__(self) -> Any:
                return self

            async def __aexit__(self, *_: object) -> None:
                return None

        return Risposta()


async def test_codice_al_posto_del_qr(hass: HomeAssistant, senza_relay: None, freezer) -> None:
    from datetime import timedelta
    import json
    from unittest.mock import patch

    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from pytest_homeassistant_custom_component.common import async_fire_time_changed

    _, hub = await _installa(hass)
    sessione = FintaSessione()
    with patch("custom_components.gdanav.hub.async_get_clientsession", return_value=sessione):
        await hass.services.async_call("button", "press", {"entity_id": "button.gdanav_nuovo_codice"}, blocking=True)
    await hass.async_block_till_done()

    codice = hub.codice
    assert codice is not None
    stato = hass.states.get("sensor.gdanav_codice")
    assert stato.state == p.mostra_codice(codice)
    assert "scade" in stato.attributes
    # Sul relay la busta sta sotto il nome ricavato dal codice; il codice
    # non ci arriva, e col codice la busta si apre.
    ((url, busta),) = sessione.lasciate
    chiave, id_ = p.deriva_codice(codice)
    assert url == f"https://relay.esempio.dev/v1/codici/{id_}"
    assert codice not in url
    assert codice not in busta
    b = json.loads(busta)
    chiaro = AESGCM(chiave).decrypt(p.da_b64(b["n"]), p.da_b64(b["c"]), b"gdanav/codice/v1")
    assert p.Abbinamento.da_uri(chiaro.decode()) == hub.abbinamento

    # Dopo dieci minuti non vale più.
    freezer.tick(timedelta(minutes=10, seconds=1))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.gdanav_codice").state == "Nessun codice"


async def test_codice_usato_quando_l_app_arriva(hass: HomeAssistant, senza_relay: None) -> None:
    _, hub = await _installa(hass)
    hub.codice = "7KQ2M9XAPD"
    hub._ws = FintoWs()
    await hub.async_ricevi('{"relay":"presente","ruolo":"app"}')
    assert hub.codice is None


async def test_codice_relay_giu(hass: HomeAssistant, senza_relay: None) -> None:
    from unittest.mock import patch

    _, hub = await _installa(hass)
    with (
        patch("custom_components.gdanav.hub.async_get_clientsession", return_value=FintaSessione(503)),
        pytest.raises(HomeAssistantError, match="503"),
    ):
        await hub.async_nuovo_codice()
    assert hub.codice is None


async def test_in_viaggio_l_app_chiede_dati_freschi(hass: HomeAssistant, senza_relay: None, freezer) -> None:
    from datetime import timedelta

    _, hub = await _installa(hass)
    aggiornate = async_mock_service(hass, "homeassistant", "update_entity")
    ws = FintoWs()
    hub._ws = ws
    await hub.async_ricevi(_dall_app(p.RICHIEDI_STATO, {"aggiorna": True}))
    await hass.async_block_till_done()
    # Si fanno rileggere le entità dell'auto, e lo stato parte due volte:
    # subito e dopo l'aggiornamento.
    assert len(aggiornate) == 1
    assert "sensor.auto_batteria" in aggiornate[0].data["entity_id"]
    assert [m.tipo for m in ws.aperti()].count(p.STATO_AUTO) == 2

    # Una seconda richiesta subito dopo: niente altro aggiornamento.
    await hub.async_ricevi(_dall_app(p.RICHIEDI_STATO, {"aggiorna": True}))
    await hass.async_block_till_done()
    assert len(aggiornate) == 1
    freezer.tick(timedelta(seconds=31))
    await hub.async_ricevi(_dall_app(p.RICHIEDI_STATO, {"aggiorna": True}))
    await hass.async_block_till_done()
    assert len(aggiornate) == 2

    # Senza «aggiorna» (all'avvio dell'app) si manda solo lo stato.
    await hub.async_ricevi(_dall_app(p.RICHIEDI_STATO, {}))
    await hass.async_block_till_done()
    assert len(aggiornate) == 2


async def test_opzioni_cambiate_senza_riavvio(hass: HomeAssistant, senza_relay: None) -> None:
    """I comandi consentiti cambiano: l'app lo sa subito, e la voce non si riavvia."""
    voce, hub = await _installa(hass)
    ws = FintoWs()
    hub._ws = ws
    hass.states.async_set("script.preriscalda_auto", "off", {"friendly_name": "Preriscalda"})
    hass.config_entries.async_update_entry(voce, options={CONF_COMANDI: ["script.preriscalda_auto"]})
    await hass.async_block_till_done()
    assert voce.runtime_data is hub, "la voce non si è riavviata"
    assert not ws.closed, "il filo col relay è rimasto su"
    (m,) = ws.aperti()
    assert m.tipo == p.COMANDI_DISPONIBILI
    assert m.dati["comandi"] == [{"id": "script.preriscalda_auto", "nome": "Preriscalda"}]
    # E il comando passa, senza riavvio.
    chiamate = async_mock_service(hass, "script", "turn_on")
    await hub.async_ricevi(_dall_app(p.COMANDO, {"comando": "script.preriscalda_auto"}))
    await hass.async_block_till_done()
    assert len(chiamate) == 1


class FintoWsDelRelay:
    """Un filo che il relay chiude subito, col codice che si vuole."""

    closed = False

    def __init__(self, close_code: int | None) -> None:
        self.close_code = close_code
        self.inviati: list[str] = []

    async def send_str(self, testo: str) -> None:
        self.inviati.append(testo)

    async def close(self) -> None:
        self.closed = True

    def __aiter__(self) -> FintoWsDelRelay:
        return self

    async def __anext__(self) -> Any:
        raise StopAsyncIteration


class FintaSessioneRelay:
    def __init__(self, ws: FintoWsDelRelay) -> None:
        self.ws = ws
        self.connessioni = 0

    def ws_connect(self, _url: str, **_kw: Any) -> Any:
        self.connessioni += 1
        sessione = self

        class Filo:
            async def __aenter__(self) -> FintoWsDelRelay:
                return sessione.ws

            async def __aexit__(self, *_args: Any) -> bool:
                return False

        return Filo()


@pytest.mark.parametrize(
    ("codice", "attese"),
    [
        # Il relay chiude un filo appena aperto: si riprova subito. Le attese
        # crescenti (fino a un minuto) sono per quando non si riesce ad aprirlo.
        (1006, [1, 1]),
        # Scalzati da un'altra Home Assistant: si aspetta un bel po'.
        (4000, [120, 120]),
    ],
)
async def test_quanto_si_aspetta_prima_di_ricollegarsi(
    hass: HomeAssistant, caplog: pytest.LogCaptureFixture, codice: int, attese: list[int]
) -> None:
    from unittest.mock import patch

    from custom_components.gdanav.hub import Hub

    sessione = FintaSessioneRelay(FintoWsDelRelay(codice))
    aspettato: list[float] = []

    async def aspetta(self: Hub, secondi: float) -> None:
        aspettato.append(secondi)
        if len(aspettato) >= 2:
            self._attivo = False

    with (
        patch("custom_components.gdanav.hub.async_get_clientsession", return_value=sessione),
        patch.object(Hub, "_aspetta", aspetta),
    ):
        _, hub = await _installa(hass)
        await hass.async_block_till_done(wait_background_tasks=True)
    assert sessione.connessioni == 2
    assert aspettato == attese
    assert hub.collegato is False
    # Appena collegata la casa manda tutto, anche se l'app non c'è ancora.
    assert [m.tipo for m in FintoWs.aperti(sessione.ws)] == [p.STATO_AUTO, p.COMANDI_DISPONIBILI] * 2
    assert ("si è collegata al relay con l'abbinamento" in caplog.text) == (codice == 4000)
    assert (hub.ultimo_errore or "").startswith("sostituita") == (codice == 4000)


async def test_diagnostica(hass: HomeAssistant, senza_relay: None, hass_client) -> None:
    from pytest_homeassistant_custom_component.components.diagnostics import get_diagnostics_for_config_entry

    voce, hub = await _installa(hass)
    hub._ws = FintoWs()
    await hub.async_ricevi(_dall_app(p.VIAGGIO, {"in_viaggio": True, "destinazione": {"nome": "Roma"}}))
    await hub.async_ricevi("spazzatura")
    await hub.async_ricevi('{"v":1,"n":"AAAAAAAAAAAAAAAA","c":"AAAA"}')
    diagnostica = await get_diagnostics_for_config_entry(hass, hass_client, voce)
    assert diagnostica["voce"]["dati"][CONF_CHIAVE] == "**REDACTED**"
    assert diagnostica["voce"]["dati"][CONF_BATTERIA] == "sensor.auto_batteria"
    assert diagnostica["relay"]["app_collegata"] is True
    assert diagnostica["relay"]["ricevuti"] == 1
    assert diagnostica["relay"]["scartati"] == 1
    assert diagnostica["stato_auto"]["batteria"] == 72
    assert diagnostica["viaggio"]["destinazione"] == "Roma"
    assert CHIAVE.hex() not in str(diagnostica)
    assert p.b64(CHIAVE) not in str(diagnostica)
