# Universal Reverse Proxy

One add-on for several externally hosted web apps (evcc, Frigate, OpenCCU, …). Each app gets its own sidebar entry with its own name, icon and admin setting, and opens inside Home Assistant like an ingress add-on. The add-on does not run the apps itself.

## Setup

1. Install this add-on and configure the services (see below), then start it.
2. Install the companion integration **Universal Proxy** via HACS (custom repository, same URL as this add-on repository) and add it under Settings → Devices & services. It finds the add-on by itself.
3. Optional: turn off "Show in sidebar" for the add-on itself. Its own entry only shows a list of all services.

## Configuration

```yaml
services:
  - name: evcc
    url: http://192.168.1.50:7070
    icon: mdi:ev-station
  - name: Frigate
    url: http://192.168.1.60:5000
    icon: mdi:cctv
    admin_only: true
```

| Option | Required | Description |
|---|---|---|
| `name` | yes | Sidebar title. Also the path: lowercase, other characters become `-` (`evcc` → `/evcc/`). |
| `url` | yes | Where Home Assistant reaches the app. |
| `icon` | no | Any `mdi:` icon, default `mdi:web`. |
| `admin_only` | no | Admins only: hides the sidebar entry and blocks non-admins (403). |
| `user_headers` | no | Send the Home Assistant user as `Remote-User` (username) and the role (`admin` or `viewer`) as `Remote-Role` and `Remote-Groups`. |
| `headers` | no | Extra fixed headers, `Name: value` (no `$ " \ ; { }`), e.g. a shared secret. |

The integration picks up changes within a minute. The add-on needs a restart after changing services.

## Security

- Requests reach the add-on only through Home Assistant ingress. Ingress requires a logged-in Home Assistant user, also via Nabu Casa or any reverse proxy. The add-on opens no port of its own, and nginx accepts only the Supervisor ingress gateway.
- The Supervisor tells the add-on who is logged in (`X-Remote-User-*` headers) and removes headers of that name sent by the browser. `admin_only` uses the user's groups from there, so it is enforced, not only hidden. Needs Supervisor 2026.10.5 or newer.
- `Remote-User`, `Remote-Role` and `Remote-Groups` are always set by the proxy (empty when `user_headers` is off), so a browser can't inject them. The `X-Remote-User-*` headers are not passed on to the apps.
- Like the single-app proxies, the add-on removes `X-Frame-Options` and `Content-Security-Policy` from responses so the apps can be shown inside Home Assistant.

## Frigate with Home Assistant users

Admins log in to Frigate as admin, everyone else as viewer. Use Frigate's authenticated port and a shared secret, so nobody else in the network can send these headers to Frigate:

```yaml
# add-on
services:
  - name: Frigate
    url: https://192.168.1.60:8971
    icon: mdi:cctv
    user_headers: true
    headers:
      - "X-Proxy-Secret: <long random string>"
```

```yaml
# Frigate config
proxy:
  auth_secret: <same string>
  header_map:
    user: remote-user
    role: remote-groups
  default_role: viewer
```

Frigate hands only some headers (`Remote-User`, `Remote-Groups`, …) to its auth check, `Remote-Role` is not among them, so the role must come from `remote-groups`. If Frigate is also reachable through another reverse proxy, let that proxy overwrite `Remote-User` and `Remote-Groups` too (e.g. fixed `viewer`), otherwise a client could send its own.

## Apps under a subpath

Each service runs under its own path (`…/evcc/`). Apps with relative links work as is (evcc does). Apps that support a base path via the `X-Ingress-Path` header (Frigate) get it per service. Apps that hard-code absolute paths (`/css/…`) do not work under a subpath, use a dedicated proxy add-on for them.

## How the sidebar entries work

The Supervisor gives an add-on exactly one sidebar entry. The integration registers one more ingress panel per service, pointing to this add-on. All of them load the add-on's start page, which asks Home Assistant which panel it runs in and jumps to the matching service. This uses internal frontend behaviour, a Home Assistant update may require an update of the integration.
