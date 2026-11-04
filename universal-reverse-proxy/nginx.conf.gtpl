worker_processes 1;
error_log /dev/stderr warn;
pid /var/run/nginx.pid;

events {
    worker_connections 512;
}

http {
    access_log /dev/stdout;
    absolute_redirect off;

    # The Supervisor sends the Home Assistant user's groups with every ingress
    # request and drops any client-supplied X-Remote-User-* header, so this
    # cannot be spoofed by the browser.
    map $http_x_remote_user_groups $ha_is_admin {
        default                          0;
        "~(^|,)system-admin(,|$)"        1;
    }
    map $ha_is_admin $ha_role {
        1       admin;
        default viewer;
    }

    # The Supervisor drops the charset from Content-Type. Templates of apps with
    # a legacy charset recode their AJAX (POST) answers to UTF-8, which browsers
    # assume when no charset is given (pages keep their <meta charset>).
    include /etc/nginx/latin1.conf;
    include /etc/nginx/maps.conf;

    proxy_http_version          1.1;
    proxy_read_timeout          600s;
    proxy_send_timeout          600s;
    proxy_connect_timeout       10s;
    proxy_buffering             off;

    # strip X-Frame-Options and frame-ancestors from upstream to allow ingress embedding
    proxy_hide_header           X-Frame-Options;
    proxy_hide_header           Content-Security-Policy;

    server {
        listen 8099;
        server_name _;

        # only the Supervisor ingress gateway (like the Frigate proxy) and the healthcheck
        allow 172.30.32.2;
        allow 127.0.0.1;
        deny  all;

        location = /healthz {
            access_log off;
            return 200 "ok\n";
        }

        # admins get the full service list, everyone else without admin-only services
        location = / {
            root /usr/share/nginx/html;
            try_files /index-$ha_role.html =404;
        }

        include /etc/nginx/services.conf;

        location / {
            return 404;
        }
    }
}
