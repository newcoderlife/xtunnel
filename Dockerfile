# syntax=docker/dockerfile:1.7
ARG CADDY_VERSION=2.11.2
ARG CADDY_IMAGE_DIGEST=sha256:834468128c7696cec0ceea6172f7d692daf645ae51983ca76e39da54a97c570d

# Stage 1: Download Xray binary
FROM --platform=$BUILDPLATFORM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11 AS xray-builder

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

# Stage 3: Download Hysteria2 binary
FROM --platform=$BUILDPLATFORM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11 AS hysteria-builder

ARG TARGETARCH
ARG TARGETVARIANT
ARG HYSTERIA_VERSION=app/v2.8.0
RUN : "${TARGETARCH:?TARGETARCH is required}" \
    && apk add --no-cache ca-certificates curl \
    && case "${TARGETARCH}/${TARGETVARIANT}" in \
        amd64/) HYSTERIA_ARCH="amd64"; HYSTERIA_SHA256="a366e2056b04b3df85075eefbb007454409db32b1618f28e161d33eb81a6e5ca" ;; \
        arm64/|arm64/v8) HYSTERIA_ARCH="arm64"; HYSTERIA_SHA256="e65cc4114e7b160ed352b5f934cc4bf972a3827f7bd880f51fb8f77c12d91d17" ;; \
        arm/|arm/v7) HYSTERIA_ARCH="arm"; HYSTERIA_SHA256="afbadc0dc1f90d1c093109a5fb1aca22d076ae2206342f25206c124dae182573" ;; \
        *) echo "Unsupported TARGETARCH/TARGETVARIANT: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
      esac \
    && curl -fsSL "https://github.com/apernet/hysteria/releases/download/${HYSTERIA_VERSION}/hysteria-linux-${HYSTERIA_ARCH}" -o /usr/local/bin/hysteria \
    && printf '%s  %s\n' "$HYSTERIA_SHA256" /usr/local/bin/hysteria | sha256sum -c - \
    && chmod +x /usr/local/bin/hysteria

# Stage 4: Download shadowsocks-rust binaries
FROM --platform=$BUILDPLATFORM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11 AS ss-builder

ARG TARGETARCH
ARG TARGETVARIANT
ARG SSRUST_VERSION=v1.24.0
RUN : "${TARGETARCH:?TARGETARCH is required}" \
    && apk add --no-cache ca-certificates curl xz \
    && case "${TARGETARCH}/${TARGETVARIANT}" in \
        amd64/) SS_TARGET="x86_64-unknown-linux-musl"; SS_SHA256="0d84f5f350ec99396867d718f146fc3810975b2a7cd06192f158d96bdef460e7" ;; \
        arm64/|arm64/v8) SS_TARGET="aarch64-unknown-linux-musl"; SS_SHA256="e00b6551f40bb2d61adb2503909e0df6550c022372c812f3f34350510797ef2f" ;; \
        arm/|arm/v7) SS_TARGET="armv7-unknown-linux-musleabihf"; SS_SHA256="99ca0a319ef19b966f054b188e9adaede948d476a98cbd2aa9fed7c8c1d37c58" ;; \
        *) echo "Unsupported TARGETARCH/TARGETVARIANT: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
      esac \
    && SS_ARCHIVE="shadowsocks-${SSRUST_VERSION}.${SS_TARGET}.tar.xz" \
    && curl -fsSL "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SSRUST_VERSION}/${SS_ARCHIVE}" -o "/tmp/${SS_ARCHIVE}" \
    && printf '%s  %s\n' "$SS_SHA256" "/tmp/${SS_ARCHIVE}" | sha256sum -c - \
    && tar -xJf "/tmp/${SS_ARCHIVE}" -C /usr/local/bin sslocal ssserver \
    && chmod +x /usr/local/bin/sslocal /usr/local/bin/ssserver \
    && rm -f "/tmp/${SS_ARCHIVE}"

# Stage 5: Minimal runtime image
FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

RUN apk add --no-cache ca-certificates libcap openssl \
    && addgroup -S tunnel && adduser -S -G tunnel tunnel \
    && mkdir -p /data/caddy && chown -R tunnel:tunnel /data

COPY --from=xray-builder /usr/local/bin/xray /usr/local/bin/xray
COPY --from=caddy-release /usr/bin/caddy /usr/local/bin/caddy
COPY --from=hysteria-builder /usr/local/bin/hysteria /usr/local/bin/hysteria
COPY --from=ss-builder /usr/local/bin/sslocal /usr/local/bin/sslocal
COPY --from=ss-builder /usr/local/bin/ssserver /usr/local/bin/ssserver
RUN setcap cap_net_bind_service=+ep /usr/local/bin/caddy \
    && setcap cap_net_bind_service=+ep /usr/local/bin/hysteria \
    && setcap cap_net_bind_service=+ep /usr/local/bin/ssserver
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY LICENSE /usr/share/licenses/xtunnel/LICENSE

EXPOSE 443/tcp 443/udp 2000/tcp 2000/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof xray >/dev/null || pidof hysteria >/dev/null || pidof ssserver >/dev/null || pidof sslocal >/dev/null || exit 1

USER tunnel
ENTRYPOINT ["/entrypoint.sh"]
