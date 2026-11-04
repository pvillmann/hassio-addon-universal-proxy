# Changelog

## 0.3.0

- Breaking: `routes` replaced by `services` (name, url, icon, admin_only)
- Each service gets its own sidebar entry via the companion integration "Universal Proxy" (HACS, same repository)
- Start page jumps to the service of the sidebar entry it is opened from
- Access limited to the Supervisor ingress gateway, like the Frigate proxy
- `X-Ingress-Path` per service (base path for apps like Frigate)
- Removed the OPNsense-specific rewrites, the proxy is generic again
- Healthcheck on `/healthz`, base image 21.0.0

## 0.2.12

- Added OPNsense route rewrites for absolute upstream origin URLs (including protocol-relative URLs) to keep asset loading inside the proxied subpath

## 0.2.11

- Added OPNsense compatibility fallback for root-absolute asset paths (`/ui`, `/css`, `/js`, `/themes`, `/vendor`)
- Removed duplicate `text/html` warning source from route-level `sub_filter_types`

## 0.2.10

- Scoped aggressive compatibility rewrites to `/opnsense` only
- Restored minimal default proxy behavior for other routes (e.g. evcc) to avoid WebSocket regressions

## 0.2.9

- Fixed evcc websocket forwarding again by restoring always-on `Connection: upgrade` behavior

## 0.2.8

- Fixed evcc WebSocket regression (`/ws` returning 426) by restoring compatible `Host` forwarding and conditional `Connection` upgrade handling

## 0.2.7

- Fixed OPNsense-style UI rendering behind subpaths by disabling upstream compression for rewriteable responses
- Added absolute URL redirect rewrite handling and single-quote HTML attribute rewrites
- Removed duplicate `text/html` from `sub_filter_types` to avoid nginx warnings

## 0.2.6

- Improved compatibility for subpath-hosted apps (e.g. OPNsense): base/content/css URL rewrites and cookie path rewrite
- Switched upstream `Host` header handling to better match backend expectations

## 0.2.5

- Fixed startup crash `/entrypoint.sh: line 88: 1: parameter not set` by escaping nginx backreference in generated `proxy_redirect`

## 0.2.4

- Improved subpath compatibility for apps like OPNsense by rewriting root-relative redirects and common HTML URL attributes (`href`, `src`, `action`)

## 0.2.3

- Fixed root page route links to work correctly behind Home Assistant Ingress base paths

## 0.2.2

- Fixed startup error by creating the index output directory before writing `index.html`

## 0.2.1

- Added a root landing page that lists all configured route links

## 0.2.0

- Renamed add-on to Universal Reverse Proxy
- Added multi-target routing via configurable subpaths
- Added `routes` option with `/subpath|http://target-host:port` format
- Added runtime validation for route mappings

## 0.1.1

- Initial release of the evcc proxy add-on
- Adds Home Assistant Ingress access to an externally hosted evcc instance
- Uses nginx as a lightweight reverse proxy with WebSocket support
- Marked as experimental for initial user feedback
