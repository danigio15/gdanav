"""I sensori del viaggio, riempiti dall'app."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity, SensorStateClass
from homeassistant.const import PERCENTAGE
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from . import GdanavConfigEntry
from .entita import EntitaGdanav


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
        ]
    )


class SensoreGdanav(EntitaGdanav):
    _dominio = "sensor"


class Destinazione(SensoreGdanav, SensorEntity):
    @property
    def native_value(self) -> str | None:
        return self.hub.viaggio.destinazione if self.hub.viaggio.in_viaggio else None


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
        return sosta.get("nome") if sosta and self.hub.viaggio.in_viaggio else None

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
