# Il protocollo fra l'app e Home Assistant

Versione 1. Implementato due volte, uguale:
[`gdanav_core/lib/src/protocollo`](../packages/gdanav_core/lib/src/protocollo)
(Dart) e [`custom_components/gdanav/protocollo.py`](../custom_components/gdanav/protocollo.py)
(Python). Il file [`vettore_prova.json`](vettore_prova.json) lo leggono le
prove di entrambi: se una parte cambia da sola, una prova diventa rossa.

## Abbinamento

Home Assistant genera 32 byte casuali (la **chiave**) e mostra il QR:

    gdanav://abbina?v=1&k=<chiave>&r=<relay>&n=<nome auto>

Tutti i byte viaggiano in base64 per URL senza `=`. Dalla chiave si ricava:

| | Come | Chi lo vede |
| --- | --- | --- |
| canale | primi 22 caratteri di `HMAC-SHA256(chiave, "gdanav/canale/v1")` | relay |
| accesso | `HMAC-SHA256(chiave, "gdanav/accesso/v1")` | relay, che ne tiene solo lo SHA-256 |

La chiave non esce mai dal telefono e da Home Assistant.

## Relay

    wss://<relay>/v1/canale/<canale>?ruolo=casa|app&accesso=<accesso>

- La **prima casa** che entra crea la stanza e fissa l'impronta dell'accesso.
  Da lì entra solo chi ha lo stesso accesso.
- Un'**app** non crea stanze: se la casa non è mai passata riceve 404.
- Una casa per stanza (la nuova sostituisce la vecchia), fino a 4 app.
- Messaggi fino a 64 KiB.
- Il relay manda in chiaro solo la presenza dell'altra parte:
  `{"relay":"presente"|"assente","ruolo":"casa"|"app"}`.

## Busta

Ogni messaggio viaggia chiuso con AES-256-GCM:

    {"v":1,"n":"<nonce di 12 byte>","c":"<cifrato + tag di 16 byte>"}

I dati associati sono `gdanav/v1/<canale>/<mittente>`, con mittente `casa` o
`app`: una busta dell'app rispedita all'app non si apre. Dentro:

    {"tipo":"...","id":"<16 esadecimali>","ts":"<ISO 8601 UTC>","dati":{...}}

Si scarta un messaggio con `ts` a più di 5 minuti dall'orologio di chi lo
riceve.

## Messaggi

### Casa → app

| tipo | dati |
| --- | --- |
| `stato_auto` | `batteria` (0–100), `letto` (ISO), e se ci sono `autonomia_km`, `in_carica`, `potenza_carica_kw`, `temperatura_batteria_c`, `latitudine`, `longitudine`. Senza `batteria` l'app lo ignora |
| `comandi_disponibili` | `comandi`: `[{id, nome}]` |
| `esito_comando` | `richiesta` (id del comando), `ok`, `errore` |
| `pianifica_viaggio` | `destinazione`, e se ci sono `latitudine`, `longitudine`, `partenza` (ISO) |

La casa manda `stato_auto` e `comandi_disponibili` quando l'app entra, quando
l'app li chiede e, per lo stato, 2 secondi dopo che le entità dell'auto
cambiano.

### App → casa

| tipo | dati | In Home Assistant |
| --- | --- | --- |
| `richiedi_stato` | — | risponde con stato e comandi |
| `viaggio` | `in_viaggio`, `destinazione: {nome, lat, lon}`, `eta` (ISO), `batteria_arrivo`, `prossima_sosta: {nome, …}` | i sensori del viaggio |
| `soc_necessario` | `batteria`, `destinazione` | `sensor.gdanav_soc_necessario` |
| `evento` | `evento`: `partenza`, `arrivo`, `arrivo_vicino`, `inizio_ricarica`, `fine_ricarica`, più quello che serve | `gdanav_evento` sul bus |
| `comando` | `comando`: l'entity_id | eseguito solo se è nella lista delle opzioni |
