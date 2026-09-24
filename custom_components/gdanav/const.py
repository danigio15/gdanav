"""Le costanti di gdanav."""

from __future__ import annotations

DOMAIN = "gdanav"

RELAY_PREDEFINITO = "wss://relay.gdanav.workers.dev"

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
)

# Nelle opzioni: gli script e i pulsanti che l'app può premere.
CONF_COMANDI = "comandi_consentiti"

EVENTO = "gdanav_evento"
EVENTI_APP = ("partenza", "arrivo", "arrivo_vicino", "inizio_ricarica", "fine_ricarica")

SERVIZIO_PIANIFICA = "pianifica_viaggio"


def segnale_aggiornamento(entry_id: str) -> str:
    return f"{DOMAIN}_aggiornamento_{entry_id}"
