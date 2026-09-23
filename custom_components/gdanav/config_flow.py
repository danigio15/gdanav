"""La configurazione: nome dell'auto, le sue entità, e il QR per l'app."""

from __future__ import annotations

from typing import Any

from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.core import callback
from homeassistant.helpers import selector
import voluptuous as vol

from . import protocollo as p
from .const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_CHIAVE,
    CONF_COMANDI,
    CONF_IN_CARICA,
    CONF_NOME_AUTO,
    CONF_POSIZIONE,
    CONF_POTENZA_CARICA,
    CONF_RELAY,
    CONF_TEMPERATURA_BATTERIA,
    DOMAIN,
    RELAY_PREDEFINITO,
)


def _entita(*domini: str, device_class: str | None = None) -> selector.EntitySelector:
    config = selector.EntitySelectorConfig(domain=list(domini))
    if device_class:
        config = selector.EntitySelectorConfig(domain=list(domini), device_class=device_class)
    return selector.EntitySelector(config)


SCHEMA = vol.Schema(
    {
        vol.Required(CONF_NOME_AUTO): selector.TextSelector(),
        vol.Required(CONF_BATTERIA): _entita("sensor", device_class="battery"),
        vol.Optional(CONF_AUTONOMIA): _entita("sensor"),
        vol.Optional(CONF_IN_CARICA): _entita("binary_sensor", "switch", "sensor"),
        vol.Optional(CONF_POTENZA_CARICA): _entita("sensor", device_class="power"),
        vol.Optional(CONF_TEMPERATURA_BATTERIA): _entita("sensor", device_class="temperature"),
        vol.Optional(CONF_POSIZIONE): _entita("device_tracker"),
        vol.Required(CONF_RELAY, default=RELAY_PREDEFINITO): selector.TextSelector(
            selector.TextSelectorConfig(type=selector.TextSelectorType.URL)
        ),
    }
)


class GdanavConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errori: dict[str, str] = {}
        if user_input is not None:
            relay = user_input[CONF_RELAY].strip()
            if not relay.startswith(("wss://", "ws://")):
                errori[CONF_RELAY] = "relay_non_valido"
            else:
                # La chiave nasce qui e resta qui: nel QR, e nella voce.
                abbinamento = p.Abbinamento.nuovo(relay, user_input[CONF_NOME_AUTO])
                await self.async_set_unique_id(abbinamento.canale)
                self._abort_if_unique_id_configured()
                return self.async_create_entry(
                    title=user_input[CONF_NOME_AUTO],
                    data={**user_input, CONF_RELAY: relay, CONF_CHIAVE: p.b64(abbinamento.chiave)},
                )
        return self.async_show_form(
            step_id="user", data_schema=self.add_suggested_values_to_schema(SCHEMA, user_input), errors=errori
        )

    @staticmethod
    @callback
    def async_get_options_flow(_entry: ConfigEntry) -> OptionsFlow:
        return GdanavOptionsFlow()


class GdanavOptionsFlow(OptionsFlow):
    """Quali script, pulsanti e scene l'app può avviare. Nient'altro."""

    async def async_step_init(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            return self.async_create_entry(data=user_input)
        schema = vol.Schema(
            {
                vol.Optional(CONF_COMANDI, default=[]): selector.EntitySelector(
                    selector.EntitySelectorConfig(domain=["script", "button", "scene"], multiple=True)
                )
            }
        )
        return self.async_show_form(
            step_id="init", data_schema=self.add_suggested_values_to_schema(schema, self.config_entry.options)
        )
