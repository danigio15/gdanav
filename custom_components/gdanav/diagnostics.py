"""La diagnostica: com'è messo il filo col relay, cosa vede l'app, senza la chiave.

Impostazioni → Dispositivi e servizi → GdANav → ⋮ → Scarica diagnostica. È
quello che si allega a una segnalazione: dice se la casa è collegata al
relay, se l'app c'è, quante buste sono passate e quante buttate, e cosa
l'app riceve dell'auto. La chiave dell'abbinamento non c'è: chi ce l'ha
legge l'auto.
"""

from __future__ import annotations

from dataclasses import asdict
from datetime import datetime
from typing import Any

from homeassistant.components.diagnostics import async_redact_data
from homeassistant.core import HomeAssistant

from . import GdanavConfigEntry
from .const import CONF_CHIAVE

DA_NASCONDERE = {CONF_CHIAVE}


def _piano(valore: Any) -> Any:
    return valore.isoformat() if isinstance(valore, datetime) else valore


async def async_get_config_entry_diagnostics(_hass: HomeAssistant, entry: GdanavConfigEntry) -> dict[str, Any]:
    hub = entry.runtime_data
    return {
        "voce": {
            "titolo": entry.title,
            "dati": async_redact_data(dict(entry.data), DA_NASCONDERE),
            "opzioni": dict(entry.options),
        },
        "relay": {
            "collegato": hub.collegato,
            "collegato_da": _piano(hub.collegato_da),
            "tentativi": hub.tentativi,
            "ultimo_errore": hub.ultimo_errore,
            "app_collegata": hub.viaggio.app_collegata,
            "inviati": hub.inviati,
            "ricevuti": hub.ricevuti,
            "scartati": hub.scartati,
            "codice_in_corso": hub.codice is not None,
        },
        "stato_auto": hub.stato_auto(),
        "viaggio": {k: _piano(v) for k, v in asdict(hub.viaggio).items()},
    }
