#!/bin/bash
# WireGuard VPN 一键安装脚本 - 适用于 Ubuntu 22.04/24.04 (AWS EC2)
# 用法: sudo bash wireguard-setup.sh
set -e

apt update && apt install -y wireguard qrencode

# 自动检测默认网卡名 (AWS 上可能是 eth0 / ens5 / enX0)
NIC=$(ip route show default | awk '{print $5}' | head -n1)
echo "Detected network interface: $NIC"

# 生成服务端和客户端密钥
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
cd /etc/wireguard
wg genkey | tee server_private.key | wg pubkey > server_public.key
wg genkey | tee client_private.key | wg pubkey > client_public.key
chmod 600 *.key

SERVER_PRIVATE=$(cat server_private.key)
CLIENT_PUBLIC=$(cat client_public.key)

# 服务端配置
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $NIC -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUBLIC
AllowedIPs = 10.0.0.2/32
EOF
chmod 600 /etc/wireguard/wg0.conf

# 开启 IP 转发
sed -i 's/^#*net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# 启动并开机自启
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

# 生成客户端配置
SERVER_PUBLIC=$(cat server_public.key)
CLIENT_PRIVATE=$(cat client_private.key)
PUBLIC_IP=$(curl -s https://checkip.amazonaws.com)

cat > /home/ubuntu/client.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE
Address = 10.0.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUBLIC
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 /home/ubuntu/client.conf
chown ubuntu:ubuntu /home/ubuntu/client.conf 2>/dev/null || true

echo ""
echo "================= 客户端配置 ================="
cat /home/ubuntu/client.conf
echo ""
echo "================= 手机扫码导入 ================="
qrencode -t ansiutf8 < /home/ubuntu/client.conf
echo ""
echo "完成! 客户端配置文件位于 /home/ubuntu/client.conf"
