FROM teddysun/xray:latest

ARG SERVER_HOST
ARG VLESS_PORT=443
ARG VLESS_SNI=www.cloudflare.com
ARG VLESS_FP=chrome
ARG VLESS_FLOW=xtls-rprx-vision
ARG VLESS_NAME=dockervpn-vless
ARG VLESS_UUID=
ARG VLESS_SHORT_ID=

ENV SERVER_HOST=${SERVER_HOST} \
    VLESS_PORT=${VLESS_PORT} \
    VLESS_SNI=${VLESS_SNI} \
    VLESS_FP=${VLESS_FP} \
    VLESS_FLOW=${VLESS_FLOW} \
    VLESS_NAME=${VLESS_NAME} \
    VLESS_UUID=${VLESS_UUID} \
    VLESS_SHORT_ID=${VLESS_SHORT_ID}

COPY docker/build-config.sh /usr/local/bin/build-config.sh
RUN chmod +x /usr/local/bin/build-config.sh && /usr/local/bin/build-config.sh
