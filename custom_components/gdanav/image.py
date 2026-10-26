"""Il QR da inquadrare con l'app. Contiene la chiave: chi lo vede entra.

Quando c'è un codice da scrivere a mano, sta scritto sotto il QR, nella
stessa immagine: chi apre il QR vede tutte e due le strade.
"""

from __future__ import annotations

from datetime import datetime
from html import escape

from homeassistant.components.image import ImageEntity
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.entity import EntityCategory
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import dt as dt_util
import segno

from . import GdanavConfigEntry, protocollo as p
from .entita import EntitaGdanav
from .hub import Hub


async def async_setup_entry(
    hass: HomeAssistant, entry: GdanavConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    async_add_entities([QrAbbinamento(hass, entry.runtime_data)])


def qr_svg(testo: str, codice: str | None = None, scade: datetime | None = None) -> bytes:
    """Il QR, e sotto il codice da scrivere a mano finché vale."""
    qr = segno.make(testo, error="m")
    scala, bordo = 8, 2
    lato = (qr.symbol_size()[0] + 2 * bordo) * scala
    dentro = qr.svg_inline(scale=scala, border=bordo, dark="#000", light="#fff")
    righe = ""
    altezza = lato
    if codice:
        altezza = lato + 125
        testo = f'text-anchor="middle" x="{lato / 2}"'
        righe = (
            f'<text {testo} y="{lato + 22}" font-family="sans-serif" font-size="20" fill="#444">'
            "Oppure scrivi nell'app il codice</text>"
            f'<text {testo} y="{lato + 72}" font-family="monospace" font-size="46" font-weight="bold" fill="#000">'
            f"{escape(p.mostra_codice(codice))}</text>"
        )
        if scade:
            ore = f"{dt_util.as_local(scade):%H:%M}"
            righe += (
                f'<text {testo} y="{lato + 108}" font-family="sans-serif" font-size="18" fill="#444">'
                f"Vale fino alle {ore}</text>"
            )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{lato}" height="{altezza}" viewBox="0 0 {lato} {altezza}">'
        f'<rect width="{lato}" height="{altezza}" fill="#fff"/>{dentro}{righe}</svg>'
    ).encode()


class QrAbbinamento(EntitaGdanav, ImageEntity):
    _dominio = "image"
    _attr_content_type = "image/svg+xml"
    _attr_entity_category = EntityCategory.CONFIG

    def __init__(self, hass: HomeAssistant, hub: Hub) -> None:
        EntitaGdanav.__init__(self, hub, "abbinamento")
        ImageEntity.__init__(self, hass)
        self._attr_image_last_updated = dt_util.utcnow()
        self._col_codice: str | None = None

    @callback
    def _cambiata(self) -> None:
        # Un codice nuovo, o scaduto: l'immagine è un'altra, e la scheda lo
        # sa dalla data dell'immagine.
        if self.hub.codice != self._col_codice:
            self._col_codice = self.hub.codice
            self._attr_image_last_updated = dt_util.utcnow()
        self.async_write_ha_state()

    async def async_image(self) -> bytes:
        return qr_svg(self.hub.abbinamento.uri, self.hub.codice, self.hub.codice_scade)
