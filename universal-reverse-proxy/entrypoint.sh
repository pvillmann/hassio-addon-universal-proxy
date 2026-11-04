#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"
SERVICES_FILE="/etc/nginx/services.conf"
INDEX_FILE="/usr/share/nginx/html/index.html"

if [ ! -f "$OPTIONS_FILE" ]; then
	echo "Missing options file: $OPTIONS_FILE"
	exit 1
fi

count=$(jq -r '.services | length' "$OPTIONS_FILE" 2>/dev/null || echo 0)
if [ "$count" -le 0 ]; then
	echo "No services configured. Add at least one entry to options.services."
	exit 1
fi

# path of a service = its name, lowercased, everything else than a-z0-9 -> "-"
# (the companion integration derives the sidebar URL the same way)
slugify() {
	printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

: > "$SERVICES_FILE"
slugs=""
links=""

i=0
while [ "$i" -lt "$count" ]; do
	name=$(jq -r ".services[$i].name" "$OPTIONS_FILE")
	url=$(jq -r ".services[$i].url" "$OPTIONS_FILE" | sed 's#/*$##')
	slug=$(slugify "$name")
	i=$((i + 1))

	if [ -z "$slug" ]; then
		echo "Service '$name': name needs at least one letter or digit."
		exit 1
	fi
	if ! printf '%s' "$url" | grep -Eq '^https?://[^[:space:]]+$'; then
		echo "Service '$name': invalid url '$url', expected http(s)://host:port"
		exit 1
	fi
	case " $slugs " in
		*" $slug "*)
			echo "Service '$name': path '/$slug/' is already used by another service."
			exit 1
			;;
	esac
	slugs="$slugs $slug"

	cat >> "$SERVICES_FILE" <<EOF
        location = /${slug} {
            return 302 \$http_x_ingress_path/${slug}/;
        }

        location /${slug}/ {
            set \$service_ingress_path \$http_x_ingress_path/${slug};
            proxy_pass ${url}/;
        }

EOF
	html_name=$(printf '%s' "$name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
	links="$links<li><a href=\"${slug}/\">${html_name}</a></li>"
	echo "Service '$name': /${slug}/ -> ${url}"
done

slug_list=$(printf '%s' "$slugs" | jq -Rc 'split(" ") | map(select(. != ""))')

mkdir -p "$(dirname "$INDEX_FILE")"
cat > "$INDEX_FILE" <<EOF
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Proxy</title>
<style>
body { font-family: system-ui, sans-serif; margin: 24px; color: #212121; }
#list { display: none; }
@media (prefers-color-scheme: dark) { body { background: #111; color: #e1e1e1; } a { color: #8ab4f8; } }
</style>
<script>
// Each service has its own sidebar panel (registered by the companion
// integration) that loads this page. Home Assistant tells the page which panel
// it runs in, the page then jumps to that service.
(function () {
  var services = ${slug_list};
  var done = false;
  function showList() {
    if (!done) { done = true; document.getElementById("list").style.display = "block"; }
  }
  window.addEventListener("message", function (ev) {
    if (ev.source !== window.parent || !ev.data || ev.data.type !== "home-assistant/properties") return;
    var prefix = (ev.data.route && ev.data.route.prefix) || "";
    var m = prefix.match(/^\/proxy-([a-z0-9-]+)$/);
    if (!done && m && services.indexOf(m[1]) !== -1) {
      done = true;
      window.location.replace(m[1] + "/");
      return;
    }
    showList();
  });
  if (window.parent !== window) {
    window.parent.postMessage({ type: "home-assistant/subscribe-properties" }, "*");
  }
  setTimeout(showList, 1500);
})();
</script>
</head>
<body>
<div id="list">
<h1>Proxy</h1>
<ul>${links}</ul>
</div>
</body>
</html>
EOF

cp /etc/nginx/nginx.conf.gtpl /etc/nginx/nginx.conf

echo "Starting universal reverse proxy with ${count} service(s)"
exec nginx -g 'daemon off;'
