FROM golang:1.24-bookworm AS awg-go-builder

ARG AMNEZIAWG_GO_REF=master

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/amneziawg-go
RUN git clone --depth=1 --branch "${AMNEZIAWG_GO_REF}" https://github.com/amnezia-vpn/amneziawg-go.git . \
    && make

FROM debian:bookworm-slim AS awg-tools-builder

ARG AMNEZIAWG_TOOLS_REF=v1.0.20250903

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git build-essential bash pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src/amneziawg-tools
RUN git clone --depth=1 --branch "${AMNEZIAWG_TOOLS_REF}" https://github.com/amnezia-vpn/amneziawg-tools.git . \
    && make -C src \
    && make -C src install DESTDIR=/opt/awg-root PREFIX=/usr WITH_WGQUICK=yes WITH_SYSTEMDUNITS=no

FROM teddysun/xray:latest AS xray-bin

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        iproute2 \
        iptables \
        tini \
        dante-server \
        passwd \
        procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=xray-bin /usr/bin/xray /usr/local/bin/xray
COPY --from=awg-go-builder /src/amneziawg-go/amneziawg-go /usr/local/bin/amneziawg-go
COPY --from=awg-tools-builder /opt/awg-root/ /

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/render-config.sh /usr/local/bin/render-config.sh
COPY docker/connection-info.sh /usr/local/bin/connection-info.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/render-config.sh /usr/local/bin/connection-info.sh \
    && mkdir -p /etc/xray /config /run/xray /opt

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
