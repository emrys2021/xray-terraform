#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "s390x" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
else
    arch="amd64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit -1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar jq bind-utils sqlite -y
    else
        apt install wget curl tar jq bind9-dnsutils sqlite3 -y
    fi

    if [[ x"${release}" == x"centos" ]]; then
        systemctl stop firewalld
        systemctl disable firewalld
        echo -e "${green}[OK]${plain} firewalld 已关闭"
    else
        systemctl stop ufw
        systemctl disable ufw
        echo -e "${green}[OK]${plain} ufw 已关闭"
    fi
}

enable_bbr() {
    local kernel_major kernel_minor
    kernel_major=$(uname -r | cut -d. -f1)
    kernel_minor=$(uname -r | cut -d. -f2)
    if [[ ${kernel_major} -gt 4 ]] || [[ ${kernel_major} -eq 4 && ${kernel_minor} -ge 9 ]]; then
        if [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" ]]; then
            echo -e "${green}[OK]${plain} BBR 已启用（内核 $(uname -r)）"
        else
            echo -e "${green}[OK]${plain} 内核 $(uname -r) 支持 BBR，正在启用"
            if ! grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf; then
                echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
                echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            fi
            sysctl -p >/dev/null 2>&1
            echo -e "${green}[OK]${plain} BBR 启用完成"
        fi
    else
        echo -e "${yellow}[跳过]${plain} 内核 $(uname -r) 不支持 BBR（需 4.9+），如需启用请手动升级内核"
    fi
}

domain_check() {
    read -rp "在阿里云上配置域名解析记录，并输入域名信息(eg:www.example.com):" domain
    echo -e "${green}[OK]${plain} 正在解析域名，请耐心等待"
    for i in {1..6}; do
        domain_ipv4="$(dig +short "${domain}" a)"
        domain_ipv6="$(dig +short "${domain}" aaaa)"
        [[ -n "${domain_ipv4}" || -n "${domain_ipv6}" ]] && break
        echo -e "${yellow}[等待]${plain} 域名暂未解析，${i}/6 次重试，10 秒后继续..."
        sleep 10
    done
    echo -e "${green}[OK]${plain} 正在获取公网 IP 信息，请耐心等待"
    wgcfv4_status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv6_status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ ${wgcfv4_status} =~ "on"|"plus" ]] || [[ ${wgcfv6_status} =~ "on"|"plus" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        echo -e "${green}[OK]${plain} 已关闭 wgcf-warp"
    fi
    local_ipv4=$(curl -s4m8 http://ip.sb)
    local_ipv6=$(curl -s6m8 http://ip.sb)
    if [[ -z ${local_ipv4} && -n ${local_ipv6} ]]; then
        echo "nameserver 2a01:4f8:c2c:123f::1" >/etc/resolv.conf
        echo -e "${green}[OK]${plain} 识别为 IPv6 Only 的 VPS，自动添加 DNS64 服务器"
    fi
    echo -e "域名 DNS 解析到的 IP：${domain_ipv4:-${domain_ipv6}}"
    echo -e "本机 IPv4：${local_ipv4}"
    echo -e "本机 IPv6：${local_ipv6}"
    sleep 2
    if [[ ${domain_ipv4} == ${local_ipv4} ]]; then
        echo -e "${green}[OK]${plain} 域名 DNS 解析 IP 与本机 IPv4 匹配"
        sleep 2
    elif [[ ${domain_ipv6} == ${local_ipv6} ]]; then
        echo -e "${green}[OK]${plain} 域名 DNS 解析 IP 与本机 IPv6 匹配"
        sleep 2
    else
        echo -e "${red}[错误]${plain} 请确保域名添加了正确的 A / AAAA 记录，否则将无法正常申请证书"
        read -rp "域名 DNS 解析 IP 与本机 IPv4 / IPv6 不匹配，是否继续安装？(y/n)" install_confirm
        case ${install_confirm} in
        [yY][eE][sS] | [yY])
            echo -e "${green}继续安装${plain}"
            sleep 2
            ;;
        *)
            echo -e "${red}安装终止${plain}"
            exit 2
            ;;
        esac
    fi
}

ssl_install() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install socat nc -y
    else
        apt install socat netcat-openbsd -y
    fi
    if [[ $? -eq 0 ]]; then
        echo -e "${green}[OK]${plain} 安装 SSL 证书生成脚本依赖 完成"
    else
        echo -e "${red}[错误]${plain} 安装 SSL 证书生成脚本依赖 失败"
        exit 1
    fi

    curl https://get.acme.sh | sh
    if [[ $? -eq 0 ]]; then
        echo -e "${green}[OK]${plain} 安装 SSL 证书生成脚本 完成"
    else
        echo -e "${red}[错误]${plain} 安装 SSL 证书生成脚本 失败"
        exit 1
    fi
}

