<img src="universal-reverse-proxy/logo.png" alt="Universal Proxy" width="250">

# Universal Proxy for Home Assistant

One add-on instead of one proxy add-on per app: list your externally hosted web apps (evcc, Frigate, OpenCCU, …) and each one gets its own sidebar entry, opening inside Home Assistant like an ingress add-on.

- One sidebar entry per app, with its own name and icon
- Admins-only apps are hidden from other users and blocked for them
- Apps can get the Home Assistant user and role (e.g. Frigate: admins stay admins, everyone else becomes viewer)
- Templates for known apps from a catalog that updates without new releases, `custom` for anything else
- Set up in a dialog: pick the app, fill in only what it needs

## You need both parts

| | What it does | Install from |
|---|---|---|
| **Universal Reverse Proxy** (add-on) | The proxy itself, runs on Home Assistant OS / Supervised | Add-on store |
| **Universal Proxy** (integration) | Sidebar entries and setup dialog | [HACS](https://hacs.xyz) |

Both come from this repository. Needs Home Assistant OS or Supervised (add-ons) and HACS.

## Install

**1. Add-on**

[![Open your Home Assistant instance and show the add-on.](https://my.home-assistant.io/badges/supervisor_addon.svg)](https://my.home-assistant.io/redirect/supervisor_addon/?addon=2e4b761a_universal_reverse_proxy&repository_url=https%3A%2F%2Fgithub.com%2Fpvillmann%2Fhassio-addon-universal-proxy)

Adds this repository to the add-on store and opens the add-on. Install and start it (it starts with an example service, you set up your own in step 3).

<details><summary>Manually</summary>

Settings → Add-ons → Add-on store → ⋮ → Repositories → add `https://github.com/pvillmann/hassio-addon-universal-proxy`, then install **Universal Reverse Proxy**.
</details>

**2. Integration**

[![Open your Home Assistant instance and open the repository in HACS.](https://my.home-assistant.io/badges/hacs_repository.svg)](https://my.home-assistant.io/redirect/hacs_repository/?owner=pvillmann&repository=hassio-addon-universal-proxy&category=integration)

Download **Universal Proxy** in HACS and restart Home Assistant. Then add the integration:

[![Open your Home Assistant instance and start setting up the integration.](https://my.home-assistant.io/badges/config_flow_start.svg)](https://my.home-assistant.io/redirect/config_flow_start/?domain=universal_proxy)

<details><summary>Manually</summary>

HACS → ⋮ → Custom repositories → add `https://github.com/pvillmann/hassio-addon-universal-proxy` as type **Integration**, download **Universal Proxy**, restart Home Assistant, then Settings → Devices & services → Add integration → Universal Proxy.
</details>

**3. Services**

Settings → Devices & services → Universal Proxy → **Configure** → *Add a service*: pick the app from the template catalog (or `custom`) and fill in the fields it asks for. The add-on restarts and the sidebar entry appears.

You can also edit the services in the add-on's configuration (YAML), see [DOCS.md](universal-reverse-proxy/DOCS.md).

## Templates

Templates make apps work that need more than a plain proxy: absolute links, a login by header, a legacy charset. They live on the [`catalog` branch](../../tree/catalog), the add-on loads it at start and once a day.

Your app is missing or needs special handling? [Request a template](../../issues/new?template=template-request.yml). Writing one yourself: format and rules are in the README of the catalog branch, pull requests go there.

## More

Details, security notes and limits: [DOCS.md](universal-reverse-proxy/DOCS.md).
