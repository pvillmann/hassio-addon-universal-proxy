"""Sidebar panels for the services of the Universal Reverse Proxy add-on.

Add-ons get exactly one sidebar entry from the Supervisor. This integration
registers one more ingress panel per configured service, with its own title,
icon and admin flag. All panels load the add-on's ingress page, which asks the
frontend for the panel it runs in and jumps to the matching service path.
"""

from __future__ import annotations

from datetime import timedelta
import logging
import re

from aiohasupervisor import SupervisorError

from homeassistant.components import frontend
from homeassistant.components.hassio import get_supervisor_client
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.event import async_track_time_interval

from .const import CONF_ADDON, PANEL_COMPONENT, PANEL_PREFIX, TEMPLATE_DEFAULTS

_LOGGER = logging.getLogger(__name__)

SCAN_INTERVAL = timedelta(minutes=1)


def service_slug(name: str) -> str:
    """Return the service path, derived exactly like the add-on does."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Register a sidebar panel per add-on service and keep them in sync."""
    addon: str = entry.data[CONF_ADDON]
    client = get_supervisor_client(hass)
    registered: dict[str, tuple] = {}

    async def async_sync(_now=None) -> None:
        try:
            info = await client.addons.addon_info(addon)
        except SupervisorError as err:
            _LOGGER.warning("Cannot read options of add-on %s: %s", addon, err)
            return

        wanted: dict[str, tuple] = {}
        for service in info.options.get("services", []):
            slug = service_slug(str(service.get("name", "")))
            if not slug:
                continue
            defaults = TEMPLATE_DEFAULTS.get(service.get("template", "custom"), {})
            wanted[f"{PANEL_PREFIX}{slug}"] = (
                service["name"],
                service.get("icon") or defaults.get("icon") or "mdi:web",
                bool(service.get("admin_only", defaults.get("admin_only", False))),
            )

        for path in set(registered) - set(wanted):
            frontend.async_remove_panel(hass, path, warn_if_unknown=False)
            registered.pop(path)

        for path, panel in wanted.items():
            if registered.get(path) == panel:
                continue
            title, icon, admin = panel
            frontend.async_register_built_in_panel(
                hass,
                PANEL_COMPONENT,
                sidebar_title=title,
                sidebar_icon=icon,
                frontend_url_path=path,
                config={"addon": addon},
                require_admin=admin,
                update=True,
            )
            registered[path] = panel

    @callback
    def async_remove_panels() -> None:
        for path in registered:
            frontend.async_remove_panel(hass, path, warn_if_unknown=False)
        registered.clear()

    await async_sync()
    entry.async_on_unload(async_track_time_interval(hass, async_sync, SCAN_INTERVAL))
    entry.async_on_unload(async_remove_panels)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload: the panels are removed by the registered unload callbacks."""
    return True
