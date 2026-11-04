#!/bin/sh
set -eu

OPTIONS_FILE="/data/options.json"
SERVICES_FILE="/etc/nginx/services.conf"
COMMON_FILE="/etc/nginx/proxy_common.conf"
HTML_DIR="/usr/share/nginx/html"

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

html_escape() {
	printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

: > "$SERVICES_FILE"
slugs=""
slugs_all=""
slugs_viewer=""
links_all=""
links_viewer=""

i=0
while [ "$i" -lt "$count" ]; do
	svc=$(jq -c ".services[$i]" "$OPTIONS_FILE")
	i=$((i + 1))
	name=$(printf '%s' "$svc" | jq -r '.name')
	url=$(printf '%s' "$svc" | jq -r '.url' | sed 's#/*$##')
	admin_only=$(printf '%s' "$svc" | jq -r '.admin_only // false')
	user_headers=$(printf '%s' "$svc" | jq -r '.user_headers // false')
	slug=$(slugify "$name")

	if [ -z "$slug" ]; then
		echo "Service '$name': name needs at least one letter or digit."
		exit 1
	fi
	if ! printf '%s' "$url" | grep -Eq '^https?://[^[:space:]";$]+$'; then
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

	guard=""
	if [ "$admin_only" = "true" ]; then
		guard='if ($ha_is_admin = 0) { return 403; }'
	fi

	if [ "$user_headers" = "true" ]; then
		user_value='$http_x_remote_user_name'
		role_value='$ha_role'
	else
		user_value='""'
		role_value='""'
	fi

	extra=""
	j=0
	n=$(printf '%s' "$svc" | jq -r '.headers // [] | length')
	while [ "$j" -lt "$n" ]; do
		h=$(printf '%s' "$svc" | jq -r ".headers[$j]")
		j=$((j + 1))
		hname=$(printf '%s' "$h" | sed -E 's/^([^:]*):.*/\1/' | sed -E 's/^ +| +$//g')
		hvalue=$(printf '%s' "$h" | sed -E 's/^[^:]*: *//')
		if [ "$hname" = "$h" ] || ! printf '%s' "$hname" | grep -Eq '^[A-Za-z0-9-]+$'; then
			echo "Service '$name': invalid header '$h', expected 'Name: value'"
			exit 1
		fi
		if printf '%s' "$hvalue" | grep -q '[$"\;{}]'; then
			echo "Service '$name': header $hname must not contain \$ \" \\ ; { }"
			exit 1
		fi
		extra="$extra
            proxy_set_header $hname \"$hvalue\";"
	done

	cat >> "$SERVICES_FILE" <<EOF
        location = /${slug} {
            ${guard}
            return 302 \$http_x_ingress_path/${slug}/;
        }

        location /${slug}/ {
            ${guard}
            proxy_pass ${url}/;
            include ${COMMON_FILE};
            # base path for apps that support it (e.g. Frigate)
            proxy_set_header X-Ingress-Path \$http_x_ingress_path/${slug};
            proxy_set_header Remote-User ${user_value};
            proxy_set_header Remote-Role ${role_value};
            proxy_set_header Remote-Groups ${role_value};${extra}
        }

EOF
	link="<li><a href=\"${slug}/\">$(html_escape "$name")</a></li>"
	links_all="$links_all$link"
	slugs_all="$slugs_all $slug"
	if [ "$admin_only" != "true" ]; then
		links_viewer="$links_viewer$link"
		slugs_viewer="$slugs_viewer $slug"
	fi
	echo "Service '$name': /${slug}/ -> ${url}$([ "$admin_only" = true ] && echo ' (admin only)')$([ "$user_headers" = true ] && echo ' (user headers)')"
done

write_index() {
	file="$1"
	slug_list=$(printf '%s' "$2" | jq -Rc 'split(" ") | map(select(. != ""))')
	links="$3"
	cat > "$file" <<EOF
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
}

mkdir -p "$HTML_DIR"
write_index "$HTML_DIR/index-admin.html" "$slugs_all" "$links_all"
write_index "$HTML_DIR/index-viewer.html" "$slugs_viewer" "$links_viewer"

cp /etc/nginx/nginx.conf.gtpl /etc/nginx/nginx.conf

echo "Starting universal reverse proxy with ${count} service(s)"
exec nginx -g 'daemon off;'
