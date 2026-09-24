"""Il pulsante per il codice da scrivere nell'app, quando il QR non si può inquadrare."""

from __future__ import annotations

from homeassistant.components.button import ButtonEntity
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from . import GdanavConfigEntry
from .entita import EntitaGdanav


async def async_setup_entry(
    _hass: HomeAssistant, entry: GdanavConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    async_add_entities([NuovoCodice(entry.runtime_data, "nuovo_codice")])


class NuovoCodice(EntitaGdanav, ButtonEntity):
    _dominio = "button"
    _attr_icon = "mdi:form-textbox-password"

    async def async_press(self) -> None:
        await self.hub.async_nuovo_codice()
