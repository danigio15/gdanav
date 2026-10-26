"""Le costanti di GdANav."""

from __future__ import annotations

DOMAIN = "gdanav"

# Il relay di GdANav su Cloudflare (vedi relay/ e la CI che lo pubblica).
RELAY_PREDEFINITO = "wss://gdanav.gdahome.org"

CONF_CHIAVE = "chiave"
CONF_RELAY = "relay"
CONF_NOME_AUTO = "nome_auto"
CONF_DISPOSITIVO = "dispositivo"

# Le entità dell'auto, scelte dall'utente fra quelle che ha già.
CONF_BATTERIA = "entita_batteria"
CONF_AUTONOMIA = "entita_autonomia"
CONF_IN_CARICA = "entita_in_carica"
CONF_POTENZA_CARICA = "entita_potenza_carica"
CONF_TEMPERATURA_BATTERIA = "entita_temperatura_batteria"
CONF_POSIZIONE = "entita_posizione"
# Per il consumo in tempo reale, come ABRP: più l'app sa, meglio calcola.
CONF_TEMPERATURA_ESTERNA = "entita_temperatura_esterna"
CONF_VELOCITA = "entita_velocita"
CONF_POTENZA = "entita_potenza"
CONF_ODOMETRO = "entita_odometro"
# Per contare in kWh veri e col clima misurato (vedi docs/DATI-AUTO.md di GdAAuto).
CONF_ENERGIA_RESIDUA = "entita_energia_residua"
CONF_CAPACITA_BATTERIA = "entita_capacita_batteria"
CONF_CONSUMO_MEDIO = "entita_consumo_medio"
CONF_POTENZA_CLIMA = "entita_potenza_clima"
CONF_CLIMA_ACCESO = "entita_clima_acceso"
CONF_BATTERIA_IN_RISCALDAMENTO = "entita_batteria_in_riscaldamento"
CONF_TEMPERATURA_INTERNA = "entita_temperatura_interna"

ENTITA_AUTO = (
    CONF_BATTERIA,
    CONF_AUTONOMIA,
    CONF_IN_CARICA,
    CONF_POTENZA_CARICA,
    CONF_TEMPERATURA_BATTERIA,
    CONF_POSIZIONE,
    CONF_TEMPERATURA_ESTERNA,
    CONF_VELOCITA,
    CONF_POTENZA,
    CONF_ODOMETRO,
    CONF_ENERGIA_RESIDUA,
    CONF_CAPACITA_BATTERIA,
    CONF_CONSUMO_MEDIO,
    CONF_POTENZA_CLIMA,
    CONF_CLIMA_ACCESO,
    CONF_BATTERIA_IN_RISCALDAMENTO,
    CONF_TEMPERATURA_INTERNA,
)

# Nelle opzioni: gli script e i pulsanti che l'app può premere.
CONF_COMANDI = "comandi_consentiti"

EVENTO = "gdanav_evento"
EVENTI_APP = ("partenza", "arrivo", "arrivo_vicino", "inizio_ricarica", "fine_ricarica")

SERVIZIO_PIANIFICA = "pianifica_viaggio"


def segnale_aggiornamento(entry_id: str) -> str:
    return f"{DOMAIN}_aggiornamento_{entry_id}"


def segnale_auto(entry_id: str) -> str:
    """L'auto è cambiata: per i sensori che la mostrano come la vede l'app."""
    return f"{DOMAIN}_auto_{entry_id}"
