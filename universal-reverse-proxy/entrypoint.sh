#!/bin/sh
set -eu

# paths can be overridden for local tests
OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"
NGINX_DIR="${NGINX_DIR:-/etc/nginx}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/etc/nginx/templates}"
HTML_DIR="${HTML_DIR:-/usr/share/nginx/html}"
SERVICES_FILE="$NGINX_DIR/services.conf"
COMMON_FILE="$NGINX_DIR/proxy_common.conf"

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

# nginx double-quoted string: escape \ and "
nginx_quote() {
	printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

: > "$SERVICES_FILE"
slugs=""
slugs_all=""
slugs_viewer=""
links_all=""
links_viewer=""
checks=""

i=0
while [ "$i" -lt "$count" ]; do
	raw=$(jq -c ".services[$i]" "$OPTIONS_FILE")
	i=$((i + 1))
	name=$(printf '%s' "$raw" | jq -r '.name')
	template=$(printf '%s' "$raw" | jq -r '.template // "custom"')

	# a template provides defaults, the service's own settings win
	if [ "$template" = "custom" ]; then
		svc="$raw"
	elif [ -f "$TEMPLATE_DIR/$template.json" ]; then
		svc=$(jq -c --argjson s "$raw" '. + $s' "$TEMPLATE_DIR/$template.json")
	else
		echo "Service '$name': unknown template '$template'."
		exit 1
	fi

	url=$(printf '%s' "$svc" | jq -r '.url' | sed 's#/*$##')
	admin_only=$(printf '%s' "$svc" | jq -r '.admin_only // false')
	user_headers=$(printf '%s' "$svc" | jq -r '.user_headers // false')
	secret=$(printf '%s' "$svc" | jq -r '.secret // ""')
	secret_header=$(printf '%s' "$svc" | jq -r '.secret_header // ""')
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

	# fixed headers: "Name: value" entries plus the template's secret header
	headers=$(printf '%s' "$svc" | jq -c '.headers // []')
	if [ -n "$secret_header" ]; then
		if [ -z "$secret" ]; then
			echo "Service '$name': template '$template' needs a secret (sent as $secret_header)."
			exit 1
		fi
		headers=$(printf '%s' "$headers" | jq -c --arg h "$secret_header: $secret" '. + [$h]')
	fi
	extra=""
	j=0
	n=$(printf '%s' "$headers" | jq -r 'length')
	while [ "$j" -lt "$n" ]; do
		h=$(printf '%s' "$headers" | jq -r ".[$j]")
		j=$((j + 1))
		hname=$(printf '%s' "$h" | sed -E 's/^([^:]*):.*/\1/' | sed -E 's/^ +| +$//g')
		hvalue=$(printf '%s' "$h" | sed -E 's/^[^:]*: *//')
		if [ "$hname" = "$h" ] || ! printf '%s' "$hname" | grep -Eq '^[A-Za-z0-9-]+$'; then
			echo "Service '$name': invalid header '$hname', expected 'Name: value'"
			exit 1
		fi
		if printf '%s' "$hvalue" | grep -q '[$"\;{}]'; then
			echo "Service '$name': header $hname must not contain \$ \" \\ ; { }"
			exit 1
		fi
		extra="$extra
            proxy_set_header $hname \"$hvalue\";"
	done

	# apps with absolute paths: put the ingress path in front of them in the
	# responses (templates only, the rules are app specific)
	rewrite=""
	rules=$(printf '%s' "$svc" | jq -c '
		[ (.rewrite_paths // [])[] as $p | (.rewrite_leads // ["\"", "'"'"'"])[] as $l
		  | (.rewrite_suffixes // ["/"])[] as $e
		  | {from: ($l + $p + $e), to: ($l + "{base}" + $p + $e)} ]
		+ (.rewrite // [])')
	nrules=$(printf '%s' "$rules" | jq -r 'length')
	if [ "$nrules" -gt 0 ]; then
		rewrite="
            # rewrite absolute paths in responses (template $template)
            proxy_set_header Accept-Encoding \"\";
            sub_filter_once off;
            sub_filter_types text/css text/javascript application/javascript application/x-javascript application/json;"
		k=0
		while [ "$k" -lt "$nrules" ]; do
			from=$(printf '%s' "$rules" | jq -r ".[$k].from")
			to=$(printf '%s' "$rules" | jq -r ".[$k].to")
			k=$((k + 1))
			to_q=$(nginx_quote "$to" | sed "s#{base}#\$http_x_ingress_path/${slug}#g")
			rewrite="$rewrite
            sub_filter $(nginx_quote "$from") $to_q;"
		done
	fi

	cat >> "$SERVICES_FILE" <<CONF
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
            # redirects to an absolute path stay inside the service
            proxy_redirect ${url}/ \$http_x_ingress_path/${slug}/;
            proxy_redirect ~^/(?!api/hassio_ingress/)(.*)\$ \$http_x_ingress_path/${slug}/\$1;${rewrite}
        }

CONF
	link="<li><a href=\"${slug}/\">$(html_escape "$name")</a></li>"
	links_all="$links_all$link"
	slugs_all="$slugs_all $slug"
	if [ "$admin_only" != "true" ]; then
		links_viewer="$links_viewer$link"
		slugs_viewer="$slugs_viewer $slug"
	fi
	checks="$checks$name|$url
"
	info=""
	[ "$template" != custom ] && info="$info, template $template"
	[ "$admin_only" = true ] && info="$info, admin only"
	[ "$user_headers" = true ] && info="$info, user headers"
	[ "$nrules" -gt 0 ] && info="$info, $nrules rewrite rules"
	echo "Service '$name': /${slug}/ -> ${url}${info:+ (${info#, })}"
done

write_index() {
	file="$1"
	slug_list=$(printf '%s' "$2" | jq -Rc 'split(" ") | map(select(. != ""))')
	links="$3"
	cat > "$file" <<HTML
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
HTML
}

mkdir -p "$HTML_DIR"
write_index "$HTML_DIR/index-admin.html" "$slugs_all" "$links_all"
write_index "$HTML_DIR/index-viewer.html" "$slugs_viewer" "$links_viewer"

# tell the user early if a service can't be reached (does not stop the add-on)
check_services() {
	printf '%s' "$checks" | while IFS='|' read -r cname curl_url; do
		[ -n "$curl_url" ] || continue
		code=$(curl -sk -o /dev/null --max-time 5 -w '%{http_code}' "$curl_url/" 2>/dev/null || true)
		case "$code" in
			000 | "") echo "WARNING: Service '$cname' is not reachable at $curl_url (check url, port and firewall)." ;;
			5??) echo "WARNING: Service '$cname' answers with HTTP $code at $curl_url." ;;
			*) echo "Service '$cname' reachable (HTTP $code)." ;;
		esac
	done
}

if [ -n "${NO_EXEC:-}" ]; then
	check_services
	exit 0
fi

cp "$NGINX_DIR/nginx.conf.gtpl" "$NGINX_DIR/nginx.conf"

echo "Starting universal reverse proxy with ${count} service(s)"
check_services &
exec nginx -g 'daemon off;'
