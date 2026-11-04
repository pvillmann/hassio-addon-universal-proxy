worker_processes 1;
error_log /dev/stderr warn;
pid /var/run/nginx.pid;

events {
    worker_connections 512;
}

http {
    access_log /dev/stdout;
    absolute_redirect off;

    proxy_http_version          1.1;
    proxy_set_header            Host $http_host;
    proxy_set_header            Upgrade $http_upgrade;
    proxy_set_header            Connection "upgrade";
    proxy_set_header            X-Real-IP $remote_addr;
    proxy_set_header            X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header            X-Forwarded-Proto $scheme;
    # ingress prefix of the service, set per location (Frigate uses it as base path)
    proxy_set_header            X-Ingress-Path $service_ingress_path;
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

        set $service_ingress_path $http_x_ingress_path;

        location = /healthz {
            access_log off;
            return 200 "ok\n";
        }

        location = / {
            root /usr/share/nginx/html;
            try_files /index.html =404;
        }

        include /etc/nginx/services.conf;

        location / {
            return 404;
        }
    }
}
