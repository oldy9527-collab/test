#!/bin/bash

# 遇到错误立即停止
set -e

echo "=============================="
echo " sing-box 移动特供修复版 (HY2 + TUIC + Trojan)"
echo " 保留多端口跳跃 / 修复AnyTLS报错 / 官方核心"
echo "=============================="
sleep 1

# =============================
# 0. 环境准备
# =============================
echo "📦 安装依赖..."
apt-get update
apt-get install -y curl openssl ufw qrencode

# 安装官方 sing-box
if ! command -v sing-box &> /dev/null; then
    echo "⬇️ 安装 sing-box 官方正式版..."
    bash <(curl -fsSL https://sing-box.app/sba.sh)
fi

# =============================
# 1. 变量定义 (移动优化配置区)
# =============================
SB_DIR="/etc/sing-box"
CONF="$SB_DIR/config.json"

# 【重点优化】移动多端口跳跃 (Port Hopping)
# 遇到 UDP 阻断时，客户端会自动尝试不同端口
HY_PORTS=(38124 41287 45863 49211 53789)
TUIC_PORTS=(32241 35678 40193 46652 52984)

# 【重点优化】TCP 救命端口 (原 AnyTLS 替换为 Trojan)
# 当移动彻底封锁 UDP 时，走这个 TCP 端口
TROJAN_PORT=443

# 自动生成密码
HY_PASS=$(openssl rand -base64 16 | tr -d '=+/')
TUIC_UUID=$(cat /proc/sys/kernel/random/uuid)
TUIC_PASS=$(openssl rand -base64 12 | tr -d '=+/')
TROJAN_PASS=$(openssl rand -base64 16 | tr -d '=+/')
SERVER_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

# =============================
# 2. 清理与证书
# =============================
systemctl stop sing-box 2>/dev/null || true
mkdir -p $SB_DIR

echo "🔐 生成自签证书 (CN=www.bing.com)..."
# 使用 bing.com 进行 SNI 伪装
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout $SB_DIR/private.key \
  -out $SB_DIR/cert.crt \
  -days 3650 \
  -subj "/CN=www.bing.com" >/dev/null 2>&1

chmod 644 $SB_DIR/cert.crt
chmod 600 $SB_DIR/private.key

# =============================
# 3. 防火墙 (很重要)
# =============================
echo "🔥 配置防火墙..."
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp          # 必须保留 SSH
ufw allow $TROJAN_PORT/tcp # 放行 TCP 救命端口

# 循环放行 UDP 端口
for p in "${HY_PORTS[@]}"; do ufw allow ${p}/udp >/dev/null; done
for p in "${TUIC_PORTS[@]}"; do ufw allow ${p}/udp >/dev/null; done

echo "y" | ufw enable >/dev/null

# =============================
# 4. 生成配置文件
# =============================
echo "🧩 生成 sing-box 配置..."

cat > $CONF <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
EOF

# [1] HY2 配置 (循环生成)
for i in "${!HY_PORTS[@]}"; do
  p="${HY_PORTS[$i]}"
  cat >> $CONF <<EOF
    {
      "type": "hysteria2",
      "tag": "hy2-$p",
      "listen": "::",
      "listen_port": $p,
      "users": [{ "password": "$HY_PASS" }],
      "ignore_client_bandwidth": true,
      "tls": {
        "enabled": true,
        "certificate_path": "$SB_DIR/cert.crt",
        "key_path": "$SB_DIR/private.key"
      }
    },
EOF
done

# [2] TUIC 配置 (循环生成)
for i in "${!TUIC_PORTS[@]}"; do
  p="${TUIC_PORTS[$i]}"
  cat >> $CONF <<EOF
    {
      "type": "tuic",
      "tag": "tuic-$p",
      "listen": "::",
      "listen_port": $p,
      "users": [{ "uuid": "$TUIC_UUID", "password": "$TUIC_PASS" }],
      "congestion_control": "bbr",
      "zero_rtt_handshake": true,
      "tls": {
        "enabled": true,
        "certificate_path": "$SB_DIR/cert.crt",
        "key_path": "$SB_DIR/private.key"
      }
    },
EOF
done

# [3] Trojan 配置 (替代 AnyTLS)
# 注意：这是最后一个配置块，结尾不能有逗号
cat >> $CONF <<EOF
    {
      "type": "trojan",
      "tag": "trojan-tcp",
      "listen": "::",
      "listen_port": $TROJAN_PORT,
      "users": [{ "password": "$TROJAN_PASS" }],
      "tls": {
        "enabled": true,
        "certificate_path": "$SB_DIR/cert.crt",
        "key_path": "$SB_DIR/private.key"
      }
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ]
}
EOF

# =============================
# 5. 创建 systemd 服务文件
# =============================
echo "📄 创建 systemd 服务文件..."
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box
After=network.target

[Service]
ExecStart=/usr/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# =============================
# 6. 启动服务
# =============================
echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# =============================
# 7. 输出结果
# =============================
echo ""
echo "======================================"
echo " ✅ 部署完成 - 移动优化版"
echo "======================================"
echo "IP: $SERVER_IP"
echo ""
echo "👉 移动主力 1 (Hysteria2):"
echo "   端口: ${HY_PORTS[*]} (自动轮询)"
echo "   密码: $HY_PASS"
echo ""
echo "👉 移动主力 2 (TUIC v5):"
echo "   端口: ${TUIC_PORTS[*]} (自动轮询)"
echo "   UUID: $TUIC_UUID"
echo "   密码: $TUIC_PASS"
echo ""
echo "👉 移动备用 (Trojan-TCP) [原AnyTLS替代]:"
echo "   端口: $TROJAN_PORT"
echo "   密码: $TROJAN_PASS"
echo "   说明: 当 UDP 被完全阻断时使用此节点"
echo ""

# 生成链接
HY_LINK="hysteria2://$HY_PASS@$SERVER_IP:${HY_PORTS[0]}?insecure=1&sni=www.bing.com#HY2-Mobile"
TUIC_LINK="tuic://$TUIC_UUID:$TUIC_PASS@$SERVER_IP:${TUIC_PORTS[0]}?congestion_control=bbr&allow_insecure=1&sni=www.bing.com#TUIC-Mobile"
TROJAN_LINK="trojan://$TROJAN_PASS@$SERVER_IP:$TROJAN_PORT?security=tls&allowInsecure=1&sni=www.bing.com#Trojan-Fallback"

echo "🔗 分享链接 (复制导入):"
echo "---------------------------------------------------"
echo "$HY_LINK"
echo "---------------------------------------------------"
echo "$TUIC_LINK"
echo "---------------------------------------------------"
echo "$TROJAN_LINK"
echo "---------------------------------------------------"

if command -v qrencode >/dev/null 2>&1; then
  echo "📱 备用节点二维码 (Trojan):"
  qrencode -t ANSIUTF8 "$TROJAN_LINK"
fi

echo ""
echo "⚠️  注意：自签证书模式，客户端必须开启【允许不安全连接 (Allow Insecure)】"
echo "======================================"