acme() {
    "${HOME}"/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    "${HOME}"/.acme.sh/acme.sh --issue --insecure -d "${domain}" --standalone -k ec-256 --force 2>&1 | tee /tmp/acme_output.log
    local acme_exit=${PIPESTATUS[0]}

    if [[ ${acme_exit} -eq 0 ]]; then
        echo -e "${green}[OK]${plain} SSL 证书生成成功"
        sleep 2
        mkdir -p /data
        if "${HOME}"/.acme.sh/acme.sh --installcert -d "${domain}" \
            --fullchainpath /data/v2ray.crt --keypath /data/v2ray.key --ecc --force; then
            echo -e "${green}[OK]${plain} 证书配置成功"
            sleep 2
            if [[ -n $(type -P wgcf) && -n $(type -P wg-quick) ]]; then
                wg-quick up wgcf >/dev/null 2>&1
                echo -e "${green}[OK]${plain} 已启动 wgcf-warp"
            fi
        fi
    else
        if grep -q "rateLimited" /tmp/acme_output.log; then
            echo -e "${red}[错误]${plain} Let's Encrypt 证书申请次数超限，同一域名每周最多申请 5 次"
            local retry_time
            retry_time=$(grep -oP 'retry after \K[^"]+' /tmp/acme_output.log | head -1)
            [[ -n "${retry_time}" ]] && echo -e "${yellow}[提示]${plain} 请在 ${retry_time} 后重新部署"
        else
            echo -e "${red}[错误]${plain} SSL 证书生成失败，请检查域名解析是否正确、80 端口是否已开放"
        fi
        rm -f /tmp/acme_output.log
        rm -rf "${HOME}/.acme.sh/${domain}_ecc"
        if [[ -n $(type -P wgcf) && -n $(type -P wg-quick) ]]; then
            wg-quick up wgcf >/dev/null 2>&1
            echo -e "${green}[OK]${plain} 已启动 wgcf-warp"
        fi
        exit 1
    fi
    rm -f /tmp/acme_output.log
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {
    local default_password='v2ray123$'
    echo -e "${yellow}出于安全考虑，安装/更新完成后需要强制修改端口与账户密码${plain}"
    read -p "确认是否继续,如选择n则跳过本次端口与账户密码设定[y/n]": config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "请设置您的账户名 [默认: v2ray]:" config_account
        config_account=${config_account:-v2ray}
        echo -e "${yellow}您的账户名将设定为:${config_account}${plain}"
        read -p "请设置您的账户密码 [默认: ${default_password}]:" config_password
        config_password=${config_password:-${default_password}}
        echo -e "${yellow}您的账户密码将设定为:${config_password}${plain}"
        read -p "请设置面板访问端口 [默认: 6357]:" config_port
        config_port=${config_port:-6357}
        echo -e "${yellow}您的面板访问端口将设定为:${config_port}${plain}"
        echo -e "${yellow}确认设定,设定中${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}账户密码设定完成${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow}面板端口设定完成${plain}"
        panel_port=${config_port}
    else
        echo -e "${red}已取消设定...${plain}"
        if [[ ! -f "/etc/x-ui/x-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            local portTemp=$(echo $RANDOM)
            /usr/local/x-ui/x-ui setting -username ${usernameTemp} -password ${passwordTemp}
            /usr/local/x-ui/x-ui setting -port ${portTemp}
            echo -e "检测到您属于全新安装,出于安全考虑已自动为您生成随机用户与端口:"
            echo -e "###############################################"
            echo -e "${green}面板登录用户名:${usernameTemp}${plain}"
            echo -e "${green}面板登录用户密码:${passwordTemp}${plain}"
            echo -e "${red}面板登录端口:${portTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}如您遗忘了面板登录相关信息,可在安装完成后输入x-ui,输入选项7查看面板登录信息${plain}"
            panel_port=${portTemp}
        else
            echo -e "${red}当前属于版本升级,保留之前设置项,登录方式保持不变,可输入x-ui后键入数字7查看面板登录信息${plain}"
            panel_port="（原端口不变）"
        fi
    fi
}

install_x-ui() {
    systemctl stop x-ui 2>/dev/null || true
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Lsk "https://api.github.com/repos/FranzKafkaYu/x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 x-ui 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 x-ui 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 x-ui 最新版本：${last_version}，开始安装"
        wget --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz https://github.com/FranzKafkaYu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/FranzKafkaYu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        echo -e "开始安装 x-ui v$1"
        wget --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 x-ui v$1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    cd x-ui
    chmod +x x-ui bin/xray-linux-${arch}
    cp -f x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/FranzKafkaYu/x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install
    #echo -e "如果是全新安装，默认网页端口为 ${green}54321${plain}，用户名和密码默认都是 ${green}admin${plain}"
    #echo -e "请自行确保此端口没有被其他程序占用，${yellow}并且确保 54321 端口已放行${plain}"
    #    echo -e "若想将 54321 修改为其它端口，输入 x-ui 命令进行修改，同样也要确保你修改的端口也是放行的"
    #echo -e ""
    #echo -e "如果是更新面板，则按你之前的方式访问面板"
    #echo -e ""
    systemctl daemon-reload
    systemctl enable x-ui
    echo -e "${green}[OK]${plain} 正在写入数据库配置（BasePath、证书路径）"
    sqlite3 /etc/x-ui/x-ui.db "INSERT OR REPLACE INTO settings (key, value) VALUES ('webBasePath', '/v2ray/');"
    sqlite3 /etc/x-ui/x-ui.db "INSERT OR REPLACE INTO settings (key, value) VALUES ('webCertFile', '/data/v2ray.crt');"
    sqlite3 /etc/x-ui/x-ui.db "INSERT OR REPLACE INTO settings (key, value) VALUES ('webKeyFile', '/data/v2ray.key');"
    echo -e "${green}[OK]${plain} 数据库配置写入完成"
    echo -e "${green}[OK]${plain} 正在创建默认 vless+ws+tls 入站配置"
    vless_uuid=$(cat /proc/sys/kernel/random/uuid)
    vless_port=$((RANDOM % 55000 + 10000))
    vless_path="/$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 8)/"
    wget -qO /tmp/inbound-template.json "https://raw.githubusercontent.com/emrys2021/xray-terraform/refs/heads/main/inbound-template.json"
    sed -e "s|{{UUID}}|${vless_uuid}|g" \
        -e "s|{{DOMAIN}}|${domain}|g" \
        -e "s|{{PORT}}|${vless_port}|g" \
        -e "s|{{PATH}}|${vless_path}|g" \
        /tmp/inbound-template.json > /tmp/inbound-rendered.json
    vless_settings=$(jq -c '.settings' /tmp/inbound-rendered.json)
    vless_stream=$(jq -c '.stream_settings' /tmp/inbound-rendered.json)
    vless_sniffing=$(jq -c '.sniffing' /tmp/inbound-rendered.json)
    sqlite3 /etc/x-ui/x-ui.db "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, 'self', 1, 0, '', ${vless_port}, 'vless', '${vless_settings}', '${vless_stream}', 'inbound-${vless_port}', '${vless_sniffing}');"
    rm -f /tmp/inbound-template.json /tmp/inbound-rendered.json
    encoded_path=$(echo "${vless_path}" | sed 's|/|%2F|g')
    vless_link="vless://${vless_uuid}@${domain}:${vless_port}?type=ws&security=tls&path=${encoded_path}&sni=${domain}&fp=chrome#self|default@xray.com"
    echo -e "${green}[OK]${plain} 默认入站配置写入完成，启动 x-ui"
    systemctl start x-ui
    panel_url="https://${domain}:${panel_port}/v2ray/"
    cat > /root/xray_info.txt <<EOF
=== X-UI 安装信息 ===

面板地址：${panel_url}
默认账号：v2ray
默认密码：v2ray123\$

=== 默认 vless 入站 ===

协议：vless + ws + tls
域名：${domain}
端口：${vless_port}
UUID：${vless_uuid}
ws 路径：${vless_path}
导入链接：${vless_link}
EOF
    echo -e "${green}x-ui v${last_version}${plain} 安装完成，面板已启动"
    echo -e "${green}面板访问地址：${panel_url}${plain}"
    echo -e "${yellow}注意：访问路径已设为 /v2ray/，直接访问根路径将无法打开面板${plain}"
    echo -e "${green}安装信息已保存至 /root/xray_info.txt${plain}"
    echo -e ""
    echo -e "默认 vless 入站信息："
    echo -e "  端口：${vless_port}"
    echo -e "  UUID：${vless_uuid}"
    echo -e "  ws 路径：${vless_path}"
    echo -e "  导入链接：${vless_link}"
    echo -e ""
    echo -e "x-ui 管理脚本使用方法: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - 显示管理菜单 (功能更多)"
    echo -e "x-ui start        - 启动 x-ui 面板"
    echo -e "x-ui stop         - 停止 x-ui 面板"
    echo -e "x-ui restart      - 重启 x-ui 面板"
    echo -e "x-ui status       - 查看 x-ui 状态"
    echo -e "x-ui enable       - 设置 x-ui 开机自启"
    echo -e "x-ui disable      - 取消 x-ui 开机自启"
    echo -e "x-ui log          - 查看 x-ui 日志"
    echo -e "x-ui v2-ui        - 迁移本机器的 v2-ui 账号数据至 x-ui"
    echo -e "x-ui update       - 更新 x-ui 面板"
    echo -e "x-ui install      - 安装 x-ui 面板"
    echo -e "x-ui uninstall    - 卸载 x-ui 面板"
    echo -e "x-ui geo          - 更新 geo  数据"
    echo -e "----------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
enable_bbr
domain_check
ssl_install
acme
install_x-ui $1