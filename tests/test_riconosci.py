"""Il riconoscimento delle entità dell'auto, su nomi veri di integrazioni diverse."""

from __future__ import annotations

from custom_components.gdanav.const import (
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
from custom_components.gdanav.riconosci import Entita, proponi


def test_un_auto_con_nomi_inglesi() -> None:
    p = proponi(
        [
            Entita("sensor.b10_12v_battery", "12V battery", "%", "battery"),
            Entita("sensor.b10_soc", "State of charge", "%"),
            Entita("sensor.b10_target_soc", "Target SoC", "%"),
            Entita("sensor.b10_range", "Remaining range", "km"),
            Entita("sensor.b10_max_range", "Max range", "km"),
            Entita("binary_sensor.b10_plugged", "Plugged in", None, "plug"),
            Entita("binary_sensor.b10_charging", "Charging", None, "battery_charging"),
            Entita("sensor.b10_charging_power", "Charging power", "kW"),
            Entita("sensor.b10_power", "Power", "kW"),
            Entita("sensor.b10_battery_temp", "Battery temperature", "°C"),
            Entita("sensor.b10_outside_temp", "Outside temperature", "°C"),
            Entita("sensor.b10_speed", "Speed", "km/h"),
            Entita("sensor.b10_mileage", "Mileage", "km"),
            Entita("device_tracker.b10", "Location"),
        ]
    )
    assert p == {
        CONF_BATTERIA: "sensor.b10_soc",
        CONF_AUTONOMIA: "sensor.b10_range",
        CONF_IN_CARICA: "binary_sensor.b10_charging",
        CONF_POTENZA_CARICA: "sensor.b10_charging_power",
        CONF_POTENZA: "sensor.b10_power",
        CONF_TEMPERATURA_BATTERIA: "sensor.b10_battery_temp",
        CONF_TEMPERATURA_ESTERNA: "sensor.b10_outside_temp",
        CONF_VELOCITA: "sensor.b10_speed",
        CONF_ODOMETRO: "sensor.b10_mileage",
        CONF_POSIZIONE: "device_tracker.b10",
    }


def test_nomi_italiani_e_tedeschi() -> None:
    it = proponi(
        [
            Entita("sensor.auto_livello_batteria", "Livello batteria", "%"),
            Entita("sensor.auto_autonomia", "Autonomia residua", "km"),
            Entita("sensor.auto_contachilometri", "Contachilometri", "km"),
            Entita("sensor.auto_temperatura_esterna", "Temperatura esterna", "°C"),
            Entita("sensor.auto_velocita", "Velocità", "km/h"),
        ]
    )
    assert it[CONF_BATTERIA] == "sensor.auto_livello_batteria"
    assert it[CONF_AUTONOMIA] == "sensor.auto_autonomia"
    assert it[CONF_ODOMETRO] == "sensor.auto_contachilometri"
    assert it[CONF_TEMPERATURA_ESTERNA] == "sensor.auto_temperatura_esterna"
    assert it[CONF_VELOCITA] == "sensor.auto_velocita"
    de = proponi(
        [
            Entita("sensor.id3_ladestand", "Ladestand", "%"),
            Entita("sensor.id3_reichweite", "Reichweite", "km"),
            Entita("sensor.id3_kilometerstand", "Kilometerstand", "km"),
        ]
    )
    assert de == {
        CONF_BATTERIA: "sensor.id3_ladestand",
        CONF_AUTONOMIA: "sensor.id3_reichweite",
        CONF_ODOMETRO: "sensor.id3_kilometerstand",
    }


def test_nessuna_entita_in_due_caselle_e_niente_inventato() -> None:
    assert proponi([Entita("sensor.telefono_batteria", "Batteria telefono", "%", "battery")]) == {}
    p = proponi([Entita("sensor.x_battery_charging_power", "Battery charging power", "kW")])
    assert list(p.values()).count("sensor.x_battery_charging_power") == 1


def test_gdaauto_dalla_chiave_non_dal_nome() -> None:
    """Il nome dell'auto e la lingua li sceglie l'utente: conta la chiave."""

    def g(entity_id: str, chiave: str, nome: str = "", unita: str | None = None) -> Entita:
        return Entita(entity_id, nome, unita, piattaforma="gdaauto", chiave=chiave)

    p = proponi(
        [
            g("sensor.saetta_batteria", "batteria", "Akku", "%"),
            g("sensor.saetta_autonomia", "autonomia", "Reichweite", "km"),
            g("sensor.saetta_autonomia_nominale", "autonomia_nominale", "Remaining range WLTP", "km"),
            g("binary_sensor.saetta_in_carica", "in_carica", "Ladevorgang"),
            g("sensor.saetta_stato_ricarica", "stato_ricarica", "Charging state"),
            g("binary_sensor.saetta_cavo_collegato", "cavo_collegato", "Charging cable"),
            g("sensor.saetta_potenza_ricarica", "potenza_ricarica", "Ladeleistung", "kW"),
            g("sensor.saetta_temperatura_batteria", "temperatura_batteria", "Battery", "°C"),
            g("sensor.saetta_temperatura_esterna", "temperatura_esterna", "Fuori", "°C"),
            g("sensor.saetta_temperatura_interna", "temperatura_interna", "Dentro", "°C"),
            g("device_tracker.saetta_posizione", "posizione", "Dove"),
            g("sensor.saetta_velocita", "velocita", "Tempo", "km/h"),
            g("sensor.saetta_potenza", "potenza", "Leistung", "kW"),
            g("sensor.saetta_potenza_riscaldatore", "potenza_riscaldatore", "Power", "W"),
            g("sensor.saetta_odometro", "odometro", "Km", "km"),
            g("sensor.saetta_energia_residua", "energia_residua", "Energie", "kWh"),
            g("sensor.saetta_energia_oggi_clima", "energia_oggi_clima", "Remaining climate energy", "kWh"),
            g("sensor.saetta_capacita_batteria", "capacita_batteria", "Kapazität", "kWh"),
            g("sensor.saetta_consumo_medio", "consumo_medio", "Verbrauch", "kWh/100 km"),
            g("binary_sensor.saetta_clima_acceso", "clima_acceso", "Klima"),
            g("binary_sensor.saetta_batteria_in_riscaldamento", "batteria_in_riscaldamento", "Heizung"),
            g("binary_sensor.saetta_sbrinamento", "sbrinamento", "Climate defrost"),
        ]
    )
    assert p == {
        CONF_BATTERIA: "sensor.saetta_batteria",
        CONF_AUTONOMIA: "sensor.saetta_autonomia",
        CONF_IN_CARICA: "binary_sensor.saetta_in_carica",
        CONF_POTENZA_CARICA: "sensor.saetta_potenza_ricarica",
        CONF_TEMPERATURA_BATTERIA: "sensor.saetta_temperatura_batteria",
        CONF_TEMPERATURA_ESTERNA: "sensor.saetta_temperatura_esterna",
        CONF_TEMPERATURA_INTERNA: "sensor.saetta_temperatura_interna",
        CONF_POSIZIONE: "device_tracker.saetta_posizione",
        CONF_VELOCITA: "sensor.saetta_velocita",
        CONF_POTENZA: "sensor.saetta_potenza",
        CONF_POTENZA_CLIMA: "sensor.saetta_potenza_riscaldatore",
        CONF_ODOMETRO: "sensor.saetta_odometro",
        CONF_ENERGIA_RESIDUA: "sensor.saetta_energia_residua",
        CONF_CAPACITA_BATTERIA: "sensor.saetta_capacita_batteria",
        CONF_CONSUMO_MEDIO: "sensor.saetta_consumo_medio",
        CONF_CLIMA_ACCESO: "binary_sensor.saetta_clima_acceso",
        CONF_BATTERIA_IN_RISCALDAMENTO: "binary_sensor.saetta_batteria_in_riscaldamento",
    }


def test_gdaauto_senza_i_sensori_binari() -> None:
    # Col clima comandabile GdAAuto mette l'interruttore al posto del sensore
    # binario; senza «in carica» resta lo stato della ricarica.
    p = proponi(
        [
            Entita("sensor.b10_batteria", "Batteria", "%", "battery", piattaforma="gdaauto", chiave="batteria"),
            Entita("sensor.b10_stato_ricarica", "Stato ricarica", piattaforma="gdaauto", chiave="stato_ricarica"),
            Entita("switch.b10_clima", "Clima", piattaforma="gdaauto", chiave="clima"),
        ]
    )
    assert p == {
        CONF_BATTERIA: "sensor.b10_batteria",
        CONF_IN_CARICA: "sensor.b10_stato_ricarica",
        CONF_CLIMA_ACCESO: "switch.b10_clima",
    }


def test_un_altra_integrazione_accanto_a_gdaauto_va_a_parole() -> None:
    p = proponi(
        [
            Entita("sensor.b10_batteria", "Batteria", "%", "battery", piattaforma="gdaauto", chiave="batteria"),
            Entita("sensor.meteo_outside_temperature", "Outside temperature", "°C", piattaforma="met"),
        ]
    )
    assert p == {CONF_BATTERIA: "sensor.b10_batteria", CONF_TEMPERATURA_ESTERNA: "sensor.meteo_outside_temperature"}


def test_i_dati_nuovi_a_parole() -> None:
    p = proponi(
        [
            Entita("sensor.ev_soc", "State of charge", "%"),
            Entita("sensor.ev_power", "Power", "kW"),
            Entita("sensor.ev_charging_power", "Charging power", "kW"),
            Entita("sensor.ev_energy_today", "Energy today", "kWh"),
            Entita("sensor.ev_last_charge_energy", "Last charge energy", "kWh"),
            Entita("sensor.ev_remaining_energy", "Remaining energy", "kWh", "energy_storage"),
            Entita("sensor.ev_gross_capacity", "Gross battery capacity", "kWh"),
            Entita("sensor.ev_capacity", "Battery capacity", "kWh"),
            Entita("sensor.ev_instant_consumption", "Instant consumption", "kWh/100km"),
            Entita("sensor.ev_trip_consumption", "Trip consumption", "Wh/km"),
            Entita("sensor.ev_average_consumption", "Average consumption", "Wh/km"),
            Entita("sensor.ev_heater_power", "Heater power", "W"),
            Entita("switch.ev_climate", "Climate"),
            Entita("binary_sensor.ev_climate", "Climate on"),
            Entita("binary_sensor.ev_battery_heating", "Battery heating", None, "heat"),
            Entita("sensor.ev_cabin_target", "Target cabin temperature", "°C"),
            Entita("sensor.ev_interior_temperature", "Interior temperature", "°C"),
            Entita("sensor.ev_outside_temperature", "Outside temperature", "°C"),
        ]
    )
    assert p == {
        CONF_BATTERIA: "sensor.ev_soc",
        CONF_POTENZA: "sensor.ev_power",
        CONF_POTENZA_CARICA: "sensor.ev_charging_power",
        CONF_ENERGIA_RESIDUA: "sensor.ev_remaining_energy",
        CONF_CAPACITA_BATTERIA: "sensor.ev_capacity",
        CONF_CONSUMO_MEDIO: "sensor.ev_average_consumption",
        CONF_POTENZA_CLIMA: "sensor.ev_heater_power",
        CONF_CLIMA_ACCESO: "binary_sensor.ev_climate",
        CONF_BATTERIA_IN_RISCALDAMENTO: "binary_sensor.ev_battery_heating",
        CONF_TEMPERATURA_INTERNA: "sensor.ev_interior_temperature",
        CONF_TEMPERATURA_ESTERNA: "sensor.ev_outside_temperature",
    }


def test_il_riscaldatore_non_ruba_la_potenza_e_l_energia_non_ruba_la_batteria() -> None:
    it = proponi(
        [
            Entita("sensor.auto_potenza_riscaldatore", "Potenza riscaldatore", "W"),
            Entita("sensor.auto_potenza", "Potenza", "kW"),
            Entita("sensor.auto_energia_residua", "Energia residua batteria", "kWh"),
            Entita("sensor.auto_batteria", "Batteria", "%"),
            Entita("sensor.auto_autonomia_residua", "Autonomia residua", "km"),
            Entita("sensor.auto_capacita", "Capacità della batteria", "kWh"),
        ]
    )
    assert it == {
        CONF_POTENZA_CLIMA: "sensor.auto_potenza_riscaldatore",
        CONF_POTENZA: "sensor.auto_potenza",
        CONF_ENERGIA_RESIDUA: "sensor.auto_energia_residua",
        CONF_BATTERIA: "sensor.auto_batteria",
        CONF_AUTONOMIA: "sensor.auto_autonomia_residua",
        CONF_CAPACITA_BATTERIA: "sensor.auto_capacita",
    }
    # Senza le parole giuste niente: un kWh qualsiasi non è l'energia che resta.
    assert proponi([Entita("sensor.casa_energia", "Energia", "kWh")]) == {}
