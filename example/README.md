# xtunnel examples

这个目录放 `xtunnel` 的部署示例，所有示例都只通过环境变量配置容器。容器启动时会重新生成 `/data/Caddyfile`、`/data/server.json` 或 `/data/client.json`，不需要也不支持挂载自定义 Xray/Caddy 配置。

- [server.md](server.md)：server 侧 RouterOS Container 配置、变量说明和 Docker 参考命令。
- [client.md](client.md)：client 侧 RouterOS Container 配置、单 server、多 server 和 Docker 参考命令。

示例里的 IP、域名、UUID 和 Cloudflare API token 都需要替换成你自己的值。RouterOS 的容器 veth 也必须实际拥有示例中的 VTEP IP，否则 Xray 无法绑定本地 UDP 入口或按指定源地址发包。server 只需要开放 `443/udp`，xtunnel 只使用 HTTP/3 over QUIC 承载公网 tunnel。
