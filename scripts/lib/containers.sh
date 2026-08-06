#!/usr/bin/env bash

collect_docker_inventory() {
    write_command_output "docker-version" docker version
    write_command_output "docker-info" docker info
    write_command_output "docker-ps" docker ps -a
    write_command_output "docker-images" docker images
    write_command_output "docker-networks" docker network ls
    write_command_output "docker-volumes" docker volume ls
}

collect_podman_inventory() {
    write_command_output "podman-version" podman version
    write_command_output "podman-info" podman info
    write_command_output "podman-ps" podman ps -a
    write_command_output "podman-images" podman images
    write_command_output "podman-networks" podman network ls
    write_command_output "podman-volumes" podman volume ls
}

collect_lxc_inventory() {
    if command_exists incus; then
        write_command_output "incus-list" incus list
        write_command_output "incus-images" incus image list
        write_command_output "incus-profiles" incus profile list
    fi

    if command_exists lxc; then
        write_command_output "lxc-list" lxc list
        write_command_output "lxc-profiles" lxc profile list
    fi
}

collect_virtualization_inventory() {
    if command_exists virsh; then
        write_command_output "libvirt-domains" virsh list --all
        write_command_output "libvirt-networks" virsh net-list --all
        write_command_output "libvirt-pools" virsh pool-list --all
    fi

    if command_exists VBoxManage; then
        write_command_output "virtualbox-version" VBoxManage --version
        write_command_output "virtualbox-vms" VBoxManage list vms
    fi

    if command_exists vmware; then
        write_command_output "vmware-version" vmware -v
    fi

    if command_exists qemu-system-x86_64; then
        write_command_output "qemu-version" qemu-system-x86_64 --version
    fi
}

collect_containers_inventory() {
    local output_file=$1
    local container_backends=$2

    {
        printf 'container_backends=%s\n\n' "$container_backends"

        if command_exists docker; then
            collect_docker_inventory
        fi

        if command_exists podman; then
            collect_podman_inventory
        fi

        if command_exists incus || command_exists lxc; then
            collect_lxc_inventory
        fi

        collect_virtualization_inventory
    } > "$output_file"
}