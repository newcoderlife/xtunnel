FROM debian:latest

RUN apt update && apt install -y ca-certificates caddy curl && rm -rf /var/lib/apt/lists/*
RUN touch /.dockerenv
RUN bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
