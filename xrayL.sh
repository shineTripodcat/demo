#!/bin/bash

# 默认配置
DEFAULT_START_PORT=20000                         # 默认起始端口
DEFAULT_SOCKS_USERNAME="userb"                   # 默认 SOCKS 账号
DEFAULT_SOCKS_PASSWORD="passwordb"               # 默认 SOCKS 密码
DEFAULT_WS_PATH="/ws"                            # 默认 WebSocket 路径
DEFAULT_UUID=$(cat /proc/sys/kernel/random/uuid) # 默认随机 UUID

# 获取本机 IP 地址
IP_ADDRESSES=($(hostname -I))

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

# 配置 Xray
config_xray() {
    config_type=$1
    mkdir -p /etc/xrayL

    # 验证配置类型
    if [ "$config_type" != "socks" ] && [ "$config_type" != "vmess" ]; then
        echo "类型错误！仅支持 socks 和 vmess."
        exit 1
    fi

    # 用户输入起始端口和代理池数量
    read -p "起始端口 (默认 $DEFAULT_START_PORT): " START_PORT
    START_PORT=${START_PORT:-$DEFAULT_START_PORT}
    read -p "代理池 IP 数量: " IP_COUNT

    # 初始化配置内容
    config_content=""

    for ((i = 0; i < IP_COUNT; i++)); do
        if [ "$config_type" == "socks" ]; then
            read -p "SOCKS 账号 (默认 $DEFAULT_SOCKS_USERNAME): " SOCKS_USERNAME
            SOCKS_USERNAME=${SOCKS_USERNAME:-$DEFAULT_SOCKS_USERNAME}

            read -p "SOCKS 密码 (默认 $DEFAULT_SOCKS_PASSWORD): " SOCKS_PASSWORD
            SOCKS_PASSWORD=${SOCKS_PASSWORD:-$DEFAULT_SOCKS_PASSWORD}

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

        elif [ "$config_type" == "vmess" ]; then
            read -p "UUID (默认随机): " UUID
            UUID=${UUID:-$DEFAULT_UUID}
            read -p "WebSocket 路径 (默认 $DEFAULT_WS_PATH): " WS_PATH
            WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}

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
        fi

        # 公共配置部分
        config_content+="sendThrough = \"${IP_ADDRESSES[0]}\"\n" # 使用第一个 IP 地址
        config_content+="protocol = \"freedom\"\n"
        config_content+="tag = \"tag_$((i + 1))\"\n\n"

        config_content+="[[routing.rules]]\n"
        config_content+="type = \"field\"\n"
        config_content+="inboundTag = \"tag_$((i + 1))\"\n"
        config_content+="outboundTag = \"tag_$((i + 1))\"\n\n\n"
    done

    # 根据选择的类型保存配置到相应文件
    if [ "$config_type" == "socks" ]; then
        CONFIG_FILE="/etc/xrayL/socks5_config.toml"
    elif [ "$config_type" == "vmess" ]; then
        CONFIG_FILE="/etc/xrayL/vmess_config.toml"
    fi

    # 保存配置到文件
    echo -e "$config_content" > "$CONFIG_FILE"
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

# 增加用户配置
add_user() {
    config_type=$1
    read -p "起始端口 (默认 $DEFAULT_START_PORT): " START_PORT
    START_PORT=${START_PORT:-$DEFAULT_START_PORT}
    read -p "代理池 IP 数量: " IP_COUNT

    user_config=""
    for ((i = 0; i < IP_COUNT; i++)); do
        if [ "$config_type" == "socks" ]; then
            read -p "SOCKS 账号 (默认 $DEFAULT_SOCKS_USERNAME): " SOCKS_USERNAME
            SOCKS_USERNAME=${SOCKS_USERNAME:-$DEFAULT_SOCKS_USERNAME}

            read -p "SOCKS 密码 (默认 $DEFAULT_SOCKS_PASSWORD): " SOCKS_PASSWORD
            SOCKS_PASSWORD=${SOCKS_PASSWORD:-$DEFAULT_SOCKS_PASSWORD}

            user_config+="[[inbounds]]\n"
            user_config+="port = $((START_PORT + i))\n"
            user_config+="protocol = \"socks\"\n"
            user_config+="tag = \"tag_$((i + 1))\"\n"
            user_config+="[inbounds.settings]\n"
            user_config+="auth = \"password\"\n"
            user_config+="udp = true\n"
            user_config+="[[inbounds.settings.accounts]]\n"
            user_config+="user = \"$SOCKS_USERNAME\"\n"
            user_config+="pass = \"$SOCKS_PASSWORD\"\n\n"

        elif [ "$config_type" == "vmess" ]; then
            read -p "UUID (默认随机): " UUID
            UUID=${UUID:-$DEFAULT_UUID}
            read -p "WebSocket 路径 (默认 $DEFAULT_WS_PATH): " WS_PATH
            WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}

            user_config+="[[inbounds]]\n"
            user_config+="port = $((START_PORT + i))\n"
            user_config+="protocol = \"vmess\"\n"
            user_config+="tag = \"tag_$((i + 1))\"\n"
            user_config+="[inbounds.settings]\n"
            user_config+="[[inbounds.settings.clients]]\n"
            user_config+="id = \"$UUID\"\n"
            user_config+="[inbounds.streamSettings]\n"
            user_config+="network = \"ws\"\n"
            user_config+="[inbounds.streamSettings.wsSettings]\n"
            user_config+="path = \"$WS_PATH\"\n\n"
        fi

        user_config+="sendThrough = \"${IP_ADDRESSES[0]}\"\n"
        user_config+="protocol = \"freedom\"\n"
        user_config+="tag = \"tag_$((i + 1))\"\n\n"

        user_config+="[[routing.rules]]\n"
        user_config+="type = \"field\"\n"
        user_config+="inboundTag = \"tag_$((i + 1))\"\n"
        user_config+="outboundTag = \"tag_$((i + 1))\"\n\n\n"
    done

    # 根据选择的类型保存配置到相应文件
    if [ "$config_type" == "socks" ]; then
        CONFIG_FILE="/etc/xrayL/socks5_config.toml"
    elif [ "$config_type" == "vmess" ]; then
        CONFIG_FILE="/etc/xrayL/vmess_config.toml"
    fi

    # 追加用户配置到文件
    echo -e "$user_config" >> "$CONFIG_FILE"
    systemctl restart xrayL.service
    systemctl --no-pager status xrayL.service
    echo ""
    echo "添加 $config_type 用户配置完成"
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

    # 增加用户配置
    while true; do
        read -p "是否添加更多用户配置？(y/n): " add_more
        if [ "$add_more" == "y" ]; then
            add_user "$config_type"
        else
            break
        fi
    done
}

# 执行主函数
main "$@"
