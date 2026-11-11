#!/bin/bash
# 修复 sing-box v1.14 Hysteria2 入站缺少 TLS 的问题
set -e

# 1) 生成自签名证书（客户端用 insecure 跳过校验，无需 CA）
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout /etc/sing-box/hysteria.key \
  -out /etc/sing-box/hysteria.crt \
  -subj "/CN=www.microsoft.com" >/dev/null 2>&1

chmod 600 /etc/sing-box/hysteria.key

# 2) 给 hysteria2 入站补上 tls 块（保留原有密钥/密码）
python3 -c "import json;p='/etc/sing-box/config.json';c=json.load(open(p));[i.__setitem__('tls',{'enabled':True,'certificate_path':'/etc/sing-box/hysteria.crt','key_path':'/etc/sing-box/hysteria.key'}) for i in c['inbounds'] if i.get('type')=='hysteria2'];open(p,'w').write(json.dumps(c,indent=2));print('patched ok')"

# 3) 校验 + 重启
sing-box check -c /etc/sing-box/config.json
systemctl restart sing-box
sleep 1
systemctl is-active sing-box