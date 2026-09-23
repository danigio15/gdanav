"""Le prove girano dentro un Home Assistant vero, finto solo nel relay."""

from __future__ import annotations

from collections.abc import Generator
from unittest.mock import patch

import pytest


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations: None) -> None:
    """Senza questo Home Assistant ignora custom_components."""


@pytest.fixture
def senza_relay() -> Generator[None]:
    """Il filo col relay non parte: i messaggi si passano a mano."""

    async def niente(_self) -> None:
        return None

    with patch("custom_components.gdanav.hub.Hub._ciclo", niente):
        yield
