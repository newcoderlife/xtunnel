# syntax=docker/dockerfile:1.7

# Stage 1: Download shadowsocks-rust binaries
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

# Stage 2: Minimal runtime image
FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

RUN apk add --no-cache ca-certificates libcap \
    && addgroup -S tunnel && adduser -S -G tunnel tunnel \
    && mkdir -p /data && chown -R tunnel:tunnel /data

COPY --from=ss-builder /usr/local/bin/sslocal /usr/local/bin/sslocal
COPY --from=ss-builder /usr/local/bin/ssserver /usr/local/bin/ssserver
RUN setcap cap_net_bind_service=+ep /usr/local/bin/ssserver
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY LICENSE /usr/share/licenses/xtunnel/LICENSE

EXPOSE 443/tcp 443/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof ssserver >/dev/null || pidof sslocal >/dev/null || exit 1

USER tunnel
ENTRYPOINT ["/entrypoint.sh"]
