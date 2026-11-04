"""Config flow for Universal Proxy.

Setup finds the add-on, nothing to enter. The options flow ("Configure") adds,
edits and removes services: pick a template from the add-on's catalog, then
fill in only the fields that template needs. The result is written to the
add-on's options and the add-on is restarted.
"""

from __future__ import annotations

import asyncio
import re
from typing import Any

from aiohasupervisor import SupervisorError
from aiohasupervisor.models import AddonsOptions
import voluptuous as vol

from homeassistant.components.hassio import get_supervisor_client
from homeassistant.config_entries import (
    ConfigEntry,
    ConfigFlow,
    ConfigFlowResult,
    OptionsFlow,
)
from homeassistant.core import callback
from homeassistant.helpers.hassio import is_hassio
from homeassistant.helpers.selector import (
    BooleanSelector,
    IconSelector,
    SelectOptionDict,
    SelectSelector,
    SelectSelectorConfig,
    TextSelector,
    TextSelectorConfig,
    TextSelectorType,
)

from .addon import async_fetch_addon_json, service_slug
from .const import ADDON_SLUG_SUFFIX, CONF_ADDON, DOMAIN

CUSTOM = "custom"
URL_RE = re.compile(r"^https?://[^\s\";$]+$")
HEADER_RE = re.compile(r"^[A-Za-z0-9-]+: ?[^$\"\\;{}]*$")


class UniversalProxyConfigFlow(ConfigFlow, domain=DOMAIN):
    """Set up the sidebar panels for the Universal Reverse Proxy add-on."""

    VERSION = 1

    @staticmethod
    @callback
    def async_get_options_flow(config_entry: ConfigEntry) -> OptionsFlow:
        """Services are managed in the options flow."""
        return ServicesOptionsFlow()

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


