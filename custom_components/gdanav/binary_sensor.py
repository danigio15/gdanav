"""In viaggio sì o no, e se l'app è collegata."""

from __future__ import annotations

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import EntityCategory
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from . import GdanavConfigEntry
from .entita import EntitaGdanav


async def async_setup_entry(
    _hass: HomeAssistant, entry: GdanavConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    hub = entry.runtime_data
    async_add_entities([InViaggio(hub, "in_viaggio"), AppCollegata(hub, "app_collegata")])


class BinarioGdanav(EntitaGdanav):
    _dominio = "binary_sensor"


class InViaggio(BinarioGdanav, BinarySensorEntity):
    _attr_device_class = BinarySensorDeviceClass.MOVING

    @property
    def is_on(self) -> bool:
        return self.hub.viaggio.in_viaggio


class AppCollegata(BinarioGdanav, BinarySensorEntity):
    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    @property
    def is_on(self) -> bool:
        return self.hub.viaggio.app_collegata
