"""Constants for Universal Proxy."""

DOMAIN = "universal_proxy"
CONF_ADDON = "addon"

ADDON_SLUG_SUFFIX = "universal_reverse_proxy"

# Panel type the frontend uses for add-on ingress panels (was "hassio" before
# Home Assistant 2026.x). Internal frontend API, check after HA updates.
PANEL_COMPONENT = "app"

# The add-on's start page maps "/proxy-<service>" to the service path.
PANEL_PREFIX = "proxy-"
