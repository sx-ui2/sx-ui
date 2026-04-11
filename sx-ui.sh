#!/bin/bash
export LANG=en_US.UTF-8

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'

red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }
blue() { echo -e "\033[36m\033[01m$1\033[0m"; }
white() { echo -e "\033[37m\033[01m$1\033[0m"; }
readp() { read -p "$(yellow "$1")" "$2"; }

LOGD() { echo -e "${yellow}[DBG] $* ${plain}"; }
LOGE() { echo -e "${red}[ERR] $* ${plain}"; }
LOGI() { echo -e "${green}[INF] $* ${plain}"; }

print_cli_header() {
    local subtitle="${1:-管理脚本}"
    green "======================================================================"
    echo -e "${bblue}   ____  __  __        _   _ ___ ${plain}"
    echo -e "${bblue}  / ___| \\ \\/ /       | | | |_ _|${plain}"
    echo -e "${bblue}  \\___ \\  \\  /  _____ | | | || | ${plain}"
    echo -e "${bblue}   ___) | /  \\ |_____|| |_| || | ${plain}"
    echo -e "${bblue}  |____/ /_/\\_\\        \\___/|___|${plain}"
    echo
    white "sx-ui Github 项目 ：github.com/sx-ui2/sx-ui"
    white "sx-ui ${subtitle}   ：sx-ui"
    green "======================================================================"
    echo
}

release=""
os_version=""
setting_dump=""
current_username=""
current_password=""
current_port=""
current_base_path="/"
current_cert_file=""
current_key_file=""
current_cert_host=""
current_nginx_proxy_enabled="false"
current_nginx_proxy_host=""
current_nginx_proxy_https="false"
v4=""
v6=""
wgcfv4=""
wgcfv6=""
latest_release_version=""
post_install_exit_code=10

[[ $EUID -ne 0 ]] && LOGE "错误：必须使用 root 用户运行此脚本！" && exit 1

detect_release() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
        release="debian"
    elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue 2>/dev/null; then
        release="centos"
    elif grep -Eqi "debian" /proc/version 2>/dev/null; then
        release="debian"
    elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /proc/version 2>/dev/null; then
        release="centos"
    else
        LOGE "未检测到系统版本，请联系脚本作者。" && exit 1
    fi
}

check_os_version() {
    if [[ -f /etc/os-release ]]; then
        os_version=$(awk -F'[= ."]+' '/VERSION_ID/{print $2}' /etc/os-release)
    fi
    if [[ -z "${os_version}" && -f /etc/lsb-release ]]; then
        os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
    fi

    case "${release}" in
        centos)
            [[ -n "${os_version}" && ${os_version} -le 6 ]] && LOGE "请使用 CentOS 7 或更高版本的系统。" && exit 1
            ;;
        ubuntu)
            [[ -n "${os_version}" && ${os_version} -lt 16 ]] && LOGE "请使用 Ubuntu 16 或更高版本的系统。" && exit 1
            ;;
        debian)
            [[ -n "${os_version}" && ${os_version} -lt 8 ]] && LOGE "请使用 Debian 8 或更高版本的系统。" && exit 1
            ;;
    esac
}

get_system_pretty_name() {
    if [[ -f /etc/os-release ]]; then
        awk -F'"' '/^PRETTY_NAME=/{print $2}' /etc/os-release
        return 0
    fi
    if [[ -f /etc/redhat-release ]]; then
        cat /etc/redhat-release
        return 0
    fi
    echo "${release}"
}

get_kernel_version() {
    uname -r | cut -d "-" -f1
}

get_cpu_arch() {
    uname -m
}

get_virtualization_type() {
    local virt=""
    virt=$(systemd-detect-virt 2>/dev/null)
    if [[ -z "${virt}" || "${virt}" == "none" ]]; then
        virt=$(virt-what 2>/dev/null | head -n 1)
    fi
    [[ -z "${virt}" ]] && virt="物理机/未知"
    echo "${virt}"
}

get_bbr_algo() {
    local algo=""
    algo=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [[ -n "${algo}" ]]; then
        echo "${algo}"
    elif ping -c 1 -W 1 10.0.0.2 >/dev/null 2>&1; then
        echo "OpenVZ版bbr-plus"
    else
        echo "未知/OpenVZ-LXC"
    fi
}

confirm() {
    local prompt="$1"
    local default_value="${2:-}"
    local temp=""
    if [[ -n "${default_value}" ]]; then
        echo
        read -p "${prompt} [默认${default_value}]: " temp
        [[ -z "${temp}" ]] && temp="${default_value}"
    else
        read -p "${prompt} [y/n]: " temp
    fi
    [[ "${temp}" == "y" || "${temp}" == "Y" ]]
}

before_show_menu() {
    echo
    read -p "按回车返回主菜单: " temp
    show_menu
}

random_string() {
    local length="${1:-6}"
    tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c "${length}"
}

ensure_nat64_for_ipv6_only() {
    warpcheck
    if [[ ! "${wgcfv4}" =~ ^(on|plus)$ && ! "${wgcfv6}" =~ ^(on|plus)$ ]]; then
        v4v6
    fi

    if [[ -z "${v4}" && -n "${v6}" ]]; then
        if grep -q "2a00:1098:2b::1" /etc/resolv.conf 2>/dev/null && grep -q "2a00:1098:2c::1" /etc/resolv.conf 2>/dev/null; then
            LOGI "检测到纯 IPv6 VPS，NAT64/DNS64 解析已存在。"
        else
            LOGI "检测到纯 IPv6 VPS，自动添加 NAT64/DNS64 解析。"
            cat >/etc/resolv.conf <<'EOF'
nameserver 2a00:1098:2b::1
nameserver 2a00:1098:2c::1
EOF
        fi
    fi
}

v4v6() {
    v4=$(curl -s4m5 icanhazip.com -k 2>/dev/null | tr -d '\r\n')
    v6=$(curl -s6m5 icanhazip.com -k 2>/dev/null | tr -d '\r\n')
}

warpcheck() {
    wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | awk -F= '/^warp=/{print $2; exit}')
    wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | awk -F= '/^warp=/{print $2; exit}')
}

get_public_ipv4() {
    v4v6
    echo "${v4}"
}

get_public_ipv6() {
    v4v6
    echo "${v6}"
}

resolve_latest_sxui_release() {
    curl -Ls "https://api.github.com/repos/sx-ui2/sx-ui/releases?per_page=20" \
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | grep -E '^(26\.|0\.)' \
        | head -n 1
}

version_lt() {
    local left="$1"
    local right="$2"
    [[ -z "${left}" || -z "${right}" ]] && return 1
    [[ "${left}" == "${right}" ]] && return 1
    [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | head -n 1)" == "${left}" ]]
}

port_in_use() {
    local port="$1"
    ss -lntup 2>/dev/null | awk 'NR>1 {print $5}' | grep -Eq "[:.]${port}$"
}

current_ssh_port() {
    local port=""
    port=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2}' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -n 1)
    [[ -z "${port}" ]] && port="22"
    echo "${port}"
}

backup_firewall_rules() {
    local backup_dir="/etc/sx-ui/firewall-backups"
    local stamp=""

    mkdir -p "${backup_dir}" >/dev/null 2>&1 || return 1
    stamp=$(date +%Y%m%d-%H%M%S)

    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save >"${backup_dir}/iptables-${stamp}.rules" 2>/dev/null || true
    fi
    if command -v ip6tables-save >/dev/null 2>&1; then
        ip6tables-save >"${backup_dir}/ip6tables-${stamp}.rules" 2>/dev/null || true
    fi

    if [[ -f "${backup_dir}/iptables-${stamp}.rules" || -f "${backup_dir}/ip6tables-${stamp}.rules" ]]; then
        LOGI "已备份当前防火墙规则到 ${backup_dir}/"
        return 0
    fi

    return 1
}

persist_firewall_rules() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || true
        return 0
    fi

    if command -v service >/dev/null 2>&1; then
        service iptables save >/dev/null 2>&1 || true
        service ip6tables save >/dev/null 2>&1 || true
    fi
}

