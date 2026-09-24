"""Il protocollo fra Home Assistant e l'app gdanav.

È lo specchio di ``packages/gdanav_core/lib/src/protocollo``: stesse
derivazioni, stessa busta, stessi nomi. Non importa niente di Home
Assistant, così si prova da solo.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
import hashlib
import hmac
import json
import secrets
from typing import Any
from urllib.parse import parse_qs, urlencode, urlparse

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

TOLLERANZA = timedelta(minutes=5)

MITTENTE_CASA = "casa"
MITTENTE_APP = "app"

# casa → app
STATO_AUTO = "stato_auto"
PIANIFICA_VIAGGIO = "pianifica_viaggio"
COMANDI_DISPONIBILI = "comandi_disponibili"
ESITO_COMANDO = "esito_comando"
# app → casa
VIAGGIO = "viaggio"
EVENTO = "evento"
SOC_NECESSARIO = "soc_necessario"
COMANDO = "comando"
RICHIEDI_STATO = "richiedi_stato"


class ErroreProtocollo(ValueError):
    """Una busta o un QR che non si può accettare."""


def b64(dati: bytes) -> str:
    return base64.urlsafe_b64encode(dati).decode().rstrip("=")


def da_b64(testo: str) -> bytes:
    return base64.urlsafe_b64decode(testo + "=" * (-len(testo) % 4))


@dataclass(frozen=True)
class Abbinamento:
    chiave: bytes
    relay: str
    nome_auto: str = ""

    def __post_init__(self) -> None:
        if len(self.chiave) != 32:
            raise ErroreProtocollo("La chiave deve essere di 32 byte")

    @classmethod
    def nuovo(cls, relay: str, nome_auto: str = "") -> Abbinamento:
        return cls(secrets.token_bytes(32), relay, nome_auto)

    @classmethod
    def da_uri(cls, testo: str) -> Abbinamento:
        uri = urlparse(testo)
        if uri.scheme != "gdanav" or uri.netloc != "abbina":
            raise ErroreProtocollo("Non è un QR di gdanav")
        q = {k: v[0] for k, v in parse_qs(uri.query).items()}
        if q.get("v") != "1":
            raise ErroreProtocollo(f"Versione di abbinamento non supportata: {q.get('v')}")
        if "k" not in q or "r" not in q:
            raise ErroreProtocollo("QR incompleto")
        return cls(da_b64(q["k"]), q["r"], q.get("n", ""))

    @property
    def uri(self) -> str:
        q = {"v": "1", "k": b64(self.chiave), "r": self.relay}
        if self.nome_auto:
            q["n"] = self.nome_auto
        return "gdanav://abbina?" + urlencode(q)

    def _deriva(self, etichetta: str) -> str:
        return b64(hmac.new(self.chiave, etichetta.encode(), hashlib.sha256).digest())

    @property
    def canale(self) -> str:
        return self._deriva("gdanav/canale/v1")[:22]

    @property
    def accesso(self) -> str:
        return self._deriva("gdanav/accesso/v1")

    def indirizzo_relay(self, ruolo: str) -> str:
        base = self.relay if self.relay.endswith("/") else self.relay + "/"
        query = urlencode({"ruolo": ruolo, "accesso": self.accesso})
        return f"{base}v1/canale/{self.canale}?{query}"


@dataclass
class Messaggio:
    tipo: str
    dati: dict[str, Any] = field(default_factory=dict)
    id: str = field(default_factory=lambda: secrets.token_hex(8))
    ts: datetime = field(default_factory=lambda: datetime.now(UTC))

    def to_json(self) -> dict[str, Any]:
        # Stesso formato di Dart: toIso8601String() in UTC finisce con «Z».
        ts = self.ts.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        return {"tipo": self.tipo, "id": self.id, "ts": ts, "dati": self.dati}

    @classmethod
    def da_json(cls, json_: dict[str, Any]) -> Messaggio:
        ts = datetime.fromisoformat(json_["ts"])
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=UTC)
        return cls(json_["tipo"], json_.get("dati") or {}, json_["id"], ts)


class Busta:
    """AES-256-GCM, con il canale e il mittente nei dati associati."""

    def __init__(self, abbinamento: Abbinamento) -> None:
        self._aes = AESGCM(abbinamento.chiave)
        self._canale = abbinamento.canale

    def _aad(self, mittente: str) -> bytes:
        return f"gdanav/v1/{self._canale}/{mittente}".encode()

    def chiudi(self, m: Messaggio, mittente: str, nonce: bytes | None = None) -> str:
        nonce = nonce or secrets.token_bytes(12)
        chiaro = json.dumps(m.to_json(), separators=(",", ":"), ensure_ascii=False).encode()
        cifrato = self._aes.encrypt(nonce, chiaro, self._aad(mittente))
        return json.dumps({"v": 1, "n": b64(nonce), "c": b64(cifrato)})

    def apri(self, testo: str, mittente: str, ora: datetime | None = None) -> Messaggio:
        try:
            busta = json.loads(testo)
            if busta.get("v") != 1:
                raise ErroreProtocollo(f"Versione della busta non supportata: {busta.get('v')}")
            chiaro = self._aes.decrypt(da_b64(busta["n"]), da_b64(busta["c"]), self._aad(mittente))
            m = Messaggio.da_json(json.loads(chiaro))
        except ErroreProtocollo:
            raise
        except Exception as err:  # qualunque rottura è la stessa cosa
            raise ErroreProtocollo("Busta non valida") from err
        if abs((ora or datetime.now(UTC)) - m.ts) > TOLLERANZA:
            raise ErroreProtocollo("Messaggio fuori tempo")
        return m


# Il codice da scrivere a mano al posto del QR: lo specchio di
# ``lib/src/protocollo/codice.dart``.
ALFABETO_CODICE = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
LUNGHEZZA_CODICE = 10
ITERAZIONI_CODICE = 20000
DURATA_CODICE = timedelta(minutes=10)
_AAD_CODICE = b"gdanav/codice/v1"


def nuovo_codice() -> str:
    return "".join(secrets.choice(ALFABETO_CODICE) for _ in range(LUNGHEZZA_CODICE))


def mostra_codice(codice: str) -> str:
    return f"{codice[:5]}-{codice[5:]}"


def deriva_codice(codice: str) -> tuple[bytes, str]:
    """La chiave della busta e il nome sul relay."""
    b = hashlib.pbkdf2_hmac("sha256", codice.encode(), _AAD_CODICE, ITERAZIONI_CODICE, 64)
    return b[:32], b64(hashlib.sha256(b[32:]).digest())[:22]


def chiudi_codice(abbinamento: Abbinamento, codice: str, nonce: bytes | None = None) -> str:
    chiave, _ = deriva_codice(codice)
    nonce = nonce or secrets.token_bytes(12)
    cifrato = AESGCM(chiave).encrypt(nonce, abbinamento.uri.encode(), _AAD_CODICE)
    return json.dumps({"v": 1, "n": b64(nonce), "c": b64(cifrato)})


def indirizzo_codice(relay: str, id_: str) -> str:
    """L'indirizzo http del relay, da quello del WebSocket."""
    if relay.startswith("wss://"):
        relay = "https://" + relay[len("wss://") :]
    elif relay.startswith("ws://"):
        relay = "http://" + relay[len("ws://") :]
    base = relay if relay.endswith("/") else relay + "/"
    return f"{base}v1/codici/{id_}"
