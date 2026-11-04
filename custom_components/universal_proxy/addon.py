"""Talking to the Universal Reverse Proxy add-on."""

from __future__ import annotations

import re
from typing import Any

import aiohttp

from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession


def service_slug(name: str) -> str:
    """Return the service path, derived exactly like the add-on does."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


async def async_fetch_addon_json(hass: HomeAssistant, info: Any, path: str) -> Any:
    """Read one of the add-on's info files (/_services.json, /_catalog.json).

    The add-on serves them to Home Assistant Core only. Returns None when the
    add-on is not running or too old.
    """
    if getattr(info, "state", None) != "started":
        return None
    host = getattr(info, "ip_address", None) or getattr(info, "hostname", None)
    port = getattr(info, "ingress_port", None) or 8099
    if not host:
        return None
    try:
        async with async_get_clientsession(hass).get(
            f"http://{host}:{port}/{path}",
            timeout=aiohttp.ClientTimeout(total=5),
        ) as resp:
            if resp.status != 200:
                return None
            data = await resp.json(content_type=None)
    except (aiohttp.ClientError, TimeoutError, ValueError):
        return None
    if not isinstance(data, list) or not all(isinstance(i, dict) for i in data):
        return None
    return data