reset_filter_tables_for_ufw_cmd() {
    local cmd="$1"

    command -v "${cmd}" >/dev/null 2>&1 || return 1

    "${cmd}" -P INPUT ACCEPT >/dev/null 2>&1 || true
    "${cmd}" -P FORWARD ACCEPT >/dev/null 2>&1 || true
    "${cmd}" -P OUTPUT ACCEPT >/dev/null 2>&1 || true
    "${cmd}" -t mangle -F >/dev/null 2>&1 || true
    "${cmd}" -F >/dev/null 2>&1 || true
    "${cmd}" -X >/dev/null 2>&1 || true
    return 0
}

prepare_ufw_takeover() {
    local prepared=0

    backup_firewall_rules || true

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            systemctl stop firewalld >/dev/null 2>&1 || true
            systemctl disable firewalld >/dev/null 2>&1 || true
            prepared=1
        fi
    fi

    if command -v ufw >/dev/null 2>&1; then
        ufw disable >/dev/null 2>&1 || true
        prepared=1
    fi

    reset_filter_tables_for_ufw_cmd iptables && prepared=1
    reset_filter_tables_for_ufw_cmd ip6tables && prepared=1

    if [[ ${prepared} -eq 1 ]]; then
        persist_firewall_rules
        LOGI "已备份并重置现有 filter/mangle 防火墙规则，后续交由 UFW 接管。"
    fi
}

ensure_ufw_command() {
    if command -v ufw >/dev/null 2>&1; then
        return 0
    fi

    if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
        apt-get update -y >/dev/null 2>&1 || apt-get update -y || return 1
        apt-get install -y ufw >/dev/null 2>&1 || apt-get install -y ufw || return 1
        command -v ufw >/dev/null 2>&1
        return $?
    fi

    return 1
}

allow_port_via_ufw() {
    local port="$1"
    local ssh_port=""

    ensure_ufw_command || return 1
    prepare_ufw_takeover

    ssh_port="$(current_ssh_port)"
    ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
    ufw allow "${port}/tcp" >/dev/null 2>&1 || true

    if ! ufw status 2>/dev/null | grep -q "^Status: active"; then
        ufw --force enable >/dev/null 2>&1 || return 1
    else
        ufw reload >/dev/null 2>&1 || true
    fi

    ufw reload >/dev/null 2>&1 || true

    if ufw status 2>/dev/null | grep -Eq "^${port}/tcp[[:space:]]"; then
        LOGI "已通过 UFW 放行面板端口 ${port}/tcp"
        if [[ "${ssh_port}" != "${port}" ]]; then
            LOGI "已通过 UFW 保留 SSH 端口 ${ssh_port}/tcp"
        fi
        return 0
    fi

    return 1
}

allow_port_in_firewall() {
    local port="$1"
    local opened=0

    [[ -z "${port}" ]] && return 0

    if command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            if firewall-cmd --quiet --query-port="${port}/tcp" >/dev/null 2>&1; then
                LOGI "已在 firewalld 中放行面板端口 ${port}/tcp"
                opened=1
            fi
        fi
    fi

    if allow_port_via_ufw "${port}"; then
        opened=1
    fi

    if [[ ${opened} -eq 0 ]]; then
        yellow "未检测到可用的 firewalld/UFW，已跳过自动放行面板端口。"
    fi
}

random_port() {
    while true; do
        local candidate=$((RANDOM % 55536 + 10000))
        if ! port_in_use "${candidate}"; then
            echo "${candidate}"
            return 0
        fi
    done
}

normalize_base_path() {
    local value="$1"
    if [[ -z "${value}" ]]; then
        value="$(random_string 3)"
    fi
    if [[ "${value}" == "/" ]]; then
        echo "/"
        return 0
    fi
    value="${value#/}"
    value="${value%/}"
    echo "/${value}/"
}

prompt_panel_username() {
    local username=""
    while true; do
        readp "设置 sx-ui 登录用户名（回车自动生成随机 6 位字符）：" username
        [[ -z "${username}" ]] && username="$(random_string 6)"
        if [[ "${username}" == *admin* ]]; then
            LOGE "用户名中不能包含 admin，请重新输入。"
            continue
        fi
        echo "${username}"
        return 0
    done
}

