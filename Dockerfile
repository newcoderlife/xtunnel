# syntax=docker/dockerfile:1.7

# Stage 1: Download Hysteria2 binary
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

# Stage 2: Minimal runtime image
FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

RUN apk add --no-cache ca-certificates libcap openssl \
    && addgroup -S tunnel && adduser -S -G tunnel tunnel \
    && mkdir -p /data && chown -R tunnel:tunnel /data

COPY --from=hysteria-builder /usr/local/bin/hysteria /usr/local/bin/hysteria
RUN setcap cap_net_bind_service=+ep /usr/local/bin/hysteria
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY LICENSE /usr/share/licenses/xtunnel/LICENSE

EXPOSE 443/udp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof hysteria >/dev/null || exit 1

USER tunnel
ENTRYPOINT ["/entrypoint.sh"]
