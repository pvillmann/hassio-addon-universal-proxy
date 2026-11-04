#!/bin/sh
# Checks every template in a directory: the rules of validate.jq, then builds
# the nginx config with one service per template and runs nginx -t.
#   sh tools/check-templates.sh <templates dir>
# Used by CI on main and on the catalog branch. Needs nginx and jq.
set -eu

templates=$(cd "$1" && pwd)
addon=$(cd "$(dirname "$0")/../universal-reverse-proxy" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failed=0
for f in "$templates"/*.json; do
	[ -f "$f" ] || continue
	id=$(basename "$f" .json)
	problems=$(jq -r --arg id "$id" -f "$addon/validate.jq" "$f" 2>&1) || problems="not valid JSON: $problems"
	if [ -n "$problems" ]; then
		echo "FAIL $id:"
		printf '%s\n' "$problems" | sed 's/^/  - /'
		failed=1
	else
		echo "ok   $id (revision $(jq .revision "$f"))"
	fi
done
[ "$failed" = 0 ] || exit 1

# one service per template, with a dummy secret where one is needed
jq -s '{catalog_updates: false, services: map({
	name: .id, template: .id,
	url: (.fields.url.example // "http://127.0.0.1:8080")
} + (if .fields.secret then {secret: "ci-dummy-secret"} else {} end))}' "$templates"/*.json > "$work/options.json"

mkdir -p "$work/nginx" "$work/html"
cp "$addon/proxy_common.conf" "$addon/latin1.conf" "$addon/validate.jq" "$work/nginx/"
sed "s#/etc/nginx#$work/nginx#g; s#/usr/share/nginx/html#$work/html#g; s#/var/run/nginx.pid#$work/nginx.pid#" \
	"$addon/nginx.conf.gtpl" > "$work/nginx/nginx.conf"
env OPTIONS_FILE="$work/options.json" NGINX_DIR="$work/nginx" HTML_DIR="$work/html" \
	BUNDLED_DIR="$templates" CACHE_DIR="$work/none" ADDON_VERSION="" NO_EXEC=1 SKIP_CHECKS=1 \
	sh "$addon/entrypoint.sh"
nginx -t -c "$work/nginx/nginx.conf"
