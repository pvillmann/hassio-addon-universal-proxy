"""Config flow for Universal Proxy: finds the add-on, nothing to enter."""

from __future__ import annotations

from typing import Any

from aiohasupervisor import SupervisorError

from homeassistant.components.hassio import get_supervisor_client
from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.helpers.hassio import is_hassio

from .const import ADDON_SLUG_SUFFIX, CONF_ADDON, DOMAIN


class UniversalProxyConfigFlow(ConfigFlow, domain=DOMAIN):
    """Set up the sidebar panels for the Universal Reverse Proxy add-on."""

    VERSION = 1

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Find the installed add-on and create the entry."""
        if not is_hassio(self.hass):
            return self.async_abort(reason="not_hassio")

        try:
            addons = await get_supervisor_client(self.hass).addons.list()
        except SupervisorError:
            return self.async_abort(reason="cannot_connect")

        slug = next(
            (a.slug for a in addons if a.slug.endswith(ADDON_SLUG_SUFFIX)), None
        )
        if slug is None:
            return self.async_abort(reason="addon_not_installed")

        await self.async_set_unique_id(slug)
        self._abort_if_unique_id_configured()
        return self.async_create_entry(
            title="Universal Proxy", data={CONF_ADDON: slug}
        )
