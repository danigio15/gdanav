"""I sensori del viaggio, riempiti dall'app, e l'auto come la vede l'app."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity, SensorStateClass
from homeassistant.const import (
    PERCENTAGE,
    UnitOfEnergy,
    UnitOfLength,
    UnitOfPower,
    UnitOfSpeed,
    UnitOfTemperature,
)
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from . import GdanavConfigEntry
from .const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_CAPACITA_BATTERIA,
    CONF_CONSUMO_MEDIO,
    CONF_ENERGIA_RESIDUA,
    CONF_ODOMETRO,
    CONF_POTENZA,
    CONF_POTENZA_CARICA,
    CONF_POTENZA_CLIMA,
    CONF_TEMPERATURA_BATTERIA,
    CONF_TEMPERATURA_ESTERNA,
    CONF_TEMPERATURA_INTERNA,
    CONF_VELOCITA,
    segnale_auto,
)
from .entita import EntitaGdanav
from .hub import Hub


@dataclass(frozen=True)
class DatoAuto:
    """Un dato dell'auto come arriva all'app: la chiave in ``stato_auto``, da quale entità."""

    chiave: str
    conf: str
    classe: SensorDeviceClass | None = None
    unita: str | None = None
    misura: SensorStateClass | None = SensorStateClass.MEASUREMENT


GRADI = UnitOfTemperature.CELSIUS
KM = UnitOfLength.KILOMETERS

DATI_AUTO = (
    DatoAuto("batteria", CONF_BATTERIA, SensorDeviceClass.BATTERY, PERCENTAGE),
    DatoAuto("autonomia_km", CONF_AUTONOMIA, SensorDeviceClass.DISTANCE, UnitOfLength.KILOMETERS),
    DatoAuto("potenza_carica_kw", CONF_POTENZA_CARICA, SensorDeviceClass.POWER, UnitOfPower.KILO_WATT),
    DatoAuto(
        "temperatura_batteria_c", CONF_TEMPERATURA_BATTERIA, SensorDeviceClass.TEMPERATURE, UnitOfTemperature.CELSIUS
    ),
    DatoAuto(
        "temperatura_esterna_c", CONF_TEMPERATURA_ESTERNA, SensorDeviceClass.TEMPERATURE, UnitOfTemperature.CELSIUS
    ),
    DatoAuto("velocita_kmh", CONF_VELOCITA, SensorDeviceClass.SPEED, UnitOfSpeed.KILOMETERS_PER_HOUR),
    DatoAuto("potenza_kw", CONF_POTENZA, SensorDeviceClass.POWER, UnitOfPower.KILO_WATT),
    DatoAuto(
        "odometro_km",
        CONF_ODOMETRO,
        SensorDeviceClass.DISTANCE,
        UnitOfLength.KILOMETERS,
        SensorStateClass.TOTAL_INCREASING,
    ),
    DatoAuto("energia_kwh", CONF_ENERGIA_RESIDUA, SensorDeviceClass.ENERGY_STORAGE, UnitOfEnergy.KILO_WATT_HOUR),
    DatoAuto("capacita_kwh", CONF_CAPACITA_BATTERIA, SensorDeviceClass.ENERGY_STORAGE, UnitOfEnergy.KILO_WATT_HOUR),
    DatoAuto("consumo_medio_kwh100", CONF_CONSUMO_MEDIO, None, "kWh/100 km"),
    DatoAuto("potenza_clima_w", CONF_POTENZA_CLIMA, SensorDeviceClass.POWER, UnitOfPower.WATT),
    DatoAuto(
        "temperatura_interna_c", CONF_TEMPERATURA_INTERNA, SensorDeviceClass.TEMPERATURE, UnitOfTemperature.CELSIUS
    ),
)


async def async_setup_entry(
    _hass: HomeAssistant, entry: GdanavConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    hub = entry.runtime_data
    async_add_entities(
        [
            Destinazione(hub, "destinazione"),
            Eta(hub, "eta"),
            SocArrivo(hub, "soc_arrivo"),
            ProssimaSosta(hub, "prossima_sosta"),
            SocNecessario(hub, "soc_necessario"),
            # Solo i dati che l'auto ha davvero: le entità scelte nella configurazione.
            *(SensoreAuto(hub, d) for d in DATI_AUTO if d.conf in hub.entita_auto),
        ]
    )


NESSUN_VIAGGIO = "Nessun viaggio"
NESSUNA_SOSTA = "Nessuna sosta"


class SensoreGdanav(EntitaGdanav):
    _dominio = "sensor"


class Destinazione(SensoreGdanav, SensorEntity):
    @property
    def native_value(self) -> str | None:
        # «Sconosciuto» sembra un guasto: senza viaggio lo si dice.
        return self.hub.viaggio.destinazione if self.hub.viaggio.in_viaggio else NESSUN_VIAGGIO


class Eta(SensoreGdanav, SensorEntity):
    _attr_device_class = SensorDeviceClass.TIMESTAMP

    @property
    def native_value(self) -> datetime | None:
        return self.hub.viaggio.eta if self.hub.viaggio.in_viaggio else None


class SocArrivo(SensoreGdanav, SensorEntity):
    _attr_device_class = SensorDeviceClass.BATTERY
    _attr_native_unit_of_measurement = PERCENTAGE

    @property
    def native_value(self) -> float | None:
        return self.hub.viaggio.batteria_arrivo if self.hub.viaggio.in_viaggio else None


class ProssimaSosta(SensoreGdanav, SensorEntity):
    @property
    def native_value(self) -> str | None:
        sosta = self.hub.viaggio.prossima_sosta
        if not self.hub.viaggio.in_viaggio:
            return NESSUN_VIAGGIO
        return sosta.get("nome") if sosta else NESSUNA_SOSTA

    @property
    def extra_state_attributes(self) -> dict[str, Any] | None:
        sosta = self.hub.viaggio.prossima_sosta
        return {k: v for k, v in sosta.items() if k != "nome"} if sosta else None


class SocNecessario(SensoreGdanav, SensorEntity):
    """La batteria che serve per il prossimo viaggio: la wallbox carica fin lì."""

    _attr_device_class = SensorDeviceClass.BATTERY
    _attr_native_unit_of_measurement = PERCENTAGE
    _attr_state_class = SensorStateClass.MEASUREMENT

    @property
    def native_value(self) -> float | None:
        return self.hub.viaggio.soc_necessario

    @property
    def extra_state_attributes(self) -> dict[str, Any] | None:
        per = self.hub.viaggio.soc_necessario_per
        return {"destinazione": per} if per else None


class SensoreAuto(SensoreGdanav, SensorEntity):
    """Un dato dell'auto **come arriva all'app**: già nell'unità sua (km, kW,
    °C), letto dall'entità scelta nella configurazione. Sulla scheda del
    dispositivo si vede cosa riceve il navigatore, e se un'entità scelta
    male manda un numero storto lo si vede qui, non in auto."""

    def __init__(self, hub: Hub, dato: DatoAuto) -> None:
        super().__init__(hub, "auto_" + dato.conf.removeprefix("entita_"))
        self._dato = dato
        self._attr_device_class = dato.classe
        self._attr_native_unit_of_measurement = dato.unita
        self._attr_state_class = dato.misura

    def _segnale(self) -> str:
        return segnale_auto(self.hub.entry.entry_id)

    @property
    def native_value(self) -> float | None:
        return self.hub.stato_auto().get(self._dato.chiave)
