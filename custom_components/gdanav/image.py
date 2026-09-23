"""Il QR da inquadrare con l'app. Contiene la chiave: chi lo vede entra."""

from __future__ import annotations

import io

from homeassistant.components.image import ImageEntity
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import EntityCategory
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util
import segno

from . import GdanavConfigEntry
from .entita import EntitaGdanav
from .hub import Hub


async def async_setup_entry(
    hass: HomeAssistant, entry: GdanavConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    async_add_entities([QrAbbinamento(hass, entry.runtime_data)])


def qr_svg(testo: str) -> bytes:
    buffer = io.BytesIO()
    segno.make(testo, error="m").save(buffer, kind="svg", scale=8, border=2, dark="#000", light="#fff")
    return buffer.getvalue()


class QrAbbinamento(EntitaGdanav, ImageEntity):
    _dominio = "image"
    _attr_content_type = "image/svg+xml"
    _attr_entity_category = EntityCategory.CONFIG

    def __init__(self, hass: HomeAssistant, hub: Hub) -> None:
        EntitaGdanav.__init__(self, hub, "abbinamento")
        ImageEntity.__init__(self, hass)
        self._attr_image_last_updated = dt_util.utcnow()

    async def async_image(self) -> bytes:
        return qr_svg(self.hub.abbinamento.uri)
