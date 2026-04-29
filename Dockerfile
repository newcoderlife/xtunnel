# syntax=docker/dockerfile:1.7
ARG CADDY_VERSION=2.11.2
ARG CADDY_DNS_CLOUDFLARE_VERSION=v0.2.4

# Stage 1: Download Xray binary
FROM --platform=$BUILDPLATFORM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11 AS xray-builder

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

# Stage 2: Build Caddy with Cloudflare DNS-01 support
FROM --platform=$BUILDPLATFORM caddy:2.11.2-builder-alpine@sha256:113249e07ac54f02da3e395a7150124562af1a3129b0b1498ddbb39f5b3fc430 AS caddy-builder
ARG CADDY_VERSION
ARG CADDY_DNS_CLOUDFLARE_VERSION
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eux; \
    export CGO_ENABLED=0 GOOS="${TARGETOS:-linux}" GOARCH="${TARGETARCH}"; \
    case "${TARGETARCH}/${TARGETVARIANT}" in \
        arm/v7) export GOARM=7 ;; \
        arm/v6) export GOARM=6 ;; \
    esac; \
    xcaddy build "v${CADDY_VERSION}" --output /usr/bin/caddy \
    --with "github.com/caddy-dns/cloudflare@${CADDY_DNS_CLOUDFLARE_VERSION}"

# Stage 3: Minimal runtime image
FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

RUN apk add --no-cache ca-certificates libcap \
    && addgroup -S tunnel && adduser -S -G tunnel tunnel \
    && mkdir -p /data/caddy && chown -R tunnel:tunnel /data

COPY --from=xray-builder /usr/local/bin/xray /usr/local/bin/xray
COPY --from=xray-builder /usr/local/share/xray /usr/local/share/xray
COPY --from=caddy-builder /usr/bin/caddy /usr/local/bin/caddy
RUN setcap cap_net_bind_service=+ep /usr/local/bin/xray \
    && setcap cap_net_bind_service=+ep /usr/local/bin/caddy
COPY --chmod=755 entrypoint.sh /entrypoint.sh

EXPOSE 443/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof xray >/dev/null && { [ -n "${PEERS:-}" ] || pidof caddy >/dev/null; } || exit 1

USER tunnel
ENTRYPOINT ["/entrypoint.sh"]
