# Home Assistant Add-on: Universal Reverse Proxy

Ingress proxy for several externally hosted web apps. Each app gets its own sidebar entry (needs the companion integration "Universal Proxy" from the same repository). Does not run the apps itself.

```yaml
services:
  - name: evcc
    template: evcc
    url: http://192.168.1.50:7070
  - name: Grafana
    url: http://192.168.1.60:3000
    icon: mdi:chart-line
```

Templates for known apps come from a catalog that is updated without add-on updates (currently `evcc`, `frigate`, `openccu`). Everything else is `custom`.

See the Documentation tab for setup, security notes and limits.