prompt_panel_password() {
    local password=""
    while true; do
        readp "设置 sx-ui 登录密码（回车自动生成随机 6 位字符）：" password
        [[ -z "${password}" ]] && password="$(random_string 6)"
        if [[ "${password}" == *admin* ]]; then
            LOGE "密码中不能包含 admin，请重新输入。"
            continue
        fi
        echo "${password}"
        return 0
    done
}

prompt_panel_port() {
    local port=""
    while true; do
        readp "设置 sx-ui 面板端口[1-65535]（回车自动生成随机端口）：" port
        [[ -z "${port}" ]] && port="$(random_port)"
        if [[ ! "${port}" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
            LOGE "端口必须是 1-65535 之间的数字。"
            continue
        fi
        if port_in_use "${port}"; then
            LOGE "端口 ${port} 已被占用，请重新输入。"
            continue
        fi
        echo "${port}"
        return 0
    done
}

prompt_panel_base_path() {
    local base_path=""
    readp "设置 sx-ui 面板根路径（回车自动生成随机 3 位字符，输入 / 表示根目录）：" base_path
    normalize_base_path "${base_path}"
}

load_panel_settings() {
    setting_dump=$(/usr/local/sx-ui/sx-ui setting -show true 2>/dev/null)
    current_username=$(echo "${setting_dump}" | awk -F': ' '$1=="username"{print $2}')
    current_password=$(echo "${setting_dump}" | awk -F': ' '$1=="userpasswd"{print $2}')
    current_port=$(echo "${setting_dump}" | awk -F': ' '$1=="port"{print $2}')
    current_base_path=$(echo "${setting_dump}" | awk -F': ' '$1=="webBasePath"{print $2}')
    current_cert_file=$(echo "${setting_dump}" | awk -F': ' '$1=="webCertFile"{print $2}')
    current_key_file=$(echo "${setting_dump}" | awk -F': ' '$1=="webKeyFile"{print $2}')
    current_nginx_proxy_enabled=$(echo "${setting_dump}" | awk -F': ' '$1=="webNginxProxyEnable"{print $2}')
    current_nginx_proxy_host=$(echo "${setting_dump}" | awk -F': ' '$1=="webNginxProxyHost"{print $2}')
    current_nginx_proxy_https=$(echo "${setting_dump}" | awk -F': ' '$1=="webNginxProxyHTTPS"{print $2}')
    [[ -z "${current_base_path}" ]] && current_base_path="/"
    [[ -z "${current_nginx_proxy_enabled}" ]] && current_nginx_proxy_enabled="false"
    [[ -z "${current_nginx_proxy_https}" ]] && current_nginx_proxy_https="false"
    current_cert_host="$(extract_certificate_primary_host "${current_cert_file}")"
}

extract_certificate_primary_host() {
    local cert_file="$1"
    local san_output=""
    local domain=""

    [[ -z "${cert_file}" || ! -f "${cert_file}" ]] && return 0
    command -v openssl >/dev/null 2>&1 || return 0

    san_output=$(openssl x509 -in "${cert_file}" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' | sed 's/^ *//')
    domain=$(echo "${san_output}" | awk -F: '/^DNS:/{print $2}' | sed 's/^[*.]*//' | sed '/^$/d' | head -n 1)
    if [[ -n "${domain}" ]]; then
        echo "${domain}"
        return 0
    fi

    domain=$(openssl x509 -in "${cert_file}" -noout -subject 2>/dev/null | sed -n 's/.*CN *= *//p' | sed 's/^[*.]*//' | head -n 1)
    echo "${domain}"
}

get_local_ipv4() {
    get_public_ipv4
}

get_local_ipv6() {
    get_public_ipv6
}

show_access_info() {
    local ipv4=""
    local ipv6=""
    local protocol="http"
    local proxy_protocol="http"

    load_panel_settings
    [[ -n "${current_cert_file}" && -n "${current_key_file}" ]] && protocol="https"
    ipv4="$(get_local_ipv4)"
    ipv6="$(get_local_ipv6)"

    if [[ "${current_nginx_proxy_enabled}" == "true" && -n "${current_nginx_proxy_host}" ]]; then
        [[ "${current_nginx_proxy_https}" == "true" ]] && proxy_protocol="https"
        echo -e "反代登录: ${blue}${proxy_protocol}://${current_nginx_proxy_host}${current_base_path}${plain}"
        return 0
    fi

    if [[ "${protocol}" == "https" && -n "${current_cert_host}" && -n "${current_port}" ]]; then
        echo -e "安全域名登录: ${blue}${protocol}://${current_cert_host}:${current_port}${current_base_path}${plain}"
    fi

    if [[ -n "${current_port}" ]]; then
        if [[ -n "${ipv4}" ]]; then
            echo -e "登录地址: ${blue}${protocol}://${ipv4}:${current_port}${current_base_path}${plain}"
        fi
        if [[ -n "${ipv6}" ]]; then
            echo -e "登录地址: ${blue}${protocol}://[${ipv6}]:${current_port}${current_base_path}${plain}"
        fi
    fi
}

install() {
    SX_UI_MANAGED_INSTALL=1 bash <(curl -Ls https://raw.githubusercontent.com/sx-ui2/sx-ui/main/install.sh)
    local install_status=$?
    [[ ${install_status} -eq ${post_install_exit_code} ]] && return 0
    return ${install_status}
}

update() {
    confirm "本功能会重装当前最新版，数据不会丢失，是否继续？" "n"
    if [[ $? != 0 ]]; then
        LOGD "已取消更新"
        [[ $# -eq 0 ]] && before_show_menu
        return 0
    fi
    SX_UI_MANAGED_INSTALL=1 bash <(curl -Ls https://raw.githubusercontent.com/sx-ui2/sx-ui/main/install.sh)
    local install_status=$?
    if [[ ${install_status} -eq 0 || ${install_status} -eq ${post_install_exit_code} ]]; then
        LOGI "更新完成"
        return 0
    fi
    return ${install_status}
}

uninstall() {
    local uninstall_confirm=""
    local cleanup_camouflage="n"

    yellow "本次卸载将清除所有数据，建议如下："
    yellow "一、点击 sx-ui 面板中的“备份与恢复”，下载备份文件 sx-ui.db"
    yellow "二、手动备份 /etc/sx-ui/ 目录中的数据库与证书文件"
    echo
    readp "确定卸载，请按回车（退出请按 Ctrl+C）:" uninstall_confirm
    if [[ -n "${uninstall_confirm}" ]]; then
        LOGE "输入有误，卸载已取消。"
        [[ $# -eq 0 ]] && before_show_menu
        return 0
    fi

    confirm "是否同时彻底清理伪装网站环境？这会删除 sx-ui 托管站点、关联数据库、默认站点包装、SNI 分流和网站附加配置，但不会卸载系统 nginx/php/mysql 软件包。" "n"
    if [[ $? == 0 ]]; then
        cleanup_camouflage="y"
    fi

    if [[ "${cleanup_camouflage}" == "y" ]]; then
        /usr/local/sx-ui/sx-ui cleanup -camouflage
        if [[ $? -ne 0 ]]; then
            LOGE "彻底清理伪装网站环境失败，已中止卸载。"
            [[ $# -eq 0 ]] && before_show_menu
            return 1
        fi
    fi

    systemctl stop sx-ui >/dev/null 2>&1
    systemctl disable sx-ui >/dev/null 2>&1
    rm -f /etc/systemd/system/sx-ui.service
    systemctl daemon-reload >/dev/null 2>&1
    systemctl reset-failed >/dev/null 2>&1
    rm -f /usr/bin/sx-ui
    rm -rf /etc/sx-ui
    rm -rf /usr/local/sx-ui

    echo
    green "sx-ui 已卸载完成。"
    echo
    blue "欢迎继续使用 sx-ui：bash <(curl -Ls https://raw.githubusercontent.com/sx-ui2/sx-ui/main/install.sh)"
}

change_auth() {
    local username=""
    local password=""
    username="$(prompt_panel_username)"
    echo
    password="$(prompt_panel_password)"
    /usr/local/sx-ui/sx-ui setting -username "${username}" -password "${password}"
    LOGI "用户名和密码修改成功"
    confirm_restart "$@"
}

set_panel_port() {
    local port=""
    port="$(prompt_panel_port)"
    /usr/local/sx-ui/sx-ui setting -port "${port}"
    allow_port_in_firewall "${port}"
    LOGI "面板端口已修改为 ${port}"
    confirm_restart "$@"
}

set_panel_base_path() {
    local base_path=""
    base_path="$(prompt_panel_base_path)"
    /usr/local/sx-ui/sx-ui setting -webBasePath "${base_path}"
    LOGI "面板根路径已修改为 ${base_path}"
    confirm_restart "$@"
}

reset_config() {
    confirm "确定要重置所有面板设置吗？账号数据不会丢失，用户名和密码不会改变。" "n"
    if [[ $? != 0 ]]; then
        [[ $# -eq 0 ]] && before_show_menu
        return 0
    fi
    /usr/local/sx-ui/sx-ui setting -reset
    LOGI "面板设置已恢复为默认值。"
    echo
    yellow "请重新设置面板端口和根路径。"
    local port=""
    local base_path=""
    port="$(prompt_panel_port)"
    echo
    base_path="$(prompt_panel_base_path)"
    /usr/local/sx-ui/sx-ui setting -port "${port}" -webBasePath "${base_path}"
    allow_port_in_firewall "${port}"
    LOGI "默认设置已重新写回"
    confirm_restart "$@"
}

check_config() {
    load_panel_settings
    echo
    echo "${setting_dump}"
    [[ $# -eq 0 ]] && before_show_menu
}

confirm_restart() {
    confirm "是否现在重启面板？" "y"
    if [[ $? == 0 ]]; then
        if [[ $# -eq 0 ]]; then
            restart
        else
            restart 0
        fi
    else
        if [[ $# -eq 0 ]]; then
            show_menu
        fi
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        LOGI "面板已运行，无需重复启动。"
    else
        systemctl start sx-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "sx-ui 启动成功"
        else
            LOGE "sx-ui 启动失败，请稍后查看日志。"
        fi
    fi
    [[ $# -eq 0 ]] && before_show_menu
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        LOGI "面板已停止，无需重复停止。"
    else
        systemctl stop sx-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "sx-ui 已停止"
        else
            LOGE "sx-ui 停止失败，请稍后查看日志。"
        fi
    fi
    [[ $# -eq 0 ]] && before_show_menu
}

restart() {
    systemctl restart sx-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "sx-ui 重启成功"
    else
        LOGE "sx-ui 重启失败，请稍后查看日志。"
    fi
    [[ $# -eq 0 ]] && before_show_menu
}

status() {
    systemctl status sx-ui -l --no-pager
    [[ $# -eq 0 ]] && before_show_menu
}

enable() {
    systemctl enable sx-ui >/dev/null 2>&1
    if [[ $? == 0 ]]; then
        LOGI "sx-ui 已设置为开机自启"
    else
        LOGE "sx-ui 设置开机自启失败"
    fi
    [[ $# -eq 0 ]] && before_show_menu
}

disable() {
    systemctl disable sx-ui >/dev/null 2>&1
    if [[ $? == 0 ]]; then
        LOGI "sx-ui 已取消开机自启"
    else
        LOGE "sx-ui 取消开机自启失败"
    fi
    [[ $# -eq 0 ]] && before_show_menu
}

show_log() {
    journalctl -u sx-ui.service -e --no-pager -f
    [[ $# -eq 0 ]] && before_show_menu
}

install_bbr() {
    local script_path="/tmp/tcpx.sh"
    yellow "开始准备 Linux-NetSpeed 网络加速脚本环境..."
    if [[ "${release}" == "centos" ]]; then
        yum install -y ca-certificates wget >/dev/null 2>&1 || yum install -y ca-certificates wget
        update-ca-trust force-enable >/dev/null 2>&1 || true
    else
        apt-get update -y >/dev/null 2>&1 || apt-get update -y
        apt-get install -y ca-certificates wget >/dev/null 2>&1 || apt-get install -y ca-certificates wget
        update-ca-certificates >/dev/null 2>&1 || true
    fi

    yellow "开始下载 Linux-NetSpeed 管理脚本..."
    wget -O "${script_path}" --no-check-certificate https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh
    if [[ $? -ne 0 ]]; then
        LOGE "下载 Linux-NetSpeed 脚本失败，请检查当前服务器是否可以访问 Github。"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi

    chmod +x "${script_path}"
    bash "${script_path}"
    rm -f "${script_path}"
    [[ $# -eq 0 ]] && before_show_menu
}

sync_bundled_shell() {
    local bundled_script="/usr/local/sx-ui/sx-ui.sh"

    if [[ ! -f "${bundled_script}" ]]; then
        LOGE "当前安装目录中未找到同版管理脚本：${bundled_script}"
        return 1
    fi

    cp -f "${bundled_script}" /usr/bin/sx-ui
    chmod +x /usr/bin/sx-ui
    return 0
}

update_shell() {
    yellow "开始同步当前安装版本附带的管理脚本..."
    sync_bundled_shell
    if [[ $? != 0 ]]; then
        [[ $# -eq 0 ]] && before_show_menu
    else
        LOGI "管理脚本已同步为当前安装版本，请重新运行 sx-ui"
        exit 0
    fi
}

check_status() {
    if [[ ! -f /etc/systemd/system/sx-ui.service ]]; then
        return 2
    fi
    local temp
    temp=$(systemctl status sx-ui 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ "${temp}" == "running" ]]; then
        return 0
    fi
    return 1
}

check_enabled() {
    local temp
    temp=$(systemctl is-enabled sx-ui 2>/dev/null)
    [[ "${temp}" == "enabled" ]]
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        LOGE "sx-ui 已安装，请不要重复安装。"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi
    return 0
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        LOGE "请先安装 sx-ui。"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi
    return 0
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "面板状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "面板状态: ${yellow}未运行${plain}"
            ;;
        2)
            echo -e "面板状态: ${red}未安装${plain}"
            ;;
    esac
    show_enable_status
    show_xray_status
    show_singbox_status
}

show_enable_status() {
    if check_enabled; then
        echo -e "开机自启: ${green}已启用${plain}"
    else
        echo -e "开机自启: ${red}未启用${plain}"
    fi
}

check_xray_status() {
    pgrep -f "xray-linux" >/dev/null 2>&1
}

show_xray_status() {
    if check_xray_status; then
        echo -e "xray 状态: ${green}运行中${plain}"
    else
        echo -e "xray 状态: ${red}未运行${plain}"
    fi
}

check_singbox_status() {
    pgrep -f "sing-box-linux" >/dev/null 2>&1
}

show_singbox_status() {
    if check_singbox_status; then
        echo -e "sing-box 状态: ${green}运行中${plain}"
    else
        echo -e "sing-box 状态: ${red}未运行${plain}"
    fi
}

show_panel_summary() {
    if [[ ! -x /usr/local/sx-ui/sx-ui ]]; then
        echo -e "当前版本: ${yellow}未安装${plain}"
        return 0
    fi

    local version=""
    version=$(/usr/local/sx-ui/sx-ui -v 2>/dev/null)
    [[ -z "${version}" ]] && version="未知"
    load_panel_settings

    echo -e "当前版本: ${bblue}${version}${plain}"
    latest_release_version="$(resolve_latest_sxui_release)"
    if [[ -n "${latest_release_version}" ]]; then
        if version_lt "${version}" "${latest_release_version}"; then
            echo -e "最新版本: ${yellow}${latest_release_version}${plain}  ${yellow}(可选择 2 更新)${plain}"
        else
            echo -e "最新版本: ${green}${latest_release_version}${plain}"
        fi
    fi
    echo -e "面板用户名: ${green}${current_username}${plain}"
    echo -e "面板密码: ${green}${current_password}${plain}"
    echo -e "面板端口: ${green}${current_port}${plain}"
    echo -e "面板根路径: ${green}${current_base_path}${plain}"
    if [[ "${current_nginx_proxy_enabled}" == "true" ]]; then
        echo -e "访问方式: ${green}Nginx 反代${plain}"
        if [[ -n "${current_nginx_proxy_host}" ]]; then
            if [[ "${current_nginx_proxy_https}" == "true" ]]; then
                echo -e "反代域名: ${green}https://${current_nginx_proxy_host}${current_base_path}${plain}"
            else
                echo -e "反代域名: ${yellow}http://${current_nginx_proxy_host}${current_base_path}${plain}"
            fi
        fi
    elif [[ -n "${current_cert_file}" && -n "${current_key_file}" ]]; then
        echo -e "证书状态: ${green}已配置 HTTPS${plain}"
    else
        echo -e "证书状态: ${yellow}未配置，当前将使用 HTTP${plain}"
    fi
    show_access_info
}

show_system_summary() {
    local pretty_name=""
    local kernel_version=""
    local cpu_arch=""
    local virt_type=""
    local bbr_algo=""

    pretty_name="$(get_system_pretty_name)"
    kernel_version="$(get_kernel_version)"
    cpu_arch="$(get_cpu_arch)"
    virt_type="$(get_virtualization_type)"
    bbr_algo="$(get_bbr_algo)"

    echo -e "系统: ${blue}${pretty_name}${plain}  内核: ${blue}${kernel_version}${plain}  架构: ${blue}${cpu_arch}${plain}  虚拟化: ${blue}${virt_type}${plain}  BBR: ${blue}${bbr_algo}${plain}"
}

show_menu() {
    clear
    print_cli_header "管理脚本"
    show_system_summary
    echo "------------------------------------------------------------------------------------"
    show_status
    echo "------------------------------------------------------------------------------------"
    show_panel_summary
    echo "------------------------------------------------------------------------------------"
    green " 1. 一键安装 sx-ui"
    green " 2. 更新 sx-ui"
    green " 3. 卸载 sx-ui"
    echo "------------------------------------------------------------------------------------"
    green " 4. 变更面板用户名和密码"
    green " 5. 变更面板端口"
    green " 6. 变更面板根路径"
    green " 7. 重置面板设置"
    green " 8. 查看当前面板设置"
    echo "------------------------------------------------------------------------------------"
    green " 9. 启动 sx-ui"
    green "10. 停止 sx-ui"
    green "11. 重启 sx-ui"
    green "12. 查看 sx-ui 状态"
    green "13. 查看 sx-ui 日志"
    echo "------------------------------------------------------------------------------------"
    green "14. 设置开机自启"
    green "15. 取消开机自启"
    green "16. 同步管理脚本"
    green "17. 管理 BBR / 网络加速"
    echo "------------------------------------------------------------------------------------"
    green " 0. 退出脚本"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo
    readp "请输入数字【0-17】：" num

    case "${num}" in
        0) exit 0 ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && change_auth ;;
        5) check_install && set_panel_port ;;
        6) check_install && set_panel_base_path ;;
        7) check_install && reset_config ;;
        8) check_install && check_config ;;
        9) check_install && start ;;
        10) check_install && stop ;;
        11) check_install && restart ;;
        12) check_install && status ;;
        13) check_install && show_log ;;
        14) check_install && enable ;;
        15) check_install && disable ;;
        16) update_shell ;;
        17) install_bbr ;;
        *) LOGE "请输入正确的数字【0-17】" && before_show_menu ;;
    esac
}

detect_release
check_os_version
ensure_nat64_for_ipv6_only

if [[ $# -gt 0 ]]; then
    case "$1" in
        start) check_install 0 && start 0 ;;
        stop) check_install 0 && stop 0 ;;
        restart) check_install 0 && restart 0 ;;
        status) check_install 0 && status 0 ;;
        enable) check_install 0 && enable 0 ;;
        disable) check_install 0 && disable 0 ;;
        log) check_install 0 && show_log 0 ;;
        update) check_install 0 && update 0 ;;
        install) check_uninstall 0 && install 0 ;;
        uninstall) check_install 0 && uninstall 0 ;;
        change-auth) check_install 0 && change_auth 0 ;;
        set-port) check_install 0 && set_panel_port 0 ;;
        set-base-path) check_install 0 && set_panel_base_path 0 ;;
        reset-config) check_install 0 && reset_config 0 ;;
        show-config) check_install 0 && check_config 0 ;;
        update-shell) update_shell 0 ;;
        sync-shell) update_shell 0 ;;
        bbr) install_bbr 0 ;;
        menu) show_menu ;;
        *) exit 0 ;;
    esac
else
    show_menu
fi
