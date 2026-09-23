"""Home Assistant e un'app finta, attraverso un relay vero.

Gira solo se c'è un relay acceso in locale:

    cd relay && npx wrangler dev --port 8799
    GDANAV_RELAY=ws://127.0.0.1:8799 pytest tests/test_relay_vero.py
"""

from __future__ import annotations

import asyncio
import os

import aiohttp
from homeassistant.core import HomeAssistant
import pytest
from pytest_homeassistant_custom_component.common import MockConfigEntry

from custom_components.gdanav import protocollo as p
from custom_components.gdanav.const import CONF_BATTERIA, CONF_CHIAVE, CONF_NOME_AUTO, CONF_RELAY, DOMAIN

RELAY = os.environ.get("GDANAV_RELAY")
pytestmark = pytest.mark.skipif(not RELAY, reason="serve GDANAV_RELAY con un relay acceso")


async def _aspetta(condizione, secondi: float = 10) -> None:
    async with asyncio.timeout(secondi):
        while not condizione():
            await asyncio.sleep(0.05)


@pytest.mark.allow_hosts(["127.0.0.1"])
async def test_andata_e_ritorno(hass: HomeAssistant, socket_enabled: None) -> None:
    abbinamento = p.Abbinamento.nuovo(RELAY, "Prova")
    busta = p.Busta(abbinamento)
    hass.states.async_set("sensor.auto_batteria", "58", {"device_class": "battery"})
    voce = MockConfigEntry(
        domain=DOMAIN,
        title="Prova",
        unique_id=abbinamento.canale,
        data={
            CONF_NOME_AUTO: "Prova",
            CONF_RELAY: RELAY,
            CONF_CHIAVE: p.b64(abbinamento.chiave),
            CONF_BATTERIA: "sensor.auto_batteria",
        },
    )
    voce.add_to_hass(hass)
    assert await hass.config_entries.async_setup(voce.entry_id)
    hub = voce.runtime_data
    await _aspetta(lambda: hub._ws is not None)

    async with aiohttp.ClientSession() as s, s.ws_connect(abbinamento.indirizzo_relay("app")) as app:
        ricevuti: list[p.Messaggio] = []

        async def ascolta() -> None:
            async for msg in app:
                if '"relay"' not in msg.data:
                    ricevuti.append(busta.apri(msg.data, p.MITTENTE_CASA))

        ascolto = asyncio.create_task(ascolta())
        # Appena l'app entra, la casa le manda stato e comandi.
        await _aspetta(lambda: any(m.tipo == p.STATO_AUTO for m in ricevuti))
        assert next(m for m in ricevuti if m.tipo == p.STATO_AUTO).dati["batteria"] == 58
        await _aspetta(lambda: hass.states.get("binary_sensor.gdanav_app_collegata").state == "on")

        await app.send_str(
            busta.chiudi(
                p.Messaggio(p.VIAGGIO, {"in_viaggio": True, "destinazione": {"nome": "Parma"}}), p.MITTENTE_APP
            )
        )
        await _aspetta(lambda: hass.states.get("sensor.gdanav_destinazione").state == "Parma")
        ascolto.cancel()

    await _aspetta(lambda: hass.states.get("binary_sensor.gdanav_app_collegata").state == "off")
    assert await hass.config_entries.async_unload(voce.entry_id)
