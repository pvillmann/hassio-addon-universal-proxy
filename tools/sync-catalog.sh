#!/bin/sh
# Before a release: take the current templates from the catalog branch into
# the add-on, they are its fallback when the catalog can't be loaded.
set -eu
cd "$(dirname "$0")/.."
git fetch -q origin catalog
dest=universal-reverse-proxy/templates
rm -f "$dest"/*.json
git archive origin/catalog templates | tar -x -C universal-reverse-proxy
sh tools/check-templates.sh "$dest"
git status --short "$dest"
