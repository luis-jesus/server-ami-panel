#!/usr/bin/env bash

collect_system_inventory() {
    local output_file=$1

    {
        printf 'snapshot_utc=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf 'hostname=%s\n' "$(hostname 2>/dev/null || uname -n)"
        printf 'kernel=%s\n\n' "$(uname -srmo 2>/dev/null || uname -a)"

        write_command_output "os-release" cat /etc/os-release
        write_command_output "uname" uname -a
        write_command_output "uptime" uptime

        if command_exists lscpu; then
            write_command_output "cpu" lscpu
        else
            write_command_output "cpu-fallback" cat /proc/cpuinfo
        fi

        if command_exists free; then
            write_command_output "memory" free -h
        else
            write_command_output "memory-fallback" cat /proc/meminfo
        fi

        if command_exists lsblk; then
            write_command_output "block-devices" lsblk -a
        else
            write_command_output "block-devices-fallback" cat /proc/partitions
        fi

        write_command_output "mounts" mount

        if command_exists lspci; then
            write_command_output "pci" lspci -nnk
        else
            write_command_output "pci-fallback" sh -c 'find /sys/bus/pci/devices -mindepth 1 -maxdepth 1 -exec basename {} \;'
        fi

        if command_exists ip; then
            write_command_output "network-links" ip -brief link
            write_command_output "network-addresses" ip -brief address
            write_command_output "routes" ip route show
        else
            if command_exists ifconfig; then
                write_command_output "network-links-fallback" ifconfig -a
            else
                write_command_output "network-links-fallback" cat /proc/net/dev
            fi

            if command_exists route; then
                write_command_output "routes-fallback" route -n
            else
                write_command_output "routes-fallback" cat /proc/net/route
            fi
        fi
    } > "$output_file"
}