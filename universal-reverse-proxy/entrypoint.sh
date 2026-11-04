#!/bin/sh
set -eu

# paths can be overridden for local tests and CI
OPTIONS_FILE="${OPTIONS_FILE:-/data/options.json}"
NGINX_DIR="${NGINX_DIR:-/etc/nginx}"
NGINX_CONF="${NGINX_CONF:-$NGINX_DIR/nginx.conf}"
HTML_DIR="${HTML_DIR:-/usr/share/nginx/html}"
SERVICES_FILE="$NGINX_DIR/services.conf"
MAPS_FILE="$NGINX_DIR/maps.conf"
COMMON_FILE="$NGINX_DIR/proxy_common.conf"
VALIDATOR="${VALIDATOR:-$NGINX_DIR/validate.jq}"
# templates shipped with this version, the catalog cache and the templates in use
BUNDLED_DIR="${BUNDLED_DIR:-$NGINX_DIR/templates}"
CACHE_DIR="${CACHE_DIR:-/data/catalog}"
ACTIVE_DIR="${ACTIVE_DIR:-$NGINX_DIR/templates.active}"
CATALOG_URL="${CATALOG_URL:-https://codeload.github.com/pvillmann/hassio-addon-universal-proxy/tar.gz/refs/heads/catalog}"
REFRESH_SECONDS="${REFRESH_SECONDS:-86400}"
# set by the Supervisor build (BUILD_VERSION)
ADDON_VERSION="${ADDON_VERSION:-}"

if [ ! -f "$OPTIONS_FILE" ]; then
	echo "Missing options file: $OPTIONS_FILE"
	exit 1
fi

# ---------------------------------------------------------------- templates

# prints the problems of a template, nothing when it is fine
template_problems() {
	jq -r --arg id "$2" -f "$VALIDATOR" "$1" 2>/dev/null || echo "not valid JSON"
}

