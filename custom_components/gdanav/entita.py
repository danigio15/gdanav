"""Quello che hanno in comune tutte le entità di gdanav."""

from __future__ import annotations

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.entity import Entity

from .const import DOMAIN, segnale_aggiornamento
from .hub import Hub


class EntitaGdanav(Entity):
    _attr_has_entity_name = True
    _attr_should_poll = False

    #: sensor, binary_sensor, image: lo dice ogni piattaforma.
    _dominio: str

    def __init__(self, hub: Hub, chiave: str) -> None:
        self.hub = hub
        # sensor.gdanav_eta in qualunque lingua sia Home Assistant, e senza il
        # nome dell'auto davanti. Con due auto la seconda prende «_2».
        self.entity_id = f"{self._dominio}.gdanav_{chiave}"
        self._attr_translation_key = chiave
        self._attr_unique_id = f"{hub.entry.unique_id}_{chiave}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, hub.entry.unique_id or hub.entry.entry_id)},
            name=f"gdanav {hub.entry.title}",
            manufacturer="gdanav",
            model="Navigatore EV",
        )

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(
            async_dispatcher_connect(
                self.hass, segnale_aggiornamento(self.hub.entry.entry_id), self.async_write_ha_state
            )
        )
