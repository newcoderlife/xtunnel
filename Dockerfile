FROM debian:latest

RUN apt update && apt install -y ca-certificates caddy curl unzip ncurses-bin && rm -rf /var/lib/apt/lists/*
RUN touch /.dockerenv && printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/systemctl && chmod +x /usr/local/bin/systemctl
RUN bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
