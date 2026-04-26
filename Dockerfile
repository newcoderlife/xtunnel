# Stage 1: Download Xray binary
FROM alpine:3.21 AS builder

ARG TARGETARCH=amd64
ARG TARGETVARIANT=
ARG XRAY_VERSION=v26.3.27
RUN apk add --no-cache ca-certificates curl unzip \
    && case "${TARGETARCH}/${TARGETVARIANT}" in \
        amd64/) XRAY_ARCH="64"; XRAY_SHA256="23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae" ;; \
        arm64/|arm64/v8) XRAY_ARCH="arm64-v8a"; XRAY_SHA256="4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c" ;; \
        arm/|arm/v7) XRAY_ARCH="arm32-v7a"; XRAY_SHA256="c7265ae13c63ca0241a037df4ef960ad37938c8a67d984cc08834b2cfdf5654b" ;; \
        *) echo "Unsupported TARGETARCH/TARGETVARIANT: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
      esac \
    && curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip \
    && printf '%s  %s\n' "$XRAY_SHA256" /tmp/xray.zip | sha256sum -c - \
    && mkdir -p /usr/local/share/xray \
    && unzip -j /tmp/xray.zip xray -d /usr/local/bin \
    && unzip -j /tmp/xray.zip geoip.dat geosite.dat -d /usr/local/share/xray \
    && chmod +x /usr/local/bin/xray \
    && rm -f /tmp/xray.zip

# Stage 2: Minimal runtime image
FROM alpine:3.21

RUN apk add --no-cache ca-certificates caddy libcap \
    && addgroup -S tunnel && adduser -S -G tunnel tunnel \
    && setcap cap_net_bind_service=+ep /usr/sbin/caddy \
    && mkdir -p /data/caddy && chown -R tunnel:tunnel /data

COPY --from=builder /usr/local/bin/xray /usr/local/bin/xray
COPY --from=builder /usr/local/share/xray /usr/local/share/xray
RUN setcap cap_net_bind_service=+ep /usr/local/bin/xray
COPY --chmod=755 entrypoint.sh /entrypoint.sh

VOLUME /data
EXPOSE 80 443 4789/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof xray >/dev/null && { [ -n "${PEERS:-}" ] || pidof caddy >/dev/null; } || exit 1

USER tunnel
ENTRYPOINT ["/entrypoint.sh"]
