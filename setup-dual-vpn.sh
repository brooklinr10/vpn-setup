#!/bin/bash
# ============================================================
#  Hysteria2 + VLESS-Reality 双协议一键脚本 (sing-box)
#  适用: Ubuntu 22.04/24.04, Debian 11/12  (AWS 美西 EC2)
#  用法: sudo bash setup-dual-vpn.sh
# ============================================================
set -e

# ---------- 可调参数 ----------
REALITY_PORT=443            # Reality 监听端口 (TCP)
REALITY_SNI="www.microsoft.com"   # Reality 伪装站点 (需支持 TLS1.3/HTTP2)
HYSTERIA_PORT=8443          # Hysteria2 真实监听端口 (UDP)
HOP_START=20000             # 端口跳跃起始 (UDP 范围，用于抗电信 QoS)
HOP_END=50000               # 端口跳跃结束
FINGERPRINT="chrome"

echo "[1/6] 检测环境..."
NIC=$(ip route show default | awk '{print $5}' | head -n1)
PUBLIC_IP=$(curl -s https://checkip.amazonaws.com || ip -4 addr show scope global | awk '/inet/{print $2}' | cut -d/ -f1 | head -n1)
echo "      网卡: $NIC   公网IP: $PUBLIC_IP"

echo "[2/6] 安装依赖..."
apt update -qq
apt install -y -qq curl qrencode iptables iproute2

echo "[3/6] 安装 sing-box..."
VERSION=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep -Po '"tag_name":\s*"\K[^"]+')
VERSION=${VERSION#v}
curl -Lo /tmp/sing-box.deb "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box_${VERSION}_linux_amd64.deb"
dpkg -i /tmp/sing-box.deb >/dev/null
echo "      已安装 sing-box v${VERSION}"

echo "[4/6] 生成密钥与证书..."
UUID=$(sing-box generate uuid)
REALITY_KEYPAIR=$(sing-box generate reality-keypair)
REALITY_PRIVATE=$(echo "$REALITY_KEYPAIR" | awk '/PrivateKey/{print $2}')
REALITY_PUBLIC=$(echo "$REALITY_KEYPAIR"  | awk '/PublicKey/{print $2}')
SHORT_ID=$(openssl rand -hex 8 2>/dev/null || head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
HY_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)
OBFS_PASSWORD=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)

mkdir -p /etc/sing-box

# 生成 Hysteria2 自签名证书（sing-box v1.14+ 要求 Hysteria2 入站必须显式配置 TLS）
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout /etc/sing-box/hysteria.key \
  -out /etc/sing-box/hysteria.crt \
  -subj "/CN=www.microsoft.com" >/dev/null 2>&1
chmod 600 /etc/sing-box/hysteria.key

echo "[5/6] 写入服务端配置..."
cat > /etc/sing-box/config.json <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "users": [ { "uuid": "${UUID}", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${REALITY_SNI}", "server_port": 443 },
          "private_key": "${REALITY_PRIVATE}",
          "short_id": [ "${SHORT_ID}" ]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "::",
      "listen_port": ${HYSTERIA_PORT},
      "users": [ { "password": "${HY_PASSWORD}" } ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/hysteria.crt",
        "key_path": "/etc/sing-box/hysteria.key"
      },
      "obfs": { "type": "salamander", "password": "${OBFS_PASSWORD}" },
      "masquerade": "https://www.bing.com/",
      "ignore_client_bandwidth": false
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF

# 端口跳跃: 把 UDP 范围流量重定向到真实 Hysteria2 端口
iptables -t nat -A PREROUTING -i "$NIC" -p udp --dport ${HOP_START}:${HOP_END} -j REDIRECT --to-ports ${HYSTERIA_PORT}
cat > /etc/systemd/system/hysteria-port-hop.service <<EOF
[Unit]
Description=Hysteria2 port hopping iptables rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables -t nat -A PREROUTING -i ${NIC} -p udp --dport ${HOP_START}:${HOP_END} -j REDIRECT --to-ports ${HYSTERIA_PORT}
ExecStop=/sbin/iptables -t nat -D PREROUTING -i ${NIC} -p udp --dport ${HOP_START}:${HOP_END} -j REDIRECT --to-ports ${HYSTERIA_PORT}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable hysteria-port-hop >/dev/null 2>&1 || true

echo "[6/6] 启动服务..."
systemctl enable sing-box >/dev/null
systemctl restart sing-box
sleep 1
systemctl is-active sing-box >/dev/null && echo "      sing-box: 运行中" || echo "      sing-box: 启动失败，请检查 journalctl -u sing-box"

# ---------- 生成客户端配置 ----------
mkdir -p /root/vpn-clients

# Hysteria2 客户端 (含端口跳跃)
cat > /root/vpn-clients/hysteria2-client.json <<EOF
{
  "log": { "level": "info" },
  "inbounds": [ { "type": "mixed", "listen": "127.0.0.1", "listen_port": 1080 } ],
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "Hysteria2-AWS",
      "server": "${PUBLIC_IP}",
      "server_ports": "${HOP_START}-${HOP_END}",
      "password": "${HY_PASSWORD}",
      "obfs": { "type": "salamander", "password": "${OBFS_PASSWORD}" },
      "tls": { "enabled": true, "insecure": true }
    }
  ]
}
EOF

# Reality 客户端
cat > /root/vpn-clients/reality-client.json <<EOF
{
  "log": { "level": "info" },
  "inbounds": [ { "type": "mixed", "listen": "127.0.0.1", "listen_port": 1080 } ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "Reality-AWS",
      "server": "${PUBLIC_IP}",
      "server_port": ${REALITY_PORT},
      "uuid": "${UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "utls": { "enabled": true, "fingerprint": "${FINGERPRINT}" },
        "reality": { "enabled": true, "public_key": "${REALITY_PUBLIC}", "short_id": "${SHORT_ID}" }
      }
    }
  ]
}
EOF

# 分享链接 (快速导入)
HY_LINK="hysteria2://${HY_PASSWORD}@${PUBLIC_IP}:${HYSTERIA_PORT}/?insecure=1&obfs=salamander&obfs-password=${OBFS_PASSWORD}#Hysteria2-AWS"
REALITY_LINK="vless://${UUID}@${PUBLIC_IP}:${REALITY_PORT}?encryption=none&security=reality&sni=${REALITY_SNI}&fp=${FINGERPRINT}&pbk=${REALITY_PUBLIC}&sid=${SHORT_ID}&flow=xtls-rprx-vision&type=tcp&headerType=none#Reality-AWS"

cat > /root/vpn-clients/README.txt <<EOF
================= 客户端信息 =================
服务器IP:     ${PUBLIC_IP}
Hysteria2端口: ${HYSTERIA_PORT} (端口跳跃 ${HOP_START}-${HOP_END})
Reality端口:   ${REALITY_PORT} (伪装: ${REALITY_SNI})

--- Hysteria2 分享链接 (推荐手机/平板导入) ---
${HY_LINK}

--- Reality 分享链接 ---
${REALITY_LINK}

--- 配置文件位置 ---
/root/vpn-clients/hysteria2-client.json   (支持端口跳跃，速度最优)
/root/vpn-clients/reality-client.json     (抗封锁保底)
EOF

echo ""
echo "============================================================"
cat /root/vpn-clients/README.txt
echo "============================================================"
echo ""
echo "Hysteria2 手机扫码:"
qrencode -t ansiutf8 "$HY_LINK"
echo ""
echo "Reality 手机扫码:"
qrencode -t ansiutf8 "$REALITY_LINK"
echo ""
echo "全部客户端文件已生成至 /root/vpn-clients/"