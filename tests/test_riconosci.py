"""Il riconoscimento delle entità dell'auto, su nomi veri di integrazioni diverse."""

from __future__ import annotations

from custom_components.gdanav.const import (
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
