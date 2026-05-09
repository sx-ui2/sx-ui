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

print_cli_header() {
    local subtitle="${1:-安装脚本}"
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

[[ $EUID -ne 0 ]] && red "错误：必须使用 root 用户运行此脚本！" && exit 1

release=""
arch=""
os_version=""
panel_username=""
panel_password=""
panel_port=""
panel_base_path=""
panel_cert_enabled=0
panel_cert_host=""
panel_nginx_proxy_enabled="false"
panel_nginx_proxy_host=""
panel_nginx_proxy_https="false"
existing_install=0
v4=""
v6=""
wgcfv4=""
wgcfv6=""
managed_singbox_repo="sx-ui2/sx-ui-runtime"
managed_singbox_tag_prefix="sing-box-stats-v"
ssh_tunnel_local_port="18080"
post_install_exit_code=10

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
        red "未检测到系统版本，请使用 Ubuntu / Debian / CentOS。" && exit 1
    fi
}

detect_arch() {
    local raw_arch
    raw_arch=$(uname -m)
    case "${raw_arch}" in
        x86_64 | x64 | amd64)
            arch="amd64"
            ;;
        aarch64 | arm64)
            arch="arm64"
            ;;
        s390x)
            arch="s390x"
            ;;
        *)
            red "暂不支持当前架构：${raw_arch}" && exit 1
            ;;
    esac
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
            [[ -n "${os_version}" && ${os_version} -le 6 ]] && red "请使用 CentOS 7 或更高版本的系统！" && exit 1
            ;;
        ubuntu)
            [[ -n "${os_version}" && ${os_version} -lt 16 ]] && red "请使用 Ubuntu 16 或更高版本的系统！" && exit 1
            ;;
        debian)
            [[ -n "${os_version}" && ${os_version} -lt 8 ]] && red "请使用 Debian 8 或更高版本的系统！" && exit 1
            ;;
    esac

    if [[ $(getconf WORD_BIT) != "32" || $(getconf LONG_BIT) != "64" ]]; then
        red "本软件仅支持 64 位系统。" && exit 1
    fi
}

get_system_pretty_name() {
    if [[ -f /etc/os-release ]]; then
        awk -F= '/^PRETTY_NAME=/{gsub(/"/, "", $2); print $2}' /etc/os-release
    else
        uname -s
    fi
}

get_kernel_version() {
    uname -r | cut -d "-" -f 1
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

    echo -e "系统：${blue}${pretty_name}${plain}  内核：${blue}${kernel_version}${plain}  架构：${blue}${cpu_arch}${plain}  虚拟化：${blue}${virt_type}${plain}  BBR：${blue}${bbr_algo}${plain}"
}

install_base() {
    yellow "开始安装必要依赖..."
    if [[ "${release}" == "centos" ]]; then
        yum install -y curl wget tar >/dev/null 2>&1 || yum install -y curl wget tar
    else
        apt-get update -y >/dev/null 2>&1 || apt-get update -y
        apt-get install -y curl wget tar >/dev/null 2>&1 || apt-get install -y curl wget tar
    fi
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

resolve_latest_managed_singbox_release() {
    curl -Ls "https://api.github.com/repos/${managed_singbox_repo}/releases?per_page=50" \
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | grep "^${managed_singbox_tag_prefix}" \
        | head -n 1
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
            green "检测到纯 IPv6 VPS，NAT64/DNS64 解析已存在。"
        else
            yellow "检测到纯 IPv6 VPS，自动添加 NAT64/DNS64 解析。"
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

random_port() {
    while true; do
        local candidate=$((RANDOM % 55536 + 10000))
        if ! port_in_use "${candidate}"; then
            echo "${candidate}"
            return 0
        fi
    done
}

port_in_use() {
    local port="$1"
    ss -lntup 2>/dev/null | awk 'NR>1 {print $5}' | grep -Eq "[:.]${port}$"
}

is_valid_tcp_port() {
    local port="$1"
    [[ "${port}" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

detect_current_session_ssh_port() {
    local port=""

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        port=$(awk '{print $4}' <<< "${SSH_CONNECTION}")
        if is_valid_tcp_port "${port}"; then
            echo "${port}"
            return 0
        fi
    fi

    if [[ -n "${SSH_CLIENT:-}" ]]; then
        port=$(awk '{print $3}' <<< "${SSH_CLIENT}")
        if is_valid_tcp_port "${port}"; then
            echo "${port}"
            return 0
        fi
    fi

    return 1
}

detect_listening_ssh_port() {
    local ports=""
    local port=""

    if command -v ss >/dev/null 2>&1; then
        ports=$(ss -lntp 2>/dev/null | awk '
            NR > 1 && $0 ~ /(sshd|ssh\.socket)/ {
                listen = $4
                sub(/^.*:/, "", listen)
                gsub(/[\[\]]/, "", listen)
                if (listen ~ /^[0-9]+$/) print listen
            }
        ' | sort -n -u)
    elif command -v netstat >/dev/null 2>&1; then
        ports=$(netstat -lntp 2>/dev/null | awk '
            NR > 2 && $0 ~ /(sshd|ssh\.socket)/ {
                listen = $4
                sub(/^.*:/, "", listen)
                gsub(/[\[\]]/, "", listen)
                if (listen ~ /^[0-9]+$/) print listen
            }
        ' | sort -n -u)
    fi

    for port in ${ports}; do
        if is_valid_tcp_port "${port}" && [[ "${port}" != "22" ]]; then
            echo "${port}"
            return 0
        fi
    done

    for port in ${ports}; do
        if is_valid_tcp_port "${port}"; then
            echo "${port}"
            return 0
        fi
    done

    return 1
}

detect_effective_sshd_port() {
    local port=""

    command -v sshd >/dev/null 2>&1 || return 1
    port=$(sshd -T 2>/dev/null | awk '/^port[[:space:]]+[0-9]+/{print $2; exit}')
    if is_valid_tcp_port "${port}"; then
        echo "${port}"
        return 0
    fi

    return 1
}

detect_configured_ssh_port() {
    local port=""

    port=$(awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ {print $2}' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -n 1)
    if is_valid_tcp_port "${port}"; then
        echo "${port}"
        return 0
    fi

    return 1
}

current_ssh_port() {
    detect_current_session_ssh_port \
        || detect_listening_ssh_port \
        || detect_effective_sshd_port \
        || detect_configured_ssh_port \
        || echo "22"
}

allow_port_via_ufw() {
    local port="$1"
    local ssh_port=""

    command -v ufw >/dev/null 2>&1 || return 1
    if ! ufw status 2>/dev/null | grep -q "^Status: active"; then
        return 1
    fi

    ssh_port="$(current_ssh_port)"
    ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
    ufw allow "${port}/tcp" >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true

    if ufw status 2>/dev/null | grep -Eq "^${port}/tcp[[:space:]]"; then
        green "已通过 UFW 放行面板端口 ${port}/tcp"
        if [[ "${ssh_port}" != "${port}" ]]; then
            green "已通过 UFW 保留 SSH 端口 ${ssh_port}/tcp"
        fi
        return 0
    fi

	return 1
}

persist_iptables_rules() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || true
        return 0
    fi

    if [[ -d /etc/iptables ]]; then
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save >/etc/iptables/rules.v4 2>/dev/null || true
        fi
        if command -v ip6tables-save >/dev/null 2>&1; then
            ip6tables-save >/etc/iptables/rules.v6 2>/dev/null || true
        fi
        return 0
    fi

    if command -v service >/dev/null 2>&1; then
        service iptables save >/dev/null 2>&1 || true
        service ip6tables save >/dev/null 2>&1 || true
        return 0
    fi

    return 1
}

allow_port_via_iptables_cmd() {
    local cmd="$1"
    local port="$2"

    command -v "${cmd}" >/dev/null 2>&1 || return 1
    "${cmd}" -C INPUT -p tcp --dport "${port}" -j ACCEPT >/dev/null 2>&1 || \
        "${cmd}" -I INPUT -p tcp --dport "${port}" -j ACCEPT >/dev/null 2>&1 || return 1
    return 0
}

allow_port_via_iptables() {
    local port="$1"
    local ssh_port=""
    local panel_opened=0
    local ssh_opened=0

    ssh_port="$(current_ssh_port)"
    if allow_port_via_iptables_cmd iptables "${ssh_port}"; then
        ssh_opened=1
    fi
    if allow_port_via_iptables_cmd iptables "${port}"; then
        panel_opened=1
    fi
    allow_port_via_iptables_cmd ip6tables "${ssh_port}" || true
    allow_port_via_iptables_cmd ip6tables "${port}" || true

    if [[ ${panel_opened} -eq 1 ]]; then
        green "已通过 iptables 增量放行面板端口 ${port}/tcp"
        if [[ "${ssh_port}" != "${port}" && ${ssh_opened} -eq 1 ]]; then
            green "已通过 iptables 保留 SSH 端口 ${ssh_port}/tcp"
        fi
        if ! persist_iptables_rules; then
            yellow "iptables 规则已临时生效，但未检测到持久化工具，重启后可能失效。"
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
                green "已在 firewalld 中放行面板端口 ${port}/tcp"
                opened=1
            fi
        fi
    fi

	if [[ ${opened} -eq 0 ]] && allow_port_via_ufw "${port}"; then
		opened=1
	fi

    if [[ ${opened} -eq 0 ]] && allow_port_via_iptables "${port}"; then
        opened=1
    fi

	if [[ ${opened} -eq 0 ]]; then
		yellow "未检测到可用的 firewalld/UFW/iptables，已跳过自动放行面板端口。"
	fi
}

enable_firewall_for_first_install() {
    local ssh_port=""

    ssh_port="$(current_ssh_port)"

    if command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            return 0
        fi
        if command -v firewall-offline-cmd >/dev/null 2>&1; then
            firewall-offline-cmd --add-service=ssh >/dev/null 2>&1 || true
            firewall-offline-cmd --add-port="${ssh_port}/tcp" >/dev/null 2>&1 || true
        fi
        systemctl enable firewalld >/dev/null 2>&1 || true
        if systemctl start firewalld >/dev/null 2>&1; then
            firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
            firewall-cmd --permanent --add-port="${ssh_port}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            green "已启用 firewalld，并保留 SSH 端口 ${ssh_port}/tcp"
            return 0
        fi
    fi

    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q "^Status: active"; then
            return 0
        fi
        ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
        if ufw --force enable >/dev/null 2>&1; then
            green "已启用 UFW，并保留 SSH 端口 ${ssh_port}/tcp"
            return 0
        fi
    fi

    yellow "未检测到可启用的 firewalld/UFW，已跳过自动启用防火墙。"
    return 1
}

sync_management_script() {
    local bundled_script="/usr/local/sx-ui/sx-ui.sh"

    if [[ ! -f "${bundled_script}" ]]; then
        red "安装包内未找到管理脚本 ${bundled_script}，无法完成同步。"
        exit 1
    fi

    cp -f "${bundled_script}" /usr/bin/sx-ui
    chmod +x /usr/bin/sx-ui
}

check_panel_runtime_status() {
    systemctl is-active --quiet sx-ui >/dev/null 2>&1
}

check_panel_boot_enabled() {
    [[ "$(systemctl is-enabled sx-ui 2>/dev/null)" == "enabled" ]]
}

check_xray_runtime_status() {
    pgrep -f "xray-linux" >/dev/null 2>&1
}

check_singbox_runtime_status() {
    pgrep -f "sing-box-linux" >/dev/null 2>&1
}

check_nginx_runtime_status() {
    systemctl is-active --quiet nginx >/dev/null 2>&1
}

enable_panel_autostart() {
    if systemctl enable sx-ui >/dev/null 2>&1; then
        green "已自动设置 sx-ui 开机自启。"
    else
        red "自动设置 sx-ui 开机自启失败，请安装完成后手动执行。"
    fi
}

install_managed_singbox_runtime() {
    local release_tag=""
    local version=""
    local archive_name=""
    local archive_url=""
    local extract_dir=""
    local tmp_dir=""

    if [[ "${arch}" != "amd64" && "${arch}" != "arm64" ]]; then
        yellow "当前架构 ${arch} 暂不支持自动替换为 sing-box stats 内核，已跳过。"
        return 0
    fi

    release_tag="$(resolve_latest_managed_singbox_release)"
    if [[ -z "${release_tag}" ]]; then
        yellow "未找到可用的 sing-box stats release，保留安装包内的 sing-box 内核。"
        return 0
    fi

    version="${release_tag#${managed_singbox_tag_prefix}}"
    archive_name="sing-box-${version}-linux-${arch}-stats.tar.gz"
    archive_url="https://github.com/${managed_singbox_repo}/releases/download/${release_tag}/${archive_name}"
    tmp_dir="/tmp/sx-ui-singbox-stats-${arch}"
    extract_dir="${tmp_dir}/sing-box-${version}-linux-${arch}-stats"

    rm -rf "${tmp_dir}"
    mkdir -p "${tmp_dir}"

    yellow "同步 sing-box stats 内核 ${version} (${arch})..."
    if ! wget -N --no-check-certificate -O "${tmp_dir}/${archive_name}" "${archive_url}"; then
        yellow "下载 sing-box stats 内核失败，保留安装包内的 sing-box 内核。"
        rm -rf "${tmp_dir}"
        return 0
    fi

    if ! tar zxf "${tmp_dir}/${archive_name}" -C "${tmp_dir}"; then
        yellow "解压 sing-box stats 内核失败，保留安装包内的 sing-box 内核。"
        rm -rf "${tmp_dir}"
        return 0
    fi

    if [[ ! -f "${extract_dir}/sing-box" ]]; then
        yellow "sing-box stats 内核文件缺失，保留安装包内的 sing-box 内核。"
        rm -rf "${tmp_dir}"
        return 0
    fi

    cp -f "${extract_dir}/sing-box" "/usr/local/sx-ui/bin/sing-box-linux-${arch}"
    if [[ -f "${extract_dir}/libcronet.so" ]]; then
        cp -f "${extract_dir}/libcronet.so" "/usr/local/sx-ui/bin/libcronet.so"
        chmod +x "/usr/local/sx-ui/bin/libcronet.so" 2>/dev/null || true
    fi
    chmod +x "/usr/local/sx-ui/bin/sing-box-linux-${arch}" 2>/dev/null || true
    rm -rf "${tmp_dir}"
    green "已切换为支持流量统计的 sing-box stats 内核 ${version}。"
}

preserve_runtime_binaries() {
    local source_bin_dir="/usr/local/sx-ui/bin"
    local preserve_dir="$1"
    local file=""

    [[ -d "${source_bin_dir}" ]] || return 0

    mkdir -p "${preserve_dir}"
    for file in \
        "xray-linux-${arch}" \
        "sing-box-linux-${arch}" \
        "sing-box-linux-${arch}-build-info.json" \
        "masque-warp-linux-${arch}" \
        "libcronet.so"; do
        if [[ -f "${source_bin_dir}/${file}" ]]; then
            cp -f "${source_bin_dir}/${file}" "${preserve_dir}/${file}"
        fi
    done
}

restore_runtime_binaries() {
    local preserve_dir="$1"
    local target_bin_dir="/usr/local/sx-ui/bin"
    local file=""

    [[ -d "${preserve_dir}" ]] || return 0

    mkdir -p "${target_bin_dir}"
    for file in \
        "xray-linux-${arch}" \
        "sing-box-linux-${arch}" \
        "sing-box-linux-${arch}-build-info.json" \
        "masque-warp-linux-${arch}" \
        "libcronet.so"; do
        if [[ -f "${preserve_dir}/${file}" ]]; then
            cp -f "${preserve_dir}/${file}" "${target_bin_dir}/${file}"
        fi
    done

    chmod +x "${target_bin_dir}/xray-linux-${arch}" 2>/dev/null || true
    chmod +x "${target_bin_dir}/sing-box-linux-${arch}" 2>/dev/null || true
    chmod +x "${target_bin_dir}/masque-warp-linux-${arch}" 2>/dev/null || true
    chmod +x "${target_bin_dir}/libcronet.so" 2>/dev/null || true
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

get_local_ipv4() {
    get_public_ipv4
}

get_local_ipv6() {
    get_public_ipv6
}

load_current_panel_settings() {
    local setting_dump=""
    setting_dump=$(/usr/local/sx-ui/sx-ui setting -show true 2>/dev/null)
    panel_cert_enabled=0
    panel_cert_host=""
    panel_username=$(echo "${setting_dump}" | awk -F': ' '$1=="username"{print $2}')
    panel_password=$(echo "${setting_dump}" | awk -F': ' '$1=="userpasswd"{print $2}')
    panel_port=$(echo "${setting_dump}" | awk -F': ' '$1=="port"{print $2}')
    panel_base_path=$(echo "${setting_dump}" | awk -F': ' '$1=="webBasePath"{print $2}')
    panel_nginx_proxy_enabled=$(echo "${setting_dump}" | awk -F': ' '$1=="webNginxProxyEnable"{print $2}')
    panel_nginx_proxy_host=$(echo "${setting_dump}" | awk -F': ' '$1=="webNginxProxyHost"{print $2}')
    panel_nginx_proxy_https=$(echo "${setting_dump}" | awk -F': ' '$1=="webNginxProxyHTTPS"{print $2}')
    local cert_file=""
    local key_file=""
    cert_file=$(echo "${setting_dump}" | awk -F': ' '$1=="webCertFile"{print $2}')
    key_file=$(echo "${setting_dump}" | awk -F': ' '$1=="webKeyFile"{print $2}')
    [[ -z "${panel_base_path}" ]] && panel_base_path="/"
    [[ -z "${panel_nginx_proxy_enabled}" ]] && panel_nginx_proxy_enabled="false"
    [[ -z "${panel_nginx_proxy_https}" ]] && panel_nginx_proxy_https="false"
    if [[ -n "${cert_file}" && -n "${key_file}" && -f "${cert_file}" && -f "${key_file}" ]]; then
        panel_cert_enabled=1
        panel_cert_host="$(extract_certificate_primary_host "${cert_file}")"
    fi
}

print_panel_path_tip() {
    if [[ "${panel_base_path}" == "/" ]]; then
        echo "/"
    else
        echo "${panel_base_path}"
    fi
}

panel_has_reverse_proxy() {
    [[ "${panel_nginx_proxy_enabled}" == "true" && -n "${panel_nginx_proxy_host}" ]]
}

panel_has_https() {
    [[ ${panel_cert_enabled} -eq 1 ]]
}

allow_panel_port_when_safe() {
    enable_firewall_for_first_install || true

    if panel_has_https; then
        allow_port_in_firewall "${panel_port}"
        return 0
    fi

    if panel_has_reverse_proxy; then
        yellow "已启用 Nginx 反代，跳过自动放行面板直连端口 ${panel_port}。"
        return 0
    fi

    yellow "未配置 HTTPS 证书，已跳过自动放行面板端口 ${panel_port}。"
    yellow "请使用下方 SSH 隧道访问；如确需公网直连，可安装后在管理脚本里手动选择“放行面板端口”。"
}

show_ssh_tunnel_info() {
    local ipv4="$1"
    local ipv6="$2"
    local path_display="$3"
    local ssh_port=""
    local local_port="${ssh_tunnel_local_port}"
    local local_link=""

    [[ -z "${panel_port}" ]] && return 0
    ssh_port="$(current_ssh_port)"
    local_link="http://127.0.0.1:${local_port}${path_display}"

    echo "----------------------------------------------"
    yellow "当前未配置 HTTPS 证书，也未启用 Nginx 反代。"
    yellow "建议先通过 SSH 本地隧道安全访问面板，再进入“证书管理”为面板配置 HTTPS。"
    echo -e "自动识别 SSH 端口：${blue}${ssh_port}${plain}"
    echo -e "本地访问链接：${blue}${local_link}${plain}"
    if [[ -n "${ipv4}" ]]; then
        echo -e "SSH 隧道命令（IPv4）：${blue}ssh -L ${local_port}:127.0.0.1:${panel_port} -p ${ssh_port} root@${ipv4}${plain}"
    fi
    if [[ -n "${ipv6}" ]]; then
        echo -e "SSH 隧道命令（IPv6）：${blue}ssh -L ${local_port}:127.0.0.1:${panel_port} -p ${ssh_port} root@[${ipv6}]${plain}"
    fi
    if [[ -z "${ipv4}" && -z "${ipv6}" ]]; then
        echo -e "SSH 隧道命令：${blue}ssh -L ${local_port}:127.0.0.1:${panel_port} -p ${ssh_port} root@<服务器IP或域名>${plain}"
    fi
    echo "使用方法："
    echo "1. 在你自己的电脑终端执行上面的 SSH 隧道命令。"
    echo "2. 保持该 SSH 会话不要关闭。"
    echo "3. 在本机浏览器打开上面的本地访问链接。"
    echo "4. 如果本机 ${local_port} 端口被占用，把命令左侧的 ${local_port} 改成其他本地端口，并同步修改访问链接。"
    echo "5. 如果服务器禁用了 root SSH 登录，请把命令里的 root 改成实际可登录的系统用户。"
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

warn_insecure_http() {
    panel_cert_enabled=0
    panel_cert_host=""
    red "警告：面板将以不安全的 HTTP 方式运行。"
    yellow "建议安装完成后尽快进入“证书管理”为面板配置 HTTPS 证书。"
}

print_recent_command_output() {
    local title="$1"
    local output="$2"
    local lines="${3:-30}"

    output="$(printf '%s' "${output}" | sed 's/\r$//')"
    [[ -z "${output}" ]] && return 0

    yellow "${title}（最近 ${lines} 行）："
    printf '%s\n' "${output}" | tail -n "${lines}"
}

prompt_panel_username() {
    local username=""
    while true; do
        readp "设置 sx-ui 登录用户名（回车自动生成随机 6 位字符）：" username
        if [[ -z "${username}" ]]; then
            username="$(random_string 6)"
        fi
        if [[ "${username}" == *admin* ]]; then
            red "用户名中不能包含 admin，请重新输入。"
            continue
        fi
        panel_username="${username}"
        green "sx-ui 登录用户名：${panel_username}"
        return 0
    done
}

prompt_panel_password() {
    local password=""
    while true; do
        readp "设置 sx-ui 登录密码（回车自动生成随机 6 位字符）：" password
        if [[ -z "${password}" ]]; then
            password="$(random_string 6)"
        fi
        if [[ "${password}" == *admin* ]]; then
            red "密码中不能包含 admin，请重新输入。"
            continue
        fi
        panel_password="${password}"
        green "sx-ui 登录密码：${panel_password}"
        return 0
    done
}

prompt_panel_port() {
    local port=""
    while true; do
        readp "设置 sx-ui 面板端口[1-65535]（回车自动生成随机端口）：" port
        if [[ -z "${port}" ]]; then
            port="$(random_port)"
        fi
        if [[ ! "${port}" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
            red "端口必须是 1-65535 之间的数字。"
            continue
        fi
        if port_in_use "${port}"; then
            red "端口 ${port} 已被占用，请重新输入。"
            continue
        fi
        panel_port="${port}"
        green "sx-ui 面板端口：${panel_port}"
        return 0
    done
}

prompt_panel_base_path() {
    local base_path=""
    readp "设置 sx-ui 面板根路径（回车自动生成随机 3 位字符，输入 / 表示根目录）：" base_path
    panel_base_path="$(normalize_base_path "${base_path}")"
    green "sx-ui 面板根路径：$(print_panel_path_tip)"
}

apply_panel_basic_settings() {
    /usr/local/sx-ui/sx-ui setting \
        -username "${panel_username}" \
        -password "${panel_password}" \
        -port "${panel_port}" \
        -webBasePath "${panel_base_path}"
}

configure_certificate_after_install() {
    local cert_confirm=""
    echo
    yellow "建议立即为面板配置 HTTPS 证书。"
    yellow "如跳过，面板将先以 HTTP 方式运行。"
    readp "是否现在配置面板证书？[Y/n]：" cert_confirm
    if [[ -n "${cert_confirm}" && "${cert_confirm}" != "y" && "${cert_confirm}" != "Y" ]]; then
        warn_insecure_http
        return 0
    fi

    echo
    white "1. 申请 Cloudflare ACME 证书并自动写入面板"
    white "2. 使用已有证书路径并写入面板"
    white "3. 跳过证书安装"
    local cert_mode=""
    readp "请选择证书配置方式【1-3】：" cert_mode

    case "${cert_mode}" in
        1)
            local acme_account_name=""
            local acme_account_email=""
            local dns_account_name=""
            local dns_account_email=""
            local dns_account_api_key=""
            local cert_domain=""
            local cert_other_domains=""
            local cert_file=""
            local key_file=""
            local panel_acme_args=()

            yellow "开始设置 ACME 账户..."
            readp "请输入 ACME 账户名称（回车自动生成）：" acme_account_name
            readp "请输入 ACME 账户邮箱（回车自动生成虚拟 gmail 邮箱）：" acme_account_email

            echo
            yellow "开始设置 DNS 账户..."
            readp "请输入 DNS 账户名称（回车自动生成）：" dns_account_name
            readp "请输入 Cloudflare 注册邮箱：" dns_account_email
            readp "请输入 Cloudflare Global API Key：" dns_account_api_key

            echo
            yellow "开始设置证书申请..."
            readp "请输入主域名（例如 example.com）：" cert_domain
            readp "请输入其他域名（可留空，多个用逗号分隔）：" cert_other_domains
            readp "请输入证书路径（可留空，留空则按面板默认规则自动生成）：" cert_file
            readp "请输入私钥路径（可留空，留空则按面板默认规则自动生成）：" key_file

            if [[ -z "${dns_account_email}" || -z "${dns_account_api_key}" || -z "${cert_domain}" ]]; then
                red "DNS 账户邮箱、API Key 和主域名不能为空，已跳过证书安装。"
                warn_insecure_http
                return 0
            fi

            panel_acme_args+=(-panelDNSAccountEmail "${dns_account_email}")
            panel_acme_args+=(-panelDNSAccountAPIKey "${dns_account_api_key}")
            panel_acme_args+=(-panelCertPrimaryDomain "${cert_domain}")
            if [[ -n "${acme_account_name}" ]]; then
                panel_acme_args+=(-panelAcmeAccountName "${acme_account_name}")
            fi
            if [[ -n "${acme_account_email}" ]]; then
                panel_acme_args+=(-panelAcmeAccountEmail "${acme_account_email}")
            fi
            if [[ -n "${dns_account_name}" ]]; then
                panel_acme_args+=(-panelDNSAccountName "${dns_account_name}")
            fi
            if [[ -n "${cert_other_domains}" ]]; then
                panel_acme_args+=(-panelCertOtherDomains "${cert_other_domains}")
            fi
            if [[ -n "${cert_file}" ]]; then
                panel_acme_args+=(-panelAcmeCertFile "${cert_file}")
            fi
            if [[ -n "${key_file}" ]]; then
                panel_acme_args+=(-panelAcmeKeyFile "${key_file}")
            fi

            local panel_cert_output=""
            if panel_cert_output=$(/usr/local/sx-ui/sx-ui setting "${panel_acme_args[@]}" 2>&1); then
                green "面板证书申请并保存成功。"
                print_recent_command_output "证书申请日志" "${panel_cert_output}" 30
                panel_cert_enabled=1
                panel_cert_host="${cert_domain}"
            else
                red "面板证书申请失败，已继续安装。"
                print_recent_command_output "证书申请日志" "${panel_cert_output}" 30
                warn_insecure_http
            fi
            ;;
        2)
            local cert_file=""
            local key_file=""
            readp "请输入证书文件路径：" cert_file
            readp "请输入私钥文件路径：" key_file
            if [[ -z "${cert_file}" || -z "${key_file}" ]]; then
                red "证书路径和私钥路径不能为空，已跳过证书安装。"
                warn_insecure_http
                return 0
            fi
            local panel_cert_output=""
            if panel_cert_output=$(/usr/local/sx-ui/sx-ui setting -webCertFile "${cert_file}" -webKeyFile "${key_file}" 2>&1); then
                green "面板证书路径保存成功。"
                print_recent_command_output "证书保存日志" "${panel_cert_output}" 30
                panel_cert_enabled=1
                panel_cert_host="$(extract_certificate_primary_host "${cert_file}")"
            else
                red "面板证书路径保存失败，已继续安装。"
                print_recent_command_output "证书保存日志" "${panel_cert_output}" 30
                warn_insecure_http
            fi
            ;;
        *)
            warn_insecure_http
            ;;
    esac
}

configure_after_install() {
    if [[ ${existing_install} -eq 1 ]]; then
        yellow "检测到已安装 sx-ui，已自动保留原有面板登录信息与证书。"
        load_current_panel_settings
        return 0
    fi

    echo
    yellow "出于安全考虑，安装完成前请先设置面板登录信息。"
    prompt_panel_username
    echo
    prompt_panel_password
    echo
    prompt_panel_port
    echo
    prompt_panel_base_path
    echo

    yellow "开始保存面板基础设置..."
    if apply_panel_basic_settings; then
        green "面板基础设置保存完成。"
    else
        red "面板基础设置保存失败。"
        exit 1
    fi

    configure_certificate_after_install
    load_current_panel_settings
    allow_panel_port_when_safe
}

show_finish_message() {
    local ipv4=""
    local ipv6=""
    local protocol="http"
    local path_display=""
    local proxy_protocol="http"
    local version=""

    load_current_panel_settings
    ipv4="$(get_local_ipv4)"
    ipv6="$(get_local_ipv6)"
    panel_has_https && protocol="https"
    path_display="$(print_panel_path_tip)"
    version=$(/usr/local/sx-ui/sx-ui -v 2>/dev/null)
    [[ -z "${version}" ]] && version="未知"
    [[ "${panel_nginx_proxy_https}" == "true" ]] && proxy_protocol="https"

    echo
    green "sx-ui 安装完成，面板已启动。"
    echo "----------------------------------------------"
    show_system_summary
    echo "----------------------------------------------"
    if check_panel_runtime_status; then
        echo -e "面板状态：${green}已运行${plain}"
    else
        echo -e "面板状态：${red}未运行${plain}"
    fi
    if check_panel_boot_enabled; then
        echo -e "开机自启：${green}已启用${plain}"
    else
        echo -e "开机自启：${red}未启用${plain}"
    fi
    if check_xray_runtime_status; then
        echo -e "xray 状态：${green}运行中${plain}"
    else
        echo -e "xray 状态：${red}未运行${plain}"
    fi
    if check_singbox_runtime_status; then
        echo -e "sing-box 状态：${green}运行中${plain}"
    else
        echo -e "sing-box 状态：${red}未运行${plain}"
    fi
    if panel_has_reverse_proxy; then
        if check_nginx_runtime_status; then
            echo -e "nginx 状态：${green}运行中${plain}"
        else
            echo -e "nginx 状态：${red}未运行${plain}"
        fi
    fi
    echo "----------------------------------------------"
    echo -e "当前版本：${bblue}${version}${plain}"
    latest_release_version="$(resolve_latest_sxui_release)"
    if [[ -n "${latest_release_version}" ]]; then
        if version_lt "${version}" "${latest_release_version}"; then
            echo -e "最新版本：${yellow}${latest_release_version}${plain}  ${yellow}(可选择 2 更新)${plain}"
        else
            echo -e "最新版本：${green}${latest_release_version}${plain}"
        fi
    fi
    echo -e "面板用户名：${green}${panel_username}${plain}"
    echo -e "面板密码：${green}${panel_password}${plain}"
    echo -e "面板端口：${green}${panel_port}${plain}"
    echo -e "面板根路径：${green}${path_display}${plain}"
    if panel_has_reverse_proxy; then
        echo -e "访问方式：${green}Nginx 反代${plain}"
        echo -e "反代域名：${green}${proxy_protocol}://${panel_nginx_proxy_host}${path_display}${plain}"
        echo -e "反代登录：${blue}${proxy_protocol}://${panel_nginx_proxy_host}${path_display}${plain}"
    elif panel_has_https; then
        echo -e "证书状态：${green}已配置 HTTPS${plain}"
        if [[ -n "${panel_cert_host}" ]]; then
            echo -e "安全域名登录：${blue}${protocol}://${panel_cert_host}:${panel_port}${path_display}${plain}"
        fi
    else
        echo -e "证书状态：${yellow}未配置，当前将使用 HTTP${plain}"
    fi
    if ! panel_has_reverse_proxy && panel_has_https; then
        if [[ -n "${ipv4}" ]]; then
            echo -e "登录地址：${blue}${protocol}://${ipv4}:${panel_port}${path_display}${plain}"
        fi
        if [[ -n "${ipv6}" ]]; then
            echo -e "登录地址：${blue}${protocol}://[${ipv6}]:${panel_port}${path_display}${plain}"
        fi
    elif ! panel_has_https && ! panel_has_reverse_proxy; then
        yellow "公网直连地址未展示：当前未配置 HTTPS，安装脚本不会自动放行面板端口。"
    fi
    if ! panel_has_https && ! panel_has_reverse_proxy; then
        show_ssh_tunnel_info "${ipv4}" "${ipv6}" "${path_display}"
    fi
    echo "----------------------------------------------"
    if [[ ${existing_install} -eq 0 ]] && ! panel_has_https && ! panel_has_reverse_proxy; then
        red "安全提示：当前为首次安装，面板暂时通过 HTTP 提供服务，存在安全风险。"
        yellow "请尽快登录面板后，进入左侧“证书管理”为面板配置 HTTPS 证书。"
        echo "----------------------------------------------"
    fi
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
    green "18. 放行面板端口"
    echo "------------------------------------------------------------------------------------"
    green " 0. 退出脚本"
}

run_post_install_command() {
    local action=""
    echo
    readp "如需立即执行管理命令，请输入对应数字（回车或 0 退出）：" action

    case "${action}" in
        "" | 0)
            if [[ "${SX_UI_MANAGED_INSTALL:-}" == "1" ]] || is_management_script_parent; then
                exit "${post_install_exit_code}"
            fi
            exit 0
            ;;
        1)
            /usr/bin/sx-ui install
            ;;
        2)
            /usr/bin/sx-ui update
            ;;
        3)
            /usr/bin/sx-ui uninstall
            ;;
        4)
            /usr/bin/sx-ui change-auth
            ;;
        5)
            /usr/bin/sx-ui set-port
            ;;
        6)
            /usr/bin/sx-ui set-base-path
            ;;
        7)
            /usr/bin/sx-ui reset-config
            ;;
        8)
            /usr/bin/sx-ui show-config
            ;;
        9)
            /usr/bin/sx-ui start
            ;;
        10)
            /usr/bin/sx-ui stop
            ;;
        11)
            /usr/bin/sx-ui restart
            ;;
        12)
            /usr/bin/sx-ui status
            ;;
        13)
            /usr/bin/sx-ui log
            ;;
        14)
            /usr/bin/sx-ui enable
            ;;
        15)
            /usr/bin/sx-ui disable
            ;;
        16)
            /usr/bin/sx-ui update-shell
            ;;
        17)
            /usr/bin/sx-ui bbr
            ;;
        18)
            /usr/bin/sx-ui open-panel-port
            ;;
        *)
            red "请输入正确的数字【0-18】。"
            ;;
    esac
}

is_management_script_parent() {
    local parent_cmd=""

    [[ -r "/proc/${PPID}/cmdline" ]] || return 1
    parent_cmd="$(tr '\0' ' ' <"/proc/${PPID}/cmdline" 2>/dev/null)"
    [[ "${parent_cmd}" == *"/usr/bin/sx-ui"* || "${parent_cmd}" == *"sx-ui.sh"* ]]
}

install_sx_ui() {
    local last_version=""
    local archive_url=""
    local preserve_dir=""

    [[ -x /usr/local/sx-ui/sx-ui ]] && existing_install=1
    systemctl stop sx-ui >/dev/null 2>&1
    cd /usr/local/ || exit 1

    if [[ $# -eq 0 || -z "$1" ]]; then
        last_version="$(resolve_latest_sxui_release)"
        if [[ -z "${last_version}" ]]; then
            red "检测 sx-ui 正式版本失败，请稍后重试。"
            exit 1
        fi
    else
        last_version="$1"
    fi

    archive_url="https://github.com/sx-ui2/sx-ui/releases/download/${last_version}/sx-ui-linux-${arch}.tar.gz"
    yellow "开始下载 sx-ui ${last_version} (${arch})..."
    wget -N --no-check-certificate -O "/usr/local/sx-ui-linux-${arch}.tar.gz" "${archive_url}"
    if [[ $? -ne 0 ]]; then
        red "下载 sx-ui 失败，请确保当前服务器可以访问 Github。"
        exit 1
    fi

    if [[ "${existing_install:-0}" -eq 1 ]]; then
        preserve_dir="/tmp/sx-ui-runtime-preserve-${arch}"
        rm -rf "${preserve_dir}"
        preserve_runtime_binaries "${preserve_dir}"
    fi

    rm -rf /usr/local/sx-ui
    tar zxf "/usr/local/sx-ui-linux-${arch}.tar.gz"
    rm -f "/usr/local/sx-ui-linux-${arch}.tar.gz"

    if [[ ! -f /usr/local/sx-ui/sx-ui && -f /usr/local/sx-ui/xui-release ]]; then
        mv /usr/local/sx-ui/xui-release /usr/local/sx-ui/sx-ui
    fi
    if [[ ! -f /usr/local/sx-ui/sx-ui ]]; then
        red "安装包缺少主程序文件 /usr/local/sx-ui/sx-ui，请重新下载或更新 release 后再试。"
        exit 1
    fi

    cd /usr/local/sx-ui || exit 1
    chmod +x /usr/local/sx-ui/sx-ui
    chmod +x "/usr/local/sx-ui/bin/xray-linux-${arch}" 2>/dev/null || true
    chmod +x "/usr/local/sx-ui/bin/sing-box-linux-${arch}" 2>/dev/null || true
    if [[ "${existing_install:-0}" -eq 1 ]]; then
        restore_runtime_binaries "${preserve_dir}"
        rm -rf "${preserve_dir}"
    else
        install_managed_singbox_runtime
    fi
    cp -f /usr/local/sx-ui/sx-ui.service /etc/systemd/system/
    sync_management_script

    configure_after_install

    systemctl daemon-reload
    enable_panel_autostart
    systemctl start sx-ui

    show_finish_message
    run_post_install_command
}

main() {
    detect_release
    detect_arch
    check_os_version
    ensure_nat64_for_ipv6_only

    clear
    print_cli_header "安装脚本"
    white "系统：${release}    架构：${arch}"
    install_base
    install_sx_ui "$1"
}

main "$@"
