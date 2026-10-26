"""Il pulsante per il codice da scrivere nell'app, quando il QR non si può inquadrare."""

from __future__ import annotations

from homeassistant.components.button import ButtonEntity
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from . import GdanavConfigEntry
from .entita import EntitaGdanav


async def async_setup_entry(
    _hass: HomeAssistant, entry: GdanavConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    async_add_entities([NuovoCodice(entry.runtime_data, "nuovo_codice")])


class NuovoCodice(EntitaGdanav, ButtonEntity):
    """«Abbina un telefono»: nella sezione «Configurazione» della scheda del
    dispositivo, e sotto di lui il codice e il QR. Si chiama così anche
    perché venga prima degli altri due: la scheda li mette in ordine di nome."""

    _dominio = "button"
    _attr_icon = "mdi:cellphone-link"
    _attr_entity_category = EntityCategory.CONFIG

    async def async_press(self) -> None:
        await self.hub.async_nuovo_codice()
