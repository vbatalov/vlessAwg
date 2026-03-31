FROM teddysun/xray:latest AS xray-bin

FROM debian:bookworm-slim

ARG TRUSTTUNNEL_CLIENT_VERSION=v1.0.31

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        tini \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) tt_arch="linux-x86_64" ;; \
      arm64) tt_arch="linux-aarch64" ;; \
      *) echo "unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    pkg="trusttunnel_client-${TRUSTTUNNEL_CLIENT_VERSION}-${tt_arch}.tar.gz"; \
    url="https://github.com/TrustTunnel/TrustTunnelClient/releases/download/${TRUSTTUNNEL_CLIENT_VERSION}/${pkg}"; \
    curl -fsSL "${url}" -o /tmp/trusttunnel_client.tgz; \
    tar -xzf /tmp/trusttunnel_client.tgz -C /tmp; \
    install -m 0755 /tmp/trusttunnel_client-${TRUSTTUNNEL_CLIENT_VERSION}-${tt_arch}/trusttunnel_client /usr/local/bin/trusttunnel_client; \
    rm -rf /tmp/trusttunnel_client.tgz /tmp/trusttunnel_client-${TRUSTTUNNEL_CLIENT_VERSION}-${tt_arch}

COPY --from=xray-bin /usr/bin/xray /usr/local/bin/xray

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/render-config.sh /usr/local/bin/render-config.sh
COPY docker/connection-info.sh /usr/local/bin/connection-info.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/render-config.sh /usr/local/bin/connection-info.sh \
    && mkdir -p /etc/xray /config /run/xray /opt /var/lib/dockervpn

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
