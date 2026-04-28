FROM teddysun/xray:latest AS xray-bin

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        tini \
    && rm -rf /var/lib/apt/lists/*

COPY --from=xray-bin /usr/bin/xray /usr/local/bin/xray

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/render-config.sh /usr/local/bin/render-config.sh
COPY docker/connection-info.sh /usr/local/bin/connection-info.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/render-config.sh /usr/local/bin/connection-info.sh \
    && mkdir -p /etc/xray /run/xray /opt /var/lib/dockervpn

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
