"""gdanav: il navigatore per auto elettriche, collegato a Home Assistant."""

from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.typing import ConfigType
import voluptuous as vol

from . import protocollo as p
from .const import DOMAIN, SERVIZIO_PIANIFICA
from .hub import Hub

PIATTAFORME = [Platform.BINARY_SENSOR, Platform.IMAGE, Platform.SENSOR]

type GdanavConfigEntry = ConfigEntry[Hub]

CONFIG_SCHEMA = cv.config_entry_only_config_schema(DOMAIN)

SCHEMA_PIANIFICA = vol.Schema(
    {
        vol.Optional("config_entry_id"): cv.string,
        vol.Required("destinazione"): cv.string,
        vol.Optional("latitudine"): cv.latitude,
        vol.Optional("longitudine"): cv.longitude,
        vol.Optional("partenza"): cv.datetime,
    }
)


async def async_setup(hass: HomeAssistant, _config: ConfigType) -> bool:
    async def pianifica(call: ServiceCall) -> None:
        voci = [
            e
            for e in hass.config_entries.async_loaded_entries(DOMAIN)
            if call.data.get("config_entry_id") in (None, e.entry_id)
        ]
        if not voci:
            raise HomeAssistantError("Nessuna auto gdanav configurata")
        dati = {k: v for k, v in call.data.items() if k != "config_entry_id"}
        if "partenza" in dati:
            dati["partenza"] = dati["partenza"].isoformat()
        consegnati = [await e.runtime_data.async_manda(p.PIANIFICA_VIAGGIO, dati) for e in voci]
        if not any(consegnati):
            raise HomeAssistantError("L'app non è collegata: il viaggio non è stato consegnato")

    hass.services.async_register(DOMAIN, SERVIZIO_PIANIFICA, pianifica, schema=SCHEMA_PIANIFICA)
    return True


async def async_setup_entry(hass: HomeAssistant, entry: GdanavConfigEntry) -> bool:
    hub = Hub(hass, entry)
    entry.runtime_data = hub
    await hass.config_entries.async_forward_entry_setups(entry, PIATTAFORME)
    await hub.async_avvia()
    entry.async_on_unload(entry.add_update_listener(_opzioni_cambiate))
    return True


async def async_unload_entry(hass: HomeAssistant, entry: GdanavConfigEntry) -> bool:
    await entry.runtime_data.async_ferma()
    return await hass.config_entries.async_unload_platforms(entry, PIATTAFORME)


async def _opzioni_cambiate(hass: HomeAssistant, entry: GdanavConfigEntry) -> None:
    await hass.config_entries.async_reload(entry.entry_id)
