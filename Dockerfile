# syntax=docker/dockerfile:1.7

# Stage 1: Download Phantun binaries
FROM --platform=$BUILDPLATFORM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11 AS phantun-builder

ARG TARGETARCH
ARG TARGETVARIANT
ARG PHANTUN_VERSION=v0.8.1
RUN : "${TARGETARCH:?TARGETARCH is required}" \
    && apk add --no-cache ca-certificates curl unzip \
    && case "${TARGETARCH}/${TARGETVARIANT}" in \
        amd64/) PHANTUN_TARGET="x86_64-unknown-linux-musl"; PHANTUN_SHA256="0cf40f0ac48411f8ced94ce0afd617105c6b9a69ad8db137c3b1e4d184d6fcdb" ;; \
        arm64/|arm64/v8) PHANTUN_TARGET="aarch64-unknown-linux-musl"; PHANTUN_SHA256="e3f2336b5173df071c8931b5e0e3d44c57453da0456007ed459ed369610c91fa" ;; \
        arm/|arm/v7) PHANTUN_TARGET="armv7-unknown-linux-musleabihf"; PHANTUN_SHA256="71f16f7a18c2ac98f3fec482d99a0e69540966cb867309f615617567d5d2f30f" ;; \
        *) echo "Unsupported TARGETARCH/TARGETVARIANT: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
      esac \
    && PHANTUN_ARCHIVE="phantun_${PHANTUN_TARGET}.zip" \
    && curl -fsSL "https://github.com/dndx/phantun/releases/download/${PHANTUN_VERSION}/${PHANTUN_ARCHIVE}" -o "/tmp/${PHANTUN_ARCHIVE}" \
    && printf '%s  %s\n' "$PHANTUN_SHA256" "/tmp/${PHANTUN_ARCHIVE}" | sha256sum -c - \
    && unzip "/tmp/${PHANTUN_ARCHIVE}" -d /usr/local/bin \
    && chmod +x /usr/local/bin/phantun_client /usr/local/bin/phantun_server \
    && rm -f "/tmp/${PHANTUN_ARCHIVE}"

# Stage 2: Minimal runtime image
FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

RUN apk add --no-cache ca-certificates iptables

COPY --from=phantun-builder /usr/local/bin/phantun_client /usr/local/bin/phantun_client
COPY --from=phantun-builder /usr/local/bin/phantun_server /usr/local/bin/phantun_server
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY LICENSE /usr/share/licenses/xtunnel/LICENSE

ENV RUST_LOG=info
EXPOSE 51820/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof phantun_client >/dev/null || pidof phantun_server >/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
