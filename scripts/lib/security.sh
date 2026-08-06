#!/usr/bin/env bash

collect_firewall_inventory() {
    local firewall_backend=$1

    case $firewall_backend in
        nftables)
            write_command_output "firewall-nftables" nft list ruleset
            ;;
        ufw)
            write_command_output "firewall-ufw" ufw status verbose
            ;;
        firewalld)
            write_command_output "firewall-firewalld" firewall-cmd --list-all
            ;;
        iptables)
            if command_exists iptables-save; then
                write_command_output "firewall-iptables" iptables-save
            else
                write_command_output "firewall-iptables" iptables -S
            fi
            ;;
        *)
            printf '## firewall\nnone-detected\n\n'
            ;;
    esac
}

collect_security_inventory() {
    local output_file=$1
    local firewall_backend=$2

    {
        printf 'firewall_backend=%s\n\n' "$firewall_backend"

        if command_exists ss; then
            write_command_output "listening-ports" ss -tulpn
        elif command_exists netstat; then
            write_command_output "listening-ports" netstat -tulpn
        fi

        if command_exists ip; then
            write_command_output "network-addresses" ip address show
            write_command_output "network-routes" ip route show
        elif command_exists ifconfig; then
            write_command_output "network-addresses" ifconfig -a
            if command_exists route; then
                write_command_output "network-routes" route -n
            else
                write_command_output "network-routes" cat /proc/net/route
            fi
        else
            write_command_output "network-addresses" cat /proc/net/dev
            write_command_output "network-routes" cat /proc/net/route
        fi

        if [[ -r /etc/resolv.conf ]]; then
            write_command_output "dns-resolvers" cat /etc/resolv.conf
        fi

        if [[ -r /etc/hosts ]]; then
            write_command_output "hosts-file" cat /etc/hosts
        fi

        collect_firewall_inventory "$firewall_backend"

        if command_exists sestatus; then
            write_command_output "selinux-status" sestatus
        elif command_exists getenforce; then
            write_command_output "selinux-status" getenforce
        fi

        if command_exists aa-status; then
            write_command_output "apparmor-status" aa-status
        fi

        if command_exists fail2ban-client; then
            write_command_output "fail2ban-status" fail2ban-client status
        fi

        if [[ -r /etc/ssh/sshd_config ]]; then
            write_command_output "sshd-config" cat /etc/ssh/sshd_config
        fi
    } > "$output_file"
}