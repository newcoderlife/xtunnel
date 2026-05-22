# syntax=docker/dockerfile:1.7

# Stage 1: Build udp2faketcp
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS udp2faketcp-builder

ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
ARG UDP2FAKETCP_VERSION=v1.1.3
RUN : "${TARGETARCH:?TARGETARCH is required}" \
    && : "${TARGETOS:=linux}" \
    && apk add --no-cache ca-certificates \
    && case "${TARGETARCH}/${TARGETVARIANT}" in \
        amd64/) GOARCH=amd64; GOARM="" ;; \
        arm64/|arm64/v8) GOARCH=arm64; GOARM="" ;; \
        arm/|arm/v7) GOARCH=arm; GOARM=7 ;; \
        *) echo "Unsupported TARGETARCH/TARGETVARIANT: ${TARGETARCH}/${TARGETVARIANT}" >&2; exit 1 ;; \
      esac \
    && mkdir -p /src /out \
    && cd /src \
    && go mod init xtunnel-udp2faketcp-build \
    && go get "github.com/huangzheng2016/udp2faketcp@${UDP2FAKETCP_VERSION}" \
    && CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$GOARCH" GOARM="$GOARM" \
      go build -o /out/udp2faketcp github.com/huangzheng2016/udp2faketcp/bin

# Stage 2: Minimal runtime image
FROM alpine:3.23@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

RUN apk add --no-cache ca-certificates

COPY --from=udp2faketcp-builder /out/udp2faketcp /usr/local/bin/udp2faketcp
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY LICENSE /usr/share/licenses/xtunnel/LICENSE

ENV UDP2FAKETCP_MODE=client
EXPOSE 51820/udp
EXPOSE 51820/tcp

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pidof udp2faketcp >/dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
