# Template catalog

Templates for the [Universal Reverse Proxy](https://github.com/pvillmann/hassio-addon-universal-proxy) add-on. The add-on downloads this branch at start and once a day, so a merged template reaches every installation within a day, without an add-on update. Before a release the templates are copied into the add-on as its fallback.

Missing an app? [Request a template](https://github.com/pvillmann/hassio-addon-universal-proxy/issues/new?template=template-request.yml). Want to write one? Open a pull request against this branch (`catalog`, not `main`).

## When an app needs a template

Try the app as `custom` first. A template helps when

- the app breaks under a subpath (absolute links like `/api/…` in its pages or scripts),
- it can take the logged-in user from headers (like Frigate),
- it shows broken characters (legacy charset like ISO-8859-1).

## Format

One file per app, `templates/<id>.json`, the file name is the id.

```json
{
  "format": 1,
  "id": "frigate",
  "name": "Frigate NVR",
  "revision": 1,
  "min_addon": "0.6.0",
  "tested_with": "Frigate 0.18",
  "homepage": "https://frigate.video",
  "icon": "mdi:cctv",
  "admin_only": false,
  "user_headers": true,
  "fields": {
    "url": { "example": "https://192.168.1.60:8971", "help": "The authenticated port 8971 (https)." },
    "secret": { "required": true, "header": "X-Proxy-Secret", "help": "Same as proxy.auth_secret in Frigate." }
  },
  "setup": "Markdown shown when the service is set up.",
  "headers": { "X-Example": "fixed value" },
  "rewrite": {
    "paths": ["/api", "/static"],
    "leads": ["\"", "'"],
    "suffixes": ["/"],
    "rules": [{ "from": "href='/'", "to": "href='{base}/'" }]
  },
  "charset": { "source": "iso-8859-1", "skip": "/jpages/" }
}
```

| Key | |
|---|---|
| `format` | Always `1`. |
| `id` | File name: lowercase letters, digits, `-`. |
| `name` | Name of the app. |
| `revision` | Starts at 1. **Raise it with every change**, the add-on uses the highest revision it can. |
| `min_addon` | Oldest add-on version that understands every key you use (format 1: `0.6.0`). Older add-ons skip the template. |
| `tested_with` | App version you tested with. |
| `homepage` | https link to the app. |
| `icon`, `admin_only` | Defaults for the sidebar entry, users can override them. |
| `user_headers` | Send the Home Assistant user as `Remote-User` and the role (`admin`/`viewer`) as `Remote-Role` and `Remote-Groups`. |
| `fields` | What a user has to fill in: `url` (always, with `example` and `help`) and `secret` (with the `header` it is sent in, `required`, `help`). Nothing else is asked. |
| `setup` | Notes for the user, e.g. what to change in the app's config. `{base}` shows the real service path in the setup dialog, for apps that need their base path configured (add-on 0.9.0+). |
| `headers` | Fixed headers sent to the app. `{base}` is replaced with the service path, e.g. `"X-Forwarded-Prefix": "{base}"` (add-on 0.9.0+). |
| `role_values` | Values for `admin` and `viewer` in the role headers, e.g. `{"admin": "Admin", "viewer": "Viewer"}` for Grafana (add-on 0.9.0+). |
| `rewrite` | Absolute paths in answers get the service path in front: every combination of `leads` + `paths` + `suffixes` (defaults `"` `'` and `/`), plus single `rules`. `{base}` is the service path. |
| `charset` | The app sends ISO-8859-1: answers to POST requests are recoded to UTF-8 (the Supervisor drops the charset header), except below `skip`. |

## Rules

The apps run on the same address as Home Assistant. A template that could put any text into a page could also read the Home Assistant login. So templates can only move paths, and the add-on and CI check that with [`validate.jq`](https://github.com/pvillmann/hassio-addon-universal-proxy/blob/main/universal-reverse-proxy/validate.jq):

- `paths`: like `/api`, letters, digits and `. _ ~ / -`.
- `leads`: `"` `'` `=` space `(` `\` `'`. `suffixes`: `/` `\/` `?` `"` `'`.
- `rules`: `to` is `from` with `{base}` put in once, right before a `/`. No `$ < >`.
- `headers` and the secret header: not `Host`, `Connection`, `Upgrade`, `X-Real-IP`, `X-Ingress-Path`, `Forwarded`, `X-Forwarded-For/-Proto/-Host/-Port`, `Remote-*`, `X-Remote-User-*`. Values without `$ " \ ; { }`, except the placeholder `{base}`.
- `role_values`: letters, digits, `_` and `-`.
- `charset.source`: `iso-8859-1`.
- At most 500 rewrite rules.

## Testing a template

Copy it to `universal-reverse-proxy/templates/` of the add-on (local add-on) or check it with `sh tools/check-templates.sh <dir>` from `main` (needs `nginx` and `jq`). Then test login, navigation and a reload inside Home Assistant.
