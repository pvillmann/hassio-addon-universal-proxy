FROM ghcr.io/hassio-addons/base:21.0.0

# set by the Supervisor, templates from the catalog may need a minimum version
ARG BUILD_VERSION
ENV ADDON_VERSION=${BUILD_VERSION}

RUN apk add --no-cache nginx gettext curl jq

COPY nginx.conf.gtpl /etc/nginx/nginx.conf.gtpl
COPY proxy_common.conf /etc/nginx/proxy_common.conf
COPY latin1.conf /etc/nginx/latin1.conf
COPY templates /etc/nginx/templates
COPY validate.jq /etc/nginx/validate.jq
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD curl --silent -o /dev/null -w '%{http_code}' http://localhost:8099/healthz | grep -q 200 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
