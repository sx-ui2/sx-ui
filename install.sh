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
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "${bblue} ░██     ░██      ░██ ██ ██         ░█${plain}█   ░██     ░██   ░██     ░█${red}█   ░██${plain}  "
    echo -e "${bblue}  ░██   ░██      ░██    ░░██${plain}        ░██  ░██      ░██  ░██${red}      ░██  ░██${plain}   "
    echo -e "${bblue}   ░██ ░██      ░██ ${plain}                ░██ ██        ░██ █${red}█        ░██ ██  ${plain}   "
    echo -e "${bblue}     ░██        ░${plain}██    ░██ ██       ░██ ██        ░█${red}█ ██        ░██ ██  ${plain}  "
    echo -e "${bblue}     ░██ ${plain}        ░██    ░░██        ░██ ░██       ░${red}██ ░██       ░██ ░██ ${plain}  "
    echo -e "${bblue}     ░█${plain}█          ░██ ██ ██         ░██  ░░${red}██     ░██  ░░██     ░██  ░░██ ${plain}  "
    echo
    white "sx-ui Github 项目 ：github.com/sx-ui2/sx-ui"
    white "sx-ui ${subtitle}   ：sx-ui"
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
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
existing_install=0
v4=""
v6=""
wgcfv4=""
wgcfv6=""
managed_singbox_repo="sx-ui2/sx-ui-runtime"
managed_singbox_tag_prefix="sing-box-stats-v"

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
        green "已备份当前防火墙规则到 ${backup_dir}/"
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
        green "已备份并重置现有 filter/mangle 防火墙规则，后续交由 UFW 接管。"
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
        green "已通过 UFW 放行面板端口 ${port}/tcp"
        if [[ "${ssh_port}" != "${port}" ]]; then
            green "已通过 UFW 保留 SSH 端口 ${ssh_port}/tcp"
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

    if allow_port_via_ufw "${port}"; then
        opened=1
    fi

    if [[ ${opened} -eq 0 ]]; then
        yellow "未检测到可用的 firewalld/UFW，已跳过自动放行面板端口。"
    fi
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
    panel_username=$(echo "${setting_dump}" | awk -F': ' '$1=="username"{print $2}')
    panel_password=$(echo "${setting_dump}" | awk -F': ' '$1=="userpasswd"{print $2}')
    panel_port=$(echo "${setting_dump}" | awk -F': ' '$1=="port"{print $2}')
    panel_base_path=$(echo "${setting_dump}" | awk -F': ' '$1=="webBasePath"{print $2}')
    local cert_file=""
    local key_file=""
    cert_file=$(echo "${setting_dump}" | awk -F': ' '$1=="webCertFile"{print $2}')
    key_file=$(echo "${setting_dump}" | awk -F': ' '$1=="webKeyFile"{print $2}')
    [[ -z "${panel_base_path}" ]] && panel_base_path="/"
    if [[ -n "${cert_file}" && -n "${key_file}" ]]; then
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
        allow_port_in_firewall "${panel_port}"
    else
        red "面板基础设置保存失败。"
        exit 1
    fi

    configure_certificate_after_install
}

show_finish_message() {
    local ipv4=""
    local ipv6=""
    local protocol="http"
    local path_display=""
    local secure_link=""

    ipv4="$(get_local_ipv4)"
    ipv6="$(get_local_ipv6)"
    [[ ${panel_cert_enabled} -eq 1 ]] && protocol="https"
    path_display="$(print_panel_path_tip)"
    if [[ "${protocol}" == "https" && -n "${panel_cert_host}" ]]; then
        secure_link="${protocol}://${panel_cert_host}:${panel_port}${path_display}"
    fi

    echo
    green "sx-ui 安装完成，面板已启动。"
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
    echo "----------------------------------------------"
    echo -e "用户名：${green}${panel_username}${plain}"
    echo -e "密码：${green}${panel_password}${plain}"
    echo -e "端口：${green}${panel_port}${plain}"
    echo -e "根路径：${green}${path_display}${plain}"
    if [[ -n "${secure_link}" ]]; then
        echo -e "安全域名登录：${blue}${secure_link}${plain}"
    fi
    if [[ -n "${ipv4}" ]]; then
        echo -e "登录地址：${blue}${protocol}://${ipv4}:${panel_port}${path_display}${plain}"
    fi
    if [[ -n "${ipv6}" ]]; then
        echo -e "登录地址：${blue}${protocol}://[${ipv6}]:${panel_port}${path_display}${plain}"
    fi
    echo "----------------------------------------------"
    if [[ ${existing_install} -eq 0 && ${panel_cert_enabled} -eq 0 ]]; then
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
    echo "------------------------------------------------------------------------------------"
    green " 0. 退出脚本"
}

run_post_install_command() {
    local action=""
    echo
    readp "如需立即执行管理命令，请输入对应数字（回车或 0 退出）：" action

    case "${action}" in
        "" | 0)
            return 0
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
        *)
            red "请输入正确的数字【0-17】。"
            ;;
    esac
}

install_sx_ui() {
    local last_version=""
    local archive_url=""

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

    rm -rf /usr/local/sx-ui
    tar zxf "/usr/local/sx-ui-linux-${arch}.tar.gz"
    rm -f "/usr/local/sx-ui-linux-${arch}.tar.gz"

    cd /usr/local/sx-ui || exit 1
    chmod +x /usr/local/sx-ui/sx-ui
    chmod +x "/usr/local/sx-ui/bin/xray-linux-${arch}" 2>/dev/null || true
    chmod +x "/usr/local/sx-ui/bin/sing-box-linux-${arch}" 2>/dev/null || true
    install_managed_singbox_runtime
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
