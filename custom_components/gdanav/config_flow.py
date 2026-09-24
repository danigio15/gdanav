"""La configurazione: l'auto (il suo dispositivo), le sue entità, e il QR per l'app."""

from __future__ import annotations

from typing import Any

from homeassistant.config_entries import ConfigEntry, ConfigFlow, ConfigFlowResult, OptionsFlow
from homeassistant.core import callback
from homeassistant.helpers import device_registry as dr, entity_registry as er, selector
import voluptuous as vol

from . import protocollo as p
from .const import (
    CONF_AUTONOMIA,
    CONF_BATTERIA,
    CONF_CHIAVE,
    CONF_COMANDI,
    CONF_DISPOSITIVO,
    CONF_IN_CARICA,
    CONF_NOME_AUTO,
    CONF_ODOMETRO,
    CONF_POSIZIONE,
    CONF_POTENZA,
    CONF_POTENZA_CARICA,
    CONF_RELAY,
    CONF_TEMPERATURA_BATTERIA,
    CONF_TEMPERATURA_ESTERNA,
    CONF_VELOCITA,
    DOMAIN,
    RELAY_PREDEFINITO,
)
from .riconosci import Entita, proponi


def _entita(*domini: str, device_class: str | None = None) -> selector.EntitySelector:
    config = selector.EntitySelectorConfig(domain=list(domini))
    if device_class:
        config = selector.EntitySelectorConfig(domain=list(domini), device_class=device_class)
    return selector.EntitySelector(config)


SCHEMA = vol.Schema(
    {
        vol.Required(CONF_NOME_AUTO): selector.TextSelector(),
        # Senza filtri sulla classe: non tutte le integrazioni la dichiarano.
        vol.Required(CONF_BATTERIA): _entita("sensor"),
        vol.Optional(CONF_AUTONOMIA): _entita("sensor"),
        vol.Optional(CONF_IN_CARICA): _entita("binary_sensor", "switch", "sensor"),
        vol.Optional(CONF_POTENZA_CARICA): _entita("sensor"),
        vol.Optional(CONF_TEMPERATURA_BATTERIA): _entita("sensor"),
        vol.Optional(CONF_POSIZIONE): _entita("device_tracker"),
        vol.Optional(CONF_TEMPERATURA_ESTERNA): _entita("sensor"),
        vol.Optional(CONF_VELOCITA): _entita("sensor"),
        vol.Optional(CONF_POTENZA): _entita("sensor"),
        vol.Optional(CONF_ODOMETRO): _entita("sensor"),
        vol.Required(CONF_RELAY, default=RELAY_PREDEFINITO): selector.TextSelector(
            selector.TextSelectorConfig(type=selector.TextSelectorType.URL)
        ),
    }
)


class GdanavConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    def __init__(self) -> None:
        self._proposta: dict[str, Any] = {}

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Primo passo: il dispositivo dell'auto, se c'è. Le entità si propongono da sole."""
        if user_input is not None:
            self._proposta = {}
            if dispositivo := user_input.get(CONF_DISPOSITIVO):
                self._proposta = self._dal_dispositivo(dispositivo)
            return await self.async_step_entita()
        schema = vol.Schema(
            {
                vol.Optional(CONF_DISPOSITIVO): selector.DeviceSelector(selector.DeviceSelectorConfig()),
            }
        )
        return self.async_show_form(step_id="user", data_schema=schema)

    def _dal_dispositivo(self, device_id: str) -> dict[str, Any]:
        registro = er.async_get(self.hass)
        entita = []
        for voce in er.async_entries_for_device(registro, device_id):
            stato = self.hass.states.get(voce.entity_id)
            attributi = stato.attributes if stato else {}
            entita.append(
                Entita(
                    voce.entity_id,
                    nome=voce.name or voce.original_name or (stato.name if stato else ""),
                    unita=attributi.get("unit_of_measurement") or voce.unit_of_measurement,
                    classe=attributi.get("device_class") or voce.device_class or voce.original_device_class,
                )
            )
        proposta: dict[str, Any] = dict(proponi(entita))
        if (d := dr.async_get(self.hass).async_get(device_id)) is not None:
            proposta[CONF_NOME_AUTO] = d.name_by_user or d.name or ""
        return proposta

    async def async_step_entita(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Secondo passo: le entità, già riempite se si è scelto il dispositivo."""
        errori: dict[str, str] = {}
        if user_input is not None and CONF_BATTERIA in user_input:
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
            step_id="entita",
            data_schema=self.add_suggested_values_to_schema(SCHEMA, user_input or self._proposta),
            errors=errori,
            description_placeholders={"trovate": str(len([k for k in self._proposta if k != CONF_NOME_AUTO]))},
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