class ServicesOptionsFlow(OptionsFlow):
    """Add, edit and remove the services of the add-on."""

    def __init__(self) -> None:
        """Nothing loaded yet."""
        self._options: dict[str, Any] = {}
        self._catalog: dict[str, dict] = {}
        self._template: dict | None = None
        self._template_id = CUSTOM
        self._index: int | None = None  # service being edited

    @property
    def _services(self) -> list[dict]:
        return self._options.setdefault("services", [])

    async def async_step_init(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Load the add-on's options and catalog, then show the menu."""
        client = get_supervisor_client(self.hass)
        try:
            info = await client.addons.addon_info(self.config_entry.data[CONF_ADDON])
        except SupervisorError:
            return self.async_abort(reason="cannot_connect")
        catalog = await async_fetch_addon_json(self.hass, info, "_catalog.json")
        if catalog is None:
            return self.async_abort(reason="addon_not_running")
        self._options = dict(info.options)
        self._catalog = {t["id"]: t for t in catalog if isinstance(t.get("id"), str)}

        menu = ["add"]
        if self._services:
            menu += ["edit", "remove"]
        return self.async_show_menu(step_id="init", menu_options=menu)

    # ------------------------------------------------------------- add

    async def async_step_add(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Pick a template."""
        if user_input is not None:
            self._index = None
            self._set_template(user_input["template"])
            return await self.async_step_service()

        options = [
            SelectOptionDict(
                value=tid,
                label=t.get("name", tid)
                + (f" ({t['tested_with']})" if t.get("tested_with") else ""),
            )
            for tid, t in sorted(
                self._catalog.items(), key=lambda i: str(i[1].get("name", i[0])).lower()
            )
        ]
        options.append(SelectOptionDict(value=CUSTOM, label="custom"))
        return self.async_show_form(
            step_id="add",
            data_schema=vol.Schema(
                {
                    vol.Required("template"): SelectSelector(
                        SelectSelectorConfig(options=options)
                    )
                }
            ),
            description_placeholders={"count": str(len(self._catalog))},
        )

    # ------------------------------------------------------------ edit

    async def async_step_edit(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Pick the service to edit."""
        if user_input is not None:
            self._index = int(user_input["service"])
            self._set_template(self._services[self._index].get("template") or CUSTOM)
            return await self.async_step_service()
        return self.async_show_form(
            step_id="edit", data_schema=self._service_picker()
        )

    # ---------------------------------------------------------- remove

    async def async_step_remove(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """Pick the service to remove."""
        errors: dict[str, str] = {}
        if user_input is not None:
            if len(self._services) == 1:
                errors["base"] = "last_service"
            else:
                del self._services[int(user_input["service"])]
                return await self._async_save()
        return self.async_show_form(
            step_id="remove", data_schema=self._service_picker(), errors=errors
        )

    # --------------------------------------------------------- service

    async def async_step_service(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        """The fields of the chosen template."""
        template = self._template or {}
        fields = template.get("fields") or {}
        secret_field = fields.get("secret")
        current = self._services[self._index] if self._index is not None else {}
        errors: dict[str, str] = {}

        if user_input is not None:
            name = user_input["name"].strip()
            url = user_input["url"].strip()
            secret = (user_input.get("secret") or "").strip() or current.get("secret", "")
            headers = [h.strip() for h in user_input.get("headers") or [] if h.strip()]
            taken = {
                service_slug(str(s.get("name", "")))
                for i, s in enumerate(self._services)
                if i != self._index
            }
            if not service_slug(name):
                errors["name"] = "invalid_name"
            elif service_slug(name) in taken:
                errors["name"] = "name_taken"
            if not URL_RE.match(url):
                errors["url"] = "invalid_url"
            if secret_field and secret_field.get("required") and not secret:
                errors["secret"] = "secret_required"
            if any(not HEADER_RE.match(h) for h in headers):
                errors["headers"] = "invalid_header"

            if not errors:
                service = {
                    k: v
                    for k, v in current.items()
                    if k not in ("icon", "admin_only", "user_headers", "headers", "secret")
                }
                service["name"] = name
                service["url"] = url
                if self._template_id != CUSTOM:
                    service["template"] = self._template_id
                if secret_field and secret:
                    service["secret"] = secret
                # store only what differs from the template
                if user_input.get("icon") and user_input["icon"] != template.get("icon"):
                    service["icon"] = user_input["icon"]
                if user_input["admin_only"] != bool(template.get("admin_only", False)):
                    service["admin_only"] = user_input["admin_only"]
                if self._template_id == CUSTOM:
                    if user_input.get("user_headers"):
                        service["user_headers"] = True
                    if headers:
                        service["headers"] = headers
                if self._index is None:
                    self._services.append(service)
                else:
                    self._services[self._index] = service
                return await self._async_save()

        schema: dict[Any, Any] = {
            vol.Required("name", default=current.get("name", template.get("name", ""))): TextSelector(),
            vol.Required(
                "url",
                description={"suggested_value": current.get("url") or (fields.get("url") or {}).get("example")},
            ): TextSelector(TextSelectorConfig(type=TextSelectorType.URL)),
        }
        if secret_field:
            key = vol.Required if secret_field.get("required") and not current.get("secret") else vol.Optional
            schema[key("secret")] = TextSelector(TextSelectorConfig(type=TextSelectorType.PASSWORD))
        schema[vol.Optional("icon", description={"suggested_value": current.get("icon") or template.get("icon")})] = IconSelector()
        schema[vol.Required("admin_only", default=bool(current.get("admin_only", template.get("admin_only", False))))] = BooleanSelector()
        if self._template_id == CUSTOM:
            schema[vol.Required("user_headers", default=bool(current.get("user_headers", False)))] = BooleanSelector()
            schema[vol.Optional("headers", description={"suggested_value": current.get("headers") or []})] = TextSelector(TextSelectorConfig(multiple=True))

        return self.async_show_form(
            step_id="service",
            data_schema=vol.Schema(schema),
            errors=errors,
            description_placeholders={
                "template": template.get("name", "custom"),
                "info": self._template_info(bool(current.get("secret"))),
            },
        )

    # ---------------------------------------------------------- helpers

    def _set_template(self, template_id: str) -> None:
        self._template_id = template_id
        self._template = self._catalog.get(template_id)
        if template_id != CUSTOM and self._template is None:
            # template no longer in the catalog: keep it, ask only the basics
            self._template = {"name": template_id, "fields": {"secret": {"required": False}}}

    def _template_info(self, has_secret: bool) -> str:
        """Help text of the template for the form (Markdown)."""
        t = self._template or {}
        fields = t.get("fields") or {}
        lines = []
        if t.get("homepage"):
            lines.append(f"[{t.get('name', '')}]({t['homepage']})")
        if (fields.get("url") or {}).get("help"):
            lines.append(f"**URL:** {fields['url']['help']}")
        if (fields.get("secret") or {}).get("help"):
            lines.append(f"**Secret:** {fields['secret']['help']}")
        if has_secret:
            lines.append("_Secret: leave empty to keep the current one._")
        if t.get("setup"):
            lines.append(t["setup"])
        if not t:
            lines.append(
                "Any web app. If it breaks under a subpath, a template may help: "
                "[request one](https://github.com/pvillmann/hassio-addon-universal-proxy/issues/new?template=template-request.yml)."
            )
        return "\n\n".join(lines)

    def _service_picker(self) -> vol.Schema:
        return vol.Schema(
            {
                vol.Required("service"): SelectSelector(
                    SelectSelectorConfig(
                        options=[
                            SelectOptionDict(
                                value=str(i),
                                label=f"{s.get('name', '?')} ({s.get('template') or CUSTOM})",
                            )
                            for i, s in enumerate(self._services)
                        ]
                    )
                )
            }
        )

    async def _async_save(self) -> ConfigFlowResult:
        """Write the add-on options, restart it, refresh the sidebar."""
        client = get_supervisor_client(self.hass)
        addon = self.config_entry.data[CONF_ADDON]
        try:
            check = await client.addons.addon_config_validate(addon, self._options)
            if not check.valid:
                return self.async_abort(
                    reason="invalid_options", description_placeholders={"message": check.message}
                )
            await client.addons.set_addon_options(addon, AddonsOptions(config=self._options))
            await client.addons.restart_addon(addon)
            # wait until the add-on serves its new service list (sidebar icons)
            for _ in range(15):
                info = await client.addons.addon_info(addon)
                if await async_fetch_addon_json(self.hass, info, "_services.json") is not None:
                    break
                await asyncio.sleep(2)
        except SupervisorError as err:
            return self.async_abort(
                reason="save_failed", description_placeholders={"message": str(err)}
            )
        sync = getattr(self.config_entry, "runtime_data", None)
        if sync is not None:
            await sync()
        return self.async_create_entry(data={})
