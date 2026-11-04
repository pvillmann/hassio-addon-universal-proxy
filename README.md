<img src="universal-reverse-proxy/logo.png" alt="Universal Proxy" width="250">

# Universal Proxy for Home Assistant

One add-on instead of one proxy add-on per app: list your externally hosted web apps (evcc, Frigate, OpenCCU, …) and each one gets its own sidebar entry, opening inside Home Assistant like an ingress add-on.

This repository contains both parts:

- **Universal Reverse Proxy** (add-on, `universal-reverse-proxy/`): nginx ingress proxy, one path per service, templates for known apps from a catalog that updates without new releases (evcc, Frigate, OpenCCU, …) plus `custom` for anything else.
- **Universal Proxy** (integration, `custom_components/universal_proxy/`): registers the sidebar entries.

## Install

1. Settings → Add-ons → Add-on Store → ⋮ → Repositories → add `https://github.com/pvillmann/hassio-addon-universal-proxy`, install **Universal Reverse Proxy**, configure your services, start it.
2. HACS → ⋮ → Custom repositories → add the same URL as type **Integration**, install **Universal Proxy**, restart Home Assistant, then Settings → Devices & services → Add integration → Universal Proxy.

Details, security notes and limits: [DOCS.md](universal-reverse-proxy/DOCS.md).

## Templates

Your app is missing or needs special handling? [Request a template](../../issues/new?template=template-request.yml). Templates live on the [`catalog` branch](../../tree/catalog), its README describes the format. Pull requests with new templates go there, the add-on picks them up within a day after merging.