# true when this add-on version is new enough for the template
version_ok() {
	[ -n "$ADDON_VERSION" ] || return 0
	jq -e --arg v "$ADDON_VERSION" '
		def ver: split(".") | map(tonumber? // 0);
		(.min_addon | ver) <= ($v | ver)' "$1" >/dev/null
}

# download the catalog branch, keep the templates that pass the checks
fetch_catalog() {
	tmp=$(mktemp -d)
	if ! curl -sfL --max-time 30 --max-filesize 5000000 -o "$tmp/catalog.tgz" "$CATALOG_URL" ||
		! tar -xzf "$tmp/catalog.tgz" -C "$tmp" 2>/dev/null; then
		echo "Template catalog: download failed, using the last known templates."
		rm -rf "$tmp"
		return 1
	fi
	mkdir "$tmp/ok"
	for f in "$tmp"/*/templates/*.json; do
		[ -f "$f" ] || continue
		id=$(basename "$f" .json)
		problems=$(template_problems "$f" "$id")
		if [ -n "$problems" ]; then
			echo "Template catalog: '$id' rejected: $(printf '%s' "$problems" | tr '\n' ';')"
			continue
		fi
		cp "$f" "$tmp/ok/"
	done
	mkdir -p "$(dirname "$CACHE_DIR")"
	rm -rf "$CACHE_DIR.new"
	mv "$tmp/ok" "$CACHE_DIR.new"
	rm -rf "$CACHE_DIR"
	mv "$CACHE_DIR.new" "$CACHE_DIR"
	rm -rf "$tmp"
	echo "Template catalog loaded: $(ls "$CACHE_DIR" | grep -c '\.json$') template(s)."
}

# per template the highest revision this version can use, bundled or catalog
resolve_templates() {
	rm -rf "$ACTIVE_DIR.new"
	mkdir -p "$ACTIVE_DIR.new"
	for f in "$BUNDLED_DIR"/*.json "$CACHE_DIR"/*.json; do
		[ -f "$f" ] || continue
		id=$(basename "$f" .json)
		if [ -n "$(template_problems "$f" "$id")" ]; then
			echo "Template '$id' ($f) is not valid, skipped."
			continue
		fi
		if ! version_ok "$f"; then
			echo "Template '$id' from the catalog needs add-on $(jq -r .min_addon "$f") or newer, update the add-on to use it."
			continue
		fi
		active="$ACTIVE_DIR.new/$id.json"
		if [ ! -f "$active" ] || [ "$(jq .revision "$f")" -gt "$(jq .revision "$active")" ]; then
			cp "$f" "$active"
		fi
	done
	rm -rf "$ACTIVE_DIR"
	mv "$ACTIVE_DIR.new" "$ACTIVE_DIR"
}

# ------------------------------------------------------------------ config

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

# catalog template -> the settings the generator works with
NORMALIZE='{
	icon, admin_only, user_headers,
	secret_header: .fields.secret.header,
	secret_required: (.fields.secret.required // false),
	template_headers: ((.headers // {}) | to_entries | map("\(.key): \(.value)")),
	rewrite_paths: .rewrite.paths, rewrite_leads: .rewrite.leads,
	rewrite_suffixes: .rewrite.suffixes, rewrite: .rewrite.rules,
	source_charset: .charset.source, recode_skip: .charset.skip,
	revision
} | with_entries(select(.value != null))'

# writes services.conf, maps.conf, the start pages and the info for the
# integration; exits on a configuration error
generate() {
	count=$(jq -r '.services | length' "$OPTIONS_FILE" 2>/dev/null || echo 0)
	if [ "$count" -le 0 ]; then
		echo "No services configured. Add at least one entry to options.services."
		exit 1
	fi

	: > "$SERVICES_FILE"
	: > "$MAPS_FILE"
	slugs=""
	slugs_all=""
	slugs_viewer=""
	links_all=""
	links_viewer=""
	checks=""
	info_json="[]"

	i=0
	while [ "$i" -lt "$count" ]; do
		raw=$(jq -c ".services[$i]" "$OPTIONS_FILE")
		i=$((i + 1))
		name=$(printf '%s' "$raw" | jq -r '.name')
		template=$(printf '%s' "$raw" | jq -r '.template // "custom" | if . == "" then "custom" else . end')

		# a template provides defaults, the service's own settings win
		if [ "$template" = "custom" ]; then
			svc="$raw"
		elif printf '%s' "$template" | grep -Eq '^[a-z0-9-]+$' && [ -f "$ACTIVE_DIR/$template.json" ]; then
			svc=$(jq -c --argjson s "$raw" "$NORMALIZE + \$s" "$ACTIVE_DIR/$template.json")
		else
			available=$(cd "$ACTIVE_DIR" && ls *.json 2>/dev/null | sed 's/\.json$//' | tr '\n' ' ')
			echo "Service '$name': unknown template '$template'. Available: custom ${available}"
			exit 1
		fi

		url=$(printf '%s' "$svc" | jq -r '.url' | sed 's#/*$##')
		admin_only=$(printf '%s' "$svc" | jq -r '.admin_only // false')
		user_headers=$(printf '%s' "$svc" | jq -r '.user_headers // false')
		secret=$(printf '%s' "$svc" | jq -r '.secret // ""')
		secret_header=$(printf '%s' "$svc" | jq -r '.secret_header // ""')
		secret_required=$(printf '%s' "$svc" | jq -r '.secret_required // false')
		revision=$(printf '%s' "$svc" | jq -r '.revision // ""')
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

		# fixed headers: the template's, the service's "Name: value" entries and
		# the template's secret header
		headers=$(printf '%s' "$svc" | jq -c '(.template_headers // []) + (.headers // [])')
		if [ "$secret_required" = "true" ] && [ -z "$secret" ]; then
			echo "Service '$name': template '$template' needs a secret (sent as $secret_header)."
			exit 1
		fi
		if [ -n "$secret" ]; then
			if [ -n "$secret_header" ]; then
				headers=$(printf '%s' "$headers" | jq -c --arg h "$secret_header: $secret" '. + [$h]')
			else
				echo "Service '$name': template '$template' uses no secret, the secret is ignored."
			fi
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
            sub_filter_types text/plain text/xml text/css text/javascript application/javascript application/x-javascript application/json;"
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

		# legacy charset (template): recode POST answers to UTF-8, see nginx.conf
		recode=""
		source_charset=$(printf '%s' "$svc" | jq -r '.source_charset // ""')
		if [ -n "$source_charset" ]; then
			var="recode_$(printf '%s' "$slug" | tr '-' '_')"
			skip=$(printf '%s' "$svc" | jq -r '.recode_skip // ""')
			{
				echo "    map \"\$request_method \$uri\" \$$var {"
				[ -n "$skip" ] && echo "        \"~^POST .*$skip\" \"\";"
				echo "        \"~^POST \" 1;"
				echo "        default \"\";"
				echo "    }"
			} >> "$MAPS_FILE"
			recode="
            # answers to POST requests: $source_charset -> utf-8
            source_charset $source_charset;
            charset_types text/plain text/xml text/css text/javascript application/javascript application/json;
            if (\$$var) { charset utf-8; override_charset on; }"
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
            proxy_redirect ~^/(?!api/hassio_ingress/)(.*)\$ \$http_x_ingress_path/${slug}/\$1;${rewrite}${recode}
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
		info_json=$(printf '%s' "$info_json" | jq -c --arg name "$name" --arg slug "$slug" \
			--arg template "$template" --arg icon "$(printf '%s' "$svc" | jq -r '.icon // "mdi:web"')" \
			--argjson admin "$admin_only" '. + [{name: $name, slug: $slug, template: $template, icon: $icon, admin_only: $admin}]')
		info=""
		[ "$template" != custom ] && info="$info, template $template${revision:+ rev $revision}"
		[ "$admin_only" = true ] && info="$info, admin only"
		[ "$user_headers" = true ] && info="$info, user headers"
		[ "$nrules" -gt 0 ] && info="$info, $nrules rewrite rules"
		echo "Service '$name': /${slug}/ -> ${url}${info:+ (${info#, })}"
	done

	mkdir -p "$HTML_DIR"
	write_index "$HTML_DIR/index-admin.html" "$slugs_all" "$links_all"
	write_index "$HTML_DIR/index-viewer.html" "$slugs_viewer" "$links_viewer"

	# for the companion integration (sidebar entries, setup dialog), no secrets
	printf '%s' "$info_json" > "$HTML_DIR/_services.json"
	jq -s 'map({id, name, revision, tested_with, homepage, icon, admin_only, user_headers, fields, setup}
		| with_entries(select(.value != null)))' "$ACTIVE_DIR"/*.json > "$HTML_DIR/_catalog.json" 2>/dev/null ||
		echo "[]" > "$HTML_DIR/_catalog.json"
}

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

# ------------------------------------------------------- catalog refresh

GENERATED="$SERVICES_FILE $MAPS_FILE $HTML_DIR/index-admin.html $HTML_DIR/index-viewer.html $HTML_DIR/_services.json $HTML_DIR/_catalog.json"

templates_hash() {
	cat "$ACTIVE_DIR"/*.json 2>/dev/null | md5sum
}

# once a day: new catalog -> new config -> nginx reload, the old config stays
# when anything fails
refresh_loop() {
	while sleep "$REFRESH_SECONDS"; do
		fetch_catalog || continue
		before=$(templates_hash)
		rm -rf "$ACTIVE_DIR.bak"
		cp -r "$ACTIVE_DIR" "$ACTIVE_DIR.bak"
		resolve_templates
		[ "$(templates_hash)" != "$before" ] || continue
		echo "Template catalog changed, applying it."
		for f in $GENERATED; do cp "$f" "$f.bak" 2>/dev/null || true; done
		if (generate) && nginx -t -q -c "$NGINX_CONF" && nginx -s reload -c "$NGINX_CONF"; then
			echo "Template catalog applied."
		else
			echo "WARNING: the new templates do not work with this configuration, keeping the previous ones."
			for f in $GENERATED; do [ -f "$f.bak" ] && mv "$f.bak" "$f"; done
			rm -rf "$ACTIVE_DIR"
			mv "$ACTIVE_DIR.bak" "$ACTIVE_DIR"
		fi
	done
}

# ------------------------------------------------------------------ start

updates=$(jq -r 'if .catalog_updates == false then "off" else "on" end' "$OPTIONS_FILE")
if [ "$updates" = on ]; then
	fetch_catalog || true
else
	echo "Template catalog updates are off, using the templates of this add-on version."
	CACHE_DIR="$CACHE_DIR.off"
fi
resolve_templates
generate

if [ -n "${NO_EXEC:-}" ]; then
	[ -n "${SKIP_CHECKS:-}" ] || check_services
	exit 0
fi

cp "$NGINX_DIR/nginx.conf.gtpl" "$NGINX_CONF"

echo "Starting universal reverse proxy with ${count} service(s)"
check_services &
[ "$updates" = on ] && refresh_loop &
exec nginx -c "$NGINX_CONF" -g 'daemon off;'
