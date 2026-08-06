#!/usr/bin/env bash

infer_distro_family() {
    local os_id=$1
    local os_like=$2
    local combined

    combined="${os_id} ${os_like}"

    case $combined in
        *debian*|*ubuntu*|*linuxmint*|*pop*)
            printf '%s\n' 'debian'
            ;;
        *rhel*|*fedora*|*centos*|*rocky*|*alma*|*ol*)
            printf '%s\n' 'rhel'
            ;;
        *arch*|*manjaro*|*endeavouros*)
            printf '%s\n' 'arch'
            ;;
        *opensuse*|*suse*|*sled*|*sles*)
            printf '%s\n' 'suse'
            ;;
        *alpine*)
            printf '%s\n' 'alpine'
            ;;
        *void*)
            printf '%s\n' 'void'
            ;;
        *gentoo*)
            printf '%s\n' 'gentoo'
            ;;
        *nixos*)
            printf '%s\n' 'nixos'
            ;;
        *)
            printf '%s\n' 'unknown'
            ;;
    esac
}

detect_os_release() {
    local -n out_id=$1
    local -n out_like=$2
    local -n out_name=$3

    out_id="unknown"
    out_like="unknown"
    out_name="unknown"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        out_id=${ID:-unknown}
        out_like=${ID_LIKE:-unknown}
        out_name=${PRETTY_NAME:-${NAME:-unknown}}
    fi
}

detect_package_backend() {
    if command_exists dpkg-query; then
        printf '%s\n' 'dpkg'
    elif command_exists pacman; then
        printf '%s\n' 'pacman'
    elif command_exists zypper; then
        printf '%s\n' 'zypper'
    elif command_exists rpm; then
        printf '%s\n' 'rpm'
    elif command_exists apk; then
        printf '%s\n' 'apk'
    elif command_exists xbps-query; then
        printf '%s\n' 'xbps'
    elif command_exists qlist; then
        printf '%s\n' 'portage'
    elif command_exists nix-store; then
        printf '%s\n' 'nix'
    else
        printf '%s\n' 'unknown'
    fi
}

detect_init_system() {
    if command_exists systemctl && [[ -d /run/systemd/system ]]; then
        printf '%s\n' 'systemd'
    elif command_exists openrc; then
        printf '%s\n' 'openrc'
    elif command_exists rc-status; then
        printf '%s\n' 'openrc'
    elif command_exists sv; then
        printf '%s\n' 'runit'
    elif command_exists s6-rc; then
        printf '%s\n' 's6'
    elif [[ -d /etc/init.d ]]; then
        printf '%s\n' 'sysvinit'
    else
        printf '%s\n' 'unknown'
    fi
}

detect_firewall_backend() {
    if command_exists ufw; then
        printf '%s\n' 'ufw'
    elif command_exists firewall-cmd; then
        printf '%s\n' 'firewalld'
    elif command_exists nft; then
        printf '%s\n' 'nftables'
    elif command_exists iptables; then
        printf '%s\n' 'iptables'
    else
        printf '%s\n' 'none'
    fi
}

detect_container_backends() {
    local backends=()

    command_exists docker && backends+=(docker)
    command_exists podman && backends+=(podman)
    command_exists incus && backends+=(incus)
    command_exists lxc && backends+=(lxc)
    command_exists virsh && backends+=(libvirt)

    if ((${#backends[@]} == 0)); then
        printf '%s\n' 'none'
        return 0
    fi

    local joined=${backends[*]}
    printf '%s\n' "${joined// /,}"
}

write_command_availability() {
    local command_name=$1

    if command_exists "$command_name"; then
        printf '%s=present\n' "$command_name"
    else
        printf '%s=missing\n' "$command_name"
    fi
}

collect_compatibility_inventory() {
    local output_file=$1
    local os_id="unknown"
    local os_like="unknown"
    local os_name="unknown"
    local distro_family
    local package_backend
    local init_system
    local firewall_backend
    local container_backends
    local command_name
    local -a commands=(
        dpkg-query rpm pacman zypper apk xbps-query qlist nix-store
        systemctl openrc rc-status sv s6-rc service
        ip ss netstat nft ufw firewall-cmd iptables
        docker podman incus lxc virsh
        lsblk lspci lscpu free journalctl
    )

    detect_os_release os_id os_like os_name
    distro_family=$(infer_distro_family "$os_id" "$os_like")
    package_backend=$(detect_package_backend)
    init_system=$(detect_init_system)
    firewall_backend=$(detect_firewall_backend)
    container_backends=$(detect_container_backends)

    {
        printf 'os_id=%s\n' "$os_id"
        printf 'os_like=%s\n' "$os_like"
        printf 'os_name=%s\n' "$os_name"
        printf 'distro_family=%s\n' "$distro_family"
        printf 'package_backend=%s\n' "$package_backend"
        printf 'init_system=%s\n' "$init_system"
        printf 'firewall_backend=%s\n' "$firewall_backend"
        printf 'container_backends=%s\n\n' "$container_backends"

        printf '## path-probes\n'
        [[ -r /etc/os-release ]] && printf '/etc/os-release=present\n' || printf '/etc/os-release=missing\n'
        [[ -d /run/systemd/system ]] && printf '/run/systemd/system=present\n' || printf '/run/systemd/system=missing\n'
        [[ -d /etc/init.d ]] && printf '/etc/init.d=present\n' || printf '/etc/init.d=missing\n'
        [[ -d /etc/service ]] && printf '/etc/service=present\n' || printf '/etc/service=missing\n'
        [[ -d /var/service ]] && printf '/var/service=present\n' || printf '/var/service=missing\n'
        printf '\n'

        printf '## command-availability\n'
        for command_name in "${commands[@]}"; do
            write_command_availability "$command_name"
        done
        printf '\n'
    } > "$output_file"
}