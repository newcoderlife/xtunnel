# Server 配置示例

server 模式不设置 `PEERS`。下面按这个约定写：

- `ether1` 是 WAN。
- `veth-xtunnel` 和 `vxlan-xtunnel` 都算 LAN。
- RouterOS 是 `172.18.0.1`，xtunnel 容器是 `172.18.0.2`。
- 外置存储是 `disk1`。

把域名、Cloudflare token 和两个 UUID 换成自己的，然后按顺序执行。

## RouterOS Container

如果还没启用 container，先执行一次：

```routeros
/system/device-mode/update container=yes
```

创建接口和容器：

```routeros
/interface/list/add name=WAN
/interface/list/add name=LAN
/interface/list/member/add list=WAN interface=ether1

/interface/veth/add name=veth-xtunnel address=172.18.0.2/24 gateway=172.18.0.1
/ip/address/add address=172.18.0.1/24 interface=veth-xtunnel
/interface/list/member/add list=LAN interface=veth-xtunnel

/interface/vxlan/add name=vxlan-xtunnel vni=100 port=4789
/interface/vxlan/vteps/add interface=vxlan-xtunnel remote-ip=172.18.0.2
/interface/list/member/add list=LAN interface=vxlan-xtunnel

/container/config/set registry-url=https://ghcr.io tmpdir=disk1/tmp
/container/envs/add list=ENV_XTUNNEL key=DOMAIN value="s1.example.com"
/container/envs/add list=ENV_XTUNNEL key=VTEP_IP value="172.18.0.2"
/container/envs/add list=ENV_XTUNNEL key=CLOUDFLARE_API_TOKEN value="cf_api_token_here"
/container/envs/add list=ENV_XTUNNEL key=FORWARD_UUID value="00000000-0000-4000-8000-000000000001"
/container/envs/add list=ENV_XTUNNEL key=REVERSE_UUID value="00000000-0000-4000-8000-000000000002"
/container/add remote-image=newcoderlife/xtunnel:latest interface=veth-xtunnel root-dir=disk1/xtunnel/root envlist=ENV_XTUNNEL name=xtunnel user=0:0 dns=1.1.1.1 start-on-boot=yes logging=yes
/container/start [find where name="xtunnel"]
```

这里不挂 `/data`，生成配置和 Caddy 证书会保存在 `root-dir` 里的 `/data` 路径下。只要不删除这个 container/root-dir，重启后还在。

## Firewall / NAT

如果你已有 firewall，只把这些规则放到最终 drop 前面即可。

```routeros
/ip/firewall/filter/add chain=forward action=accept connection-nat-state=dstnat protocol=udp dst-address=172.18.0.2 dst-port=443 in-interface-list=WAN comment="xtunnel H3"
/ip/firewall/filter/add chain=forward action=accept in-interface-list=LAN

/ip/firewall/nat/add chain=dstnat action=dst-nat protocol=udp dst-port=443 in-interface-list=WAN to-addresses=172.18.0.2 to-ports=443
/ip/firewall/nat/add chain=srcnat action=masquerade in-interface-list=LAN out-interface-list=WAN

/ip/firewall/mangle/add chain=forward action=change-mss protocol=tcp tcp-flags=syn new-mss=clamp-to-pmtu out-interface=vxlan-xtunnel
/ip/firewall/mangle/add chain=forward action=change-mss protocol=tcp tcp-flags=syn new-mss=clamp-to-pmtu in-interface=vxlan-xtunnel
```

UDP full cone 可选；需要时把下面两条加在 `masquerade` 前面，UDP 443 的 `dst-nat` 保持在 generic `endpoint-independent-nat` 前面：

```routeros
/ip/firewall/nat/add chain=srcnat action=endpoint-independent-nat protocol=udp in-interface-list=LAN out-interface-list=WAN
/ip/firewall/nat/add chain=dstnat action=endpoint-independent-nat protocol=udp in-interface-list=WAN
```

## Docker 参考

```sh
docker run -d \
  --name xtunnel \
  --restart unless-stopped \
  -p 443:443/udp \
  -v xtunnel:/data \
  -e DOMAIN=s1.example.com \
  -e VTEP_IP=172.18.0.2 \
  -e CLOUDFLARE_API_TOKEN=cf_api_token_here \
  -e FORWARD_UUID=00000000-0000-4000-8000-000000000001 \
  -e REVERSE_UUID=00000000-0000-4000-8000-000000000002 \
  ghcr.io/newcoderlife/xtunnel:latest
```

## 可选项

自定义 path：

```routeros
/container/envs/add list=ENV_XTUNNEL key=XHTTP_PATH value="/vxlan"
```
