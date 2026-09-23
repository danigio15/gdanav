"""Il protocollo, contro lo stesso vettore che legge la prova Dart."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
import json
from pathlib import Path

import pytest

from custom_components.gdanav import protocollo as p

VETTORE = json.loads((Path(__file__).parents[1] / "docs" / "vettore_prova.json").read_text())
CHIAVE = bytes(range(32))
ORA = datetime(2026, 9, 23, 10, tzinfo=UTC)
A = p.Abbinamento(CHIAVE, "wss://relay.esempio.dev", "Auto di prova")


def test_derivazioni() -> None:
    assert A.canale == VETTORE["canale"]
    assert A.accesso == VETTORE["accesso"]
    assert A.uri == VETTORE["uri"]


def test_uri_andata_e_ritorno() -> None:
    letto = p.Abbinamento.da_uri(A.uri)
    assert letto == A


def test_uri_scritto_da_dart() -> None:
    # Oggi Dart e Python scrivono lo stesso QR; se un giorno cambiano
    # ordine o escape, deve leggerlo lo stesso.
    letto = p.Abbinamento.da_uri(VETTORE["uri_dart"])
    assert letto == A


@pytest.mark.parametrize(
    "testo", ["https://esempio.dev/?k=x", "gdanav://abbina?v=2&k=x&r=y", "gdanav://abbina?v=1&r=y"]
)
def test_uri_rifiutati(testo: str) -> None:
    with pytest.raises(p.ErroreProtocollo):
        p.Abbinamento.da_uri(testo)


def test_indirizzo_relay() -> None:
    assert A.indirizzo_relay("casa") == (
        f"wss://relay.esempio.dev/v1/canale/{VETTORE['canale']}?ruolo=casa&accesso={VETTORE['accesso']}"
    )


def test_busta_uguale_al_vettore() -> None:
    m = p.Messaggio("stato_auto", {"batteria": 72.5, "in_carica": False}, "0123456789abcdef", ORA)
    assert json.loads(p.Busta(A).chiudi(m, p.MITTENTE_CASA, bytes(range(12)))) == json.loads(VETTORE["busta_casa"])


def test_apre_la_busta_di_dart() -> None:
    m = p.Busta(A).apri(VETTORE["busta_app_dart"], p.MITTENTE_APP, ora=ORA)
    assert m.tipo == "viaggio"
    assert m.dati == {"in_viaggio": True, "batteria_arrivo": 31}


def test_mittente_sbagliato() -> None:
    with pytest.raises(p.ErroreProtocollo):
        p.Busta(A).apri(VETTORE["busta_casa"], p.MITTENTE_APP, ora=ORA)


def test_fuori_tempo() -> None:
    with pytest.raises(p.ErroreProtocollo, match="fuori tempo"):
        p.Busta(A).apri(VETTORE["busta_casa"], p.MITTENTE_CASA, ora=ORA + timedelta(minutes=6))


def test_altra_chiave() -> None:
    altra = p.Abbinamento.nuovo("wss://relay.esempio.dev")
    with pytest.raises(p.ErroreProtocollo):
        p.Busta(altra).apri(VETTORE["busta_casa"], p.MITTENTE_CASA, ora=ORA)


@pytest.mark.parametrize("testo", ["non json", '{"v":2}', '{"v":1,"n":"AA","c":"AA"}'])
def test_buste_rotte(testo: str) -> None:
    with pytest.raises(p.ErroreProtocollo):
        p.Busta(A).apri(testo, p.MITTENTE_CASA, ora=ORA)
