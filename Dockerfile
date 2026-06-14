# syntax=docker/dockerfile:1.7
ARG CADDY_VERSION=2.11.2
ARG CADDY_IMAGE_DIGEST=sha256:834468128c7696cec0ceea6172f7d692daf645ae51983ca76e39da54a97c570d

# Stage 1: Download Xray binary
FROM --platform=$BUILDPLATFORM alpine:3.24@sha256:a2d49ea686c2adfe3c992e47dc3b5e7fa6e6b5055609400dc2acaeb241c829f4 AS xray-builder

ARG TARGETARCH
ARG TARGETVARIANT
ARG XRAY_VERSION=v26.3.27
RUN : "${TARGETARCH:?TARGETARCH is required}" \
    && apk add --no-cache ca-certificates curl unzip \
    && case "${TARGETARCH}/${TARGETVARIANT}" in \
        amd64/) XRAY_ARCH="64"; XRAY_SHA256="23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae" ;; \
        arm64/|arm64/v8) XRAY_ARCH="arm64-v8a"; XRAY_SHA256="4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c" ;; \
        arm/|arm/v7) XRAY_ARCH="arm32-v7a"; XRAY_SHA256="c7265ae13c63ca0241a037df4ef960ad37938c8a67d984cc08834b2cfdf5654b" ;; \
        *) echo "Unsupported TARGETARCH/TARGETVARIANT: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
      esac \
    && curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip" -o /tmp/xray.zip \
    && printf '%s  %s\n' "$XRAY_SHA256" /tmp/xray.zip | sha256sum -c - \
    && unzip -j /tmp/xray.zip xray -d /usr/local/bin \
    && chmod +x /usr/local/bin/xray \
    && rm -f /tmp/xray.zip

# Stage 2: Use official Caddy release binary
FROM --platform=$TARGETPLATFORM caddy:${CADDY_VERSION}-alpine@${CADDY_IMAGE_DIGEST} AS caddy-release
ARG CADDY_VERSION

# Stage 3: Minimal runtime image
FROM alpine:3.24@sha256:a2d49ea686c2adfe3c992e47dc3b5e7fa6e6b5055609400dc2acaeb241c829f4

RUN apk add --no-cache ca-certificates libcap \
    && addgroup -S tunnel && adduser -S -G tunnel tunnel \
    && mkdir -p /data/caddy && chown -R tunnel:tunnel /data

COPY --from=xray-builder /usr/local/bin/xray /usr/local/bin/xray
COPY --from=caddy-release /usr/bin/caddy /usr/local/bin/caddy
RUN setcap cap_net_bind_service=+ep /usr/local/bin/caddy
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY LICENSE /usr/share/licenses/xtunnel/LICENSE

EXPOSE 443

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof xray >/dev/null && { [ -n "${PEERS:-}" ] || pidof caddy >/dev/null; } || exit 1

USER tunnel
ENTRYPOINT ["/entrypoint.sh"]
