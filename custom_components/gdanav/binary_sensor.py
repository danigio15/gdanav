"""In viaggio sì o no, se l'app è collegata, e l'auto come la vede l'app."""

from __future__ import annotations

from homeassistant.components.binary_sensor import BinarySensorDeviceClass, BinarySensorEntity
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import EntityCategory
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from . import GdanavConfigEntry
from .const import CONF_BATTERIA_IN_RISCALDAMENTO, CONF_CLIMA_ACCESO, CONF_IN_CARICA, segnale_auto
from .entita import EntitaGdanav
from .hub import Hub

# (chiave in stato_auto, entità della configurazione, classe)
STATI_AUTO = (
    ("in_carica", CONF_IN_CARICA, BinarySensorDeviceClass.BATTERY_CHARGING),
    ("clima_acceso", CONF_CLIMA_ACCESO, BinarySensorDeviceClass.RUNNING),
    ("batteria_in_riscaldamento", CONF_BATTERIA_IN_RISCALDAMENTO, BinarySensorDeviceClass.HEAT),
)


async def async_setup_entry(
    _hass: HomeAssistant, entry: GdanavConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    hub = entry.runtime_data
    async_add_entities(
        [
            InViaggio(hub, "in_viaggio"),
            AppCollegata(hub, "app_collegata"),
            *(StatoAuto(hub, chiave, conf, classe) for chiave, conf, classe in STATI_AUTO if conf in hub.entita_auto),
        ]
    )


class BinarioGdanav(EntitaGdanav):
    _dominio = "binary_sensor"


class InViaggio(BinarioGdanav, BinarySensorEntity):
    # Niente «si muove / non si muove»: gli stati hanno i loro nomi.

    @property
    def is_on(self) -> bool:
        return self.hub.viaggio.in_viaggio


class AppCollegata(BinarioGdanav, BinarySensorEntity):
    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    @property
    def is_on(self) -> bool:
        return self.hub.viaggio.app_collegata


class StatoAuto(BinarioGdanav, BinarySensorEntity):
    """Un sì/no dell'auto come arriva all'app, dall'entità scelta nella configurazione."""

    def __init__(self, hub: Hub, chiave: str, conf: str, classe: BinarySensorDeviceClass) -> None:
        super().__init__(hub, "auto_" + conf.removeprefix("entita_"))
        self._chiave = chiave
        self._attr_device_class = classe

    def _segnale(self) -> str:
        return segnale_auto(self.hub.entry.entry_id)

    @property
    def is_on(self) -> bool | None:
        return self.hub.stato_auto().get(self._chiave)
