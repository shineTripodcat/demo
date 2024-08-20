#!/bin/bash

# 默认配置
DEFAULT_START_PORT=20000                         # 默认起始端口
DEFAULT_SOCKS_USERNAME="userb"                   # 默认 SOCKS 账号
DEFAULT_SOCKS_PASSWORD="passwordb"               # 默认 SOCKS 密码
DEFAULT_WS_PATH="/ws"                            # 默认 WebSocket 路径

# 获取本机 IP 地址
IP_ADDRESSES=($(hostname -I))
IP_COUNT_MAX=${#IP_ADDRESSES[@]} # 最大 IP 数量

# 安装 Xray
install_xray() {
    echo "安装 Xray..."
    apt-get install unzip -y || yum install unzip -y
    wget https://github.com/XTLS/Xray-core/releases/download/v1.8.3/Xray-linux-64.zip
    unzip Xray-linux-64.zip
    mv xray /usr/local/bin/xrayL
    chmod +x /usr/local/bin/xrayL

    # 创建系统服务
    cat <<EOF >/etc/systemd/system/xrayL.service
[Unit]
Description=XrayL Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayL -c /etc/xrayL/config.toml
Restart=on-failure
User=nobody
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xrayL.service
    systemctl start xrayL.service
    echo "Xray 安装完成."
}

# 清除旧的配置并释放端口
clear_old_config() {
    echo "清除旧的配置并释放端口..."
    systemctl stop xrayL.service
    rm -f /etc/xrayL/*.toml
    echo "旧的配置已删除，端口已释放。"
}

# 读取现有配置并提示端口占用情况
read_existing_config() {
    echo "读取现有配置并提示端口占用情况..."
    if [ -f /etc/xrayL/socks5_config.toml ]; then
        echo "现有 SOCKS 配置:"
        grep "port =" /etc/xrayL/socks5_config.toml
    fi
    if [ -f /etc/xrayL/vmess_config.toml ]; then
        echo "现有 VMess 配置:"
        grep "port =" /etc/xrayL/vmess_config.toml
    fi
}

# 配置 Xray
config_xray() {
    config_type=$1
    mkdir -p /etc/xrayL

    # 验证配置类型
    if [ "$config_type" != "socks" ] && [ "$config_type" != "vmess" ]; then
        echo "类型错误！仅支持 socks 和 vmess."
        exit 1
    fi

    # 初始化配置内容
    config_content=""

    while true; do
        # 询问是否添加用户
        read -p "是否添加用户？(y/n): " add_user
        if [ "$add_user" != "y" ]; then
            break
        fi

        if [ "$config_type" == "vmess" ]; then
            UUID=$(cat /proc/sys/kernel/random/uuid) # 为每个用户生成一个 UUID
        fi

        # 用户输入起始端口和代理池数量
        while true; do
            read -p "起始端口 (默认 $DEFAULT_START_PORT): " START_PORT
            START_PORT=${START_PORT:-$DEFAULT_START_PORT}
            
            read -p "代理池 IP 数量 (最大 $IP_COUNT_MAX): " IP_COUNT
            if [ "$IP_COUNT" -gt "$IP_COUNT_MAX" ]; then
                echo "代理池 IP 数量不能超过 $IP_COUNT_MAX."
                continue
            fi

            # 检查端口是否被占用
            port_conflict=false
            for ((i = 0; i < IP_COUNT; i++)); do
                if lsof -i:"$((START_PORT + i))" > /dev/null; then
                    port_conflict=true
                    break
                fi
            done
            
            if [ "$port_conflict" = false ]; then
                break
            else
                echo "端口范围 $START_PORT-$((START_PORT + IP_COUNT - 1)) 中有端口被占用，请选择其他起始端口。"
            fi
        done

        if [ "$config_type" == "socks" ]; then
            read -p "SOCKS 账号 (默认 $DEFAULT_SOCKS_USERNAME): " SOCKS_USERNAME
            SOCKS_USERNAME=${SOCKS_USERNAME:-$DEFAULT_SOCKS_USERNAME}

            read -p "SOCKS 密码 (默认 $DEFAULT_SOCKS_PASSWORD): " SOCKS_PASSWORD
            SOCKS_PASSWORD=${SOCKS_PASSWORD:-$DEFAULT_SOCKS_PASSWORD}

            for ((i = 0; i < IP_COUNT; i++)); do
                # SOCKS 配置
                config_content+="[[inbounds]]\n"
                config_content+="port = $((START_PORT + i))\n"
                config_content+="protocol = \"socks\"\n"
                config_content+="tag = \"tag_$((i + 1))\"\n"
                config_content+="[inbounds.settings]\n"
                config_content+="auth = \"password\"\n"
                config_content+="udp = true\n"
                config_content+="[[inbounds.settings.accounts]]\n"
                config_content+="user = \"$SOCKS_USERNAME\"\n"
                config_content+="pass = \"$SOCKS_PASSWORD\"\n\n"
            done

        elif [ "$config_type" == "vmess" ]; then
            read -p "WebSocket 路径 (默认 $DEFAULT_WS_PATH): " WS_PATH
            WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}

            for ((i = 0; i < IP_COUNT; i++)); do
                # VMess 配置
                config_content+="[[inbounds]]\n"
                config_content+="port = $((START_PORT + i))\n"
                config_content+="protocol = \"vmess\"\n"
                config_content+="tag = \"tag_$((i + 1))\"\n"
                config_content+="[inbounds.settings]\n"
                config_content+="[[inbounds.settings.clients]]\n"
                config_content+="id = \"$UUID\"\n"
                config_content+="[inbounds.streamSettings]\n"
                config_content+="network = \"ws\"\n"
                config_content+="[inbounds.streamSettings.wsSettings]\n"
                config_content+="path = \"$WS_PATH\"\n\n"
            done
        fi

        # 公共配置部分
        config_content+="sendThrough = \"${IP_ADDRESSES[0]}\"\n"
        config_content+="protocol = \"freedom\"\n"
        config_content+="tag = \"tag_$((i + 1))\"\n\n"

        config_content+="[[routing.rules]]\n"
        config_content+="type = \"field\"\n"
        config_content+="inboundTag = \"tag_$((i + 1))\"\n"
        config_content+="outboundTag = \"tag_$((i + 1))\"\n\n\n"

        # 检查是否继续添加用户
        read -p "是否继续添加用户？(y/n): " add_more
        if [ "$add_more" != "y" ]; then
            break
        fi
    done

    # 根据选择的类型保存配置到相应文件
    if [ "$config_type" == "socks" ]; then
        CONFIG_FILE="/etc/xrayL/socks5_config.toml"
    elif [ "$config_type" == "vmess" ]; then
        CONFIG_FILE="/etc/xrayL/vmess_config.toml"
    fi

    # 保存配置到文件
    echo -e "$config_content" >> "$CONFIG_FILE"
    systemctl restart xrayL.service
    systemctl --no-pager status xrayL.service
    echo ""
    echo "生成 $config_type 配置完成"
    echo "配置文件保存为: $CONFIG_FILE"
    echo "起始端口: $START_PORT"
    echo "结束端口: $((START_PORT + IP_COUNT - 1))"
    
    if [ "$config_type" == "socks" ]; then
        echo "SOCKS 账号: $SOCKS_USERNAME"
        echo "SOCKS 密码: $SOCKS_PASSWORD"
    elif [ "$config_type" == "vmess" ]; then
        echo "UUID: $UUID"
        echo "WebSocket 路径: $WS_PATH"
    fi
    echo ""
}

# 主函数
main() {
    # 询问用户是否重新配置或添加新用户
    read -p "选择操作类型：重新配置 (r) 还是添加新用户 (a): " operation_type

    if [ "$operation_type" == "r" ]; then
        # 清除旧的配置并释放端口
        clear_old_config
    elif [ "$operation_type" == "a" ]; then
        # 读取现有配置并提示端口占用情况
        read_existing_config
    else
        echo "无效的选择，退出脚本。"
        exit 1
    fi

    # 检查 Xray 是否已安装
    [ -x "$(command -v xrayL)" ] || install_xray
    
    # 获取用户输入的配置类型
    if [ $# -eq 1 ]; then
        config_type="$1"
    else
        read -p "选择生成的节点类型 (socks/vmess): " config_type
    fi

    # 根据用户选择配置 Xray
    if [ "$config_type" == "vmess" ]; then
        config_xray "vmess"
    elif [ "$config_type" == "socks" ]; then
        config_xray "socks"
    else
        echo "未正确选择类型，使用默认 SOCKS 配置."
        config_xray "socks"
    fi
}

# 执行主函数
main "$@"
