# Universal Reverse Proxy

One add-on for several externally hosted web apps (evcc, Frigate, OpenCCU, …). Each app gets its own sidebar entry with its own name, icon and admin setting, and opens inside Home Assistant like an ingress add-on. The add-on does not run the apps itself.

## Setup

1. Install this add-on and configure the services (see below), then start it.
2. Install the companion integration **Universal Proxy** via HACS (custom repository, same URL as this add-on repository) and add it under Settings → Devices & services. It finds the add-on by itself.
3. Optional: turn off "Show in sidebar" for the add-on itself. Its own entry only shows a list of all services.

## Configuration

Pick a **template** for a known app, it brings the right settings along. Everything else is `custom` (the default).

```yaml
services:
  - name: evcc
    template: evcc
    url: http://192.168.1.50:7070
  - name: Frigate
    template: frigate
    url: https://192.168.1.60:8971
    secret: <long random string>
  - name: OpenCCU
    template: openccu
    url: http://192.168.1.70
  - name: Something else
    url: http://192.168.1.80:8080
    icon: mdi:web
```

| Option | Required | Description |
|---|---|---|
| `name` | yes | Sidebar title. Also the path: lowercase, other characters become `-` (`evcc` → `/evcc/`). |
| `template` | no | `custom` (default), `evcc`, `frigate` or `openccu`, see [Templates](#templates). |
| `url` | yes | Where Home Assistant reaches the app. |
| `secret` | template | Shared secret for templates that need one (Frigate). |
| `icon` | no | Any `mdi:` icon. Default: the template's icon, else `mdi:web`. |
| `admin_only` | no | Admins only: hides the sidebar entry and blocks non-admins (403). |
| `user_headers` | no | Send the Home Assistant user as `Remote-User` (username) and the role (`admin` or `viewer`) as `Remote-Role` and `Remote-Groups`. |
| `headers` | no | Extra fixed headers, `Name: value` (no `$ " \ ; { }`), e.g. a shared secret. |

Your own settings always win over the template's. The integration picks up changes within a minute. The add-on needs a restart after changing services. At start the log tells you for every service whether Home Assistant can reach it.

## Templates

| Template | What it does | You set |
|---|---|---|
| `evcc` | Icon. evcc works under a subpath as is. | `url` |
| `frigate` | Icon, Home Assistant user → Frigate user, admins → Frigate admin, everyone else → viewer, sends `secret` as `X-Proxy-Secret`. | `url` (port **8971**, https), `secret`, Frigate config below |
| `openccu` | Icon, admins only, rewrites the absolute paths of the WebUI (same rules as the official OpenCCU proxy add-on). | `url`; allow Home Assistant in the OpenCCU firewall |

### Frigate

Frigate's config, with the same secret as in the add-on:

```yaml
proxy:
  auth_secret: <same string>
  header_map:
    user: remote-user
    role: remote-groups
  default_role: viewer
```

The secret makes sure nobody else in the network can send these headers to Frigate's port 8971. Frigate hands only some headers to its auth check (`Remote-User`, `Remote-Groups`, …, but not `Remote-Role`), so the role comes from `remote-groups`. If Frigate is also reachable through another reverse proxy, let that proxy send the secret and overwrite `Remote-User` and `Remote-Groups` (e.g. fixed `viewer`), otherwise a client could send its own.

### New templates

A template is a small JSON file in `universal-reverse-proxy/templates/`, pull requests welcome. Keys: `icon`, `admin_only`, `user_headers`, `secret_header`, `headers`, and for apps with absolute paths `rewrite_paths`, `rewrite_leads`, `rewrite_suffixes` and `rewrite` (`{"from": …, "to": …}`, `{base}` = path of the service). Add icon and admin default to `TEMPLATE_DEFAULTS` of the integration too.

## Security

- Requests reach the add-on only through Home Assistant ingress. Ingress requires a logged-in Home Assistant user, also via Nabu Casa or any reverse proxy. The add-on opens no port of its own, and nginx accepts only the Supervisor ingress gateway.
- The Supervisor tells the add-on who is logged in (`X-Remote-User-*` headers) and removes headers of that name sent by the browser. `admin_only` uses the user's groups from there, so it is enforced, not only hidden. Needs Supervisor 2026.10.5 or newer, with older versions everyone counts as non-admin.
- `Remote-User`, `Remote-Role` and `Remote-Groups` are always set by the proxy (empty when `user_headers` is off), so a browser can't inject them. The `X-Remote-User-*` headers are not passed on to the apps.
- Like the single-app proxies, the add-on removes `X-Frame-Options` and `Content-Security-Policy` from responses so the apps can be shown inside Home Assistant.
- https upstreams are not verified (self-signed certificates are common on the LAN).

## Apps under a subpath

Each service runs under its own path (`…/evcc/`). This works for apps with relative links (evcc), apps that take their base path from the `X-Ingress-Path` header (Frigate, set per service) and apps with a template that rewrites their paths (OpenCCU). Redirects to an absolute path are kept inside the service. Apps that build absolute paths in JavaScript at runtime may still break as `custom`. If one of them matters to you, open an issue, it may be a candidate for a template.

## How the sidebar entries work

The Supervisor gives an add-on exactly one sidebar entry. The integration registers one more ingress panel per service, pointing to this add-on. All of them load the add-on's start page, which asks Home Assistant which panel it runs in and jumps to the matching service. This uses internal frontend behaviour, a Home Assistant update may require an update of the integration.
