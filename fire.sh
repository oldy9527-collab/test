# 1. 启用UFW防火墙
echo "正在启用UFW防火墙..."
sudo ufw enable

# 2. 设置默认策略为拒绝（屏蔽所有未明确允许的连接）
echo "设置默认策略为拒绝..."
sudo ufw default deny incoming
sudo ufw default allow outgoing


# 3. 允许SSH（22端口）和HTTPS（443端口）流量
echo "开放SSH端口（22）和HTTPS端口（443）..."
sudo ufw allow 22/tcp

# 4. 放行 Hysteria2（UDP）
sudo ufw allow 38124/udp
sudo ufw allow 41287/udp
sudo ufw allow 45863/udp
sudo ufw allow 49211/udp
sudo ufw allow 53789/udp

# 5. 放行 TUIC（UDP）
sudo ufw allow 32241/udp
sudo ufw allow 35678/udp
sudo ufw allow 40193/udp
sudo ufw allow 46652/udp
sudo ufw allow 52984/udp

# 6. 放行 Vless-ws-enc（TCP）
sudo ufw allow 32958/tcp

# 7. 查看当前防火墙状态
echo "当前防火墙状态："
sudo ufw status verbose

echo "防火墙配置完成。"
