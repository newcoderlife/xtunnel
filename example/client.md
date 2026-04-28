# Client 配置示例

client 模式设置 `PEERS`。下面按这个约定写：

- `ether1` 是 WAN。
- `veth-xtunnel` 和 `vxlan-xtunnel` 都算 LAN。
- RouterOS 是 `172.18.0.1`，xtunnel 容器是 `172.18.0.2`。
- 外置存储是 `disk1`。

把 server 域名和 UUID 换成自己的，然后按顺序执行。

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
/container/envs/add list=ENV_XTUNNEL key=PEERS value="s1"
/container/envs/add list=ENV_XTUNNEL key=S1_DOMAIN value="s1.example.com"
/container/envs/add list=ENV_XTUNNEL key=S1_FORWARD_UUID value="00000000-0000-4000-8000-000000000001"
/container/envs/add list=ENV_XTUNNEL key=S1_REVERSE_UUID value="00000000-0000-4000-8000-000000000002"
/container/envs/add list=ENV_XTUNNEL key=S1_LOCAL_VTEP_IP value="172.18.0.2"
/container/add remote-image=newcoderlife/xtunnel:latest interface=veth-xtunnel root-dir=disk1/xtunnel/root envlist=ENV_XTUNNEL name=xtunnel user=0:0 dns=1.1.1.1 start-on-boot=yes logging=yes
/container/start [find where name="xtunnel"]
```

这里不挂 `/data`，生成配置会保存在 `root-dir` 里的 `/data` 路径下。只要不删除这个 container/root-dir，重启后还在。

## Firewall / NAT

如果你已有 firewall，只把这些规则放到最终 drop 前面即可。

```routeros
/ip/firewall/filter/add chain=forward action=accept in-interface-list=LAN

/ip/firewall/nat/add chain=srcnat action=masquerade in-interface-list=LAN out-interface-list=WAN

/ip/firewall/mangle/add chain=forward action=change-mss protocol=tcp tcp-flags=syn new-mss=clamp-to-pmtu out-interface=vxlan-xtunnel
/ip/firewall/mangle/add chain=forward action=change-mss protocol=tcp tcp-flags=syn new-mss=clamp-to-pmtu in-interface=vxlan-xtunnel
```

UDP full cone 可选；需要时把下面两条加在 `masquerade` 前面：

```routeros
/ip/firewall/nat/add chain=srcnat action=endpoint-independent-nat protocol=udp in-interface-list=LAN out-interface-list=WAN
/ip/firewall/nat/add chain=dstnat action=endpoint-independent-nat protocol=udp in-interface-list=WAN
```

## 多 server

多 server 时，把上面的 veth 和 env 改成多个本地 VTEP IP、多个 peer：

```routeros
/interface/veth/add name=veth-xtunnel address=172.18.0.2/24,172.18.0.3/24 gateway=172.18.0.1

/container/envs/add list=ENV_XTUNNEL key=PEERS value="s1,hk-1"
/container/envs/add list=ENV_XTUNNEL key=S1_DOMAIN value="s1.example.com"
/container/envs/add list=ENV_XTUNNEL key=S1_FORWARD_UUID value="00000000-0000-4000-8000-000000000001"
/container/envs/add list=ENV_XTUNNEL key=S1_REVERSE_UUID value="00000000-0000-4000-8000-000000000002"
/container/envs/add list=ENV_XTUNNEL key=S1_LOCAL_VTEP_IP value="172.18.0.2"
/container/envs/add list=ENV_XTUNNEL key=HK_1_DOMAIN value="hk-1.example.com"
/container/envs/add list=ENV_XTUNNEL key=HK_1_FORWARD_UUID value="00000000-0000-4000-8000-000000000003"
/container/envs/add list=ENV_XTUNNEL key=HK_1_REVERSE_UUID value="00000000-0000-4000-8000-000000000004"
/container/envs/add list=ENV_XTUNNEL key=HK_1_LOCAL_VTEP_IP value="172.18.0.3"

/interface/vxlan/vteps/add interface=vxlan-xtunnel remote-ip=172.18.0.3
```

## Docker 参考

```sh
docker run -d \
  --name xtunnel \
  --restart unless-stopped \
  -v xtunnel:/data \
  -e PEERS=s1 \
  -e S1_DOMAIN=s1.example.com \
  -e S1_FORWARD_UUID=00000000-0000-4000-8000-000000000001 \
  -e S1_REVERSE_UUID=00000000-0000-4000-8000-000000000002 \
  -e S1_LOCAL_VTEP_IP=172.18.0.2 \
  ghcr.io/newcoderlife/xtunnel:latest
```

## 可选项

自定义 path 或 SNI：

```routeros
/container/envs/add list=ENV_XTUNNEL key=S1_XHTTP_PATH value="/vxlan"
/container/envs/add list=ENV_XTUNNEL key=S1_SNI value="edge.example.com"
```
