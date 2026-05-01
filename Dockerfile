# syntax=docker/dockerfile:1.7

# Stage 1: Download phantun release binaries
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
    && unzip -j "/tmp/${PHANTUN_ARCHIVE}" phantun_client phantun_server -d /usr/local/bin \
    && chmod +x /usr/local/bin/phantun_client /usr/local/bin/phantun_server \
    && rm -f "/tmp/${PHANTUN_ARCHIVE}"

# Stage 2: Build udp2faketcp from pinned source
FROM --platform=$BUILDPLATFORM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11 AS udp2faketcp-builder

ARG TARGETARCH
ARG TARGETVARIANT
ARG UDP2FAKETCP_REF=328cdc46fd37785d6053acab4de4c330cab7d111
ARG UDP2FAKETCP_SHA256=d2def78db224f066a9684365eceff315acdc9a814a369df090f3eb1edf76b165
RUN apk add --no-cache ca-certificates curl go tar \
    && curl -fsSL "https://github.com/huangzheng2016/udp2faketcp/archive/${UDP2FAKETCP_REF}.tar.gz" -o /tmp/udp2faketcp.tar.gz \
    && printf '%s  %s\n' "$UDP2FAKETCP_SHA256" /tmp/udp2faketcp.tar.gz | sha256sum -c - \
    && mkdir -p /src \
    && tar -xzf /tmp/udp2faketcp.tar.gz -C /src --strip-components=1 \
    && rm -f /tmp/udp2faketcp.tar.gz
WORKDIR /src
RUN : "${TARGETARCH:?TARGETARCH is required}" \
    && case "${TARGETARCH}/${TARGETVARIANT}" in \
        amd64/) GOARCH=amd64 GOARM="" ;; \
        arm64/|arm64/v8) GOARCH=arm64 GOARM="" ;; \
        arm/|arm/v7) GOARCH=arm GOARM=7 ;; \
        *) echo "Unsupported TARGETARCH/TARGETVARIANT: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
      esac \
    && CGO_ENABLED=0 GOOS=linux GOARCH="$GOARCH" GOARM="$GOARM" go build -trimpath -ldflags="-s -w" -o /usr/local/bin/udp2faketcp ./bin

# Stage 3: Minimal runtime image
FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

RUN apk add --no-cache ca-certificates iproute2 iptables iptables-legacy

COPY --from=phantun-builder /usr/local/bin/phantun_client /usr/local/bin/phantun_client
COPY --from=phantun-builder /usr/local/bin/phantun_server /usr/local/bin/phantun_server
COPY --from=udp2faketcp-builder /usr/local/bin/udp2faketcp /usr/local/bin/udp2faketcp
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY LICENSE /usr/share/licenses/xtunnel/LICENSE

EXPOSE 443/tcp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof phantun_server >/dev/null || pidof phantun_client >/dev/null || pidof udp2faketcp >/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
