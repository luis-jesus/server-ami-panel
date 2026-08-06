#!/usr/bin/env bash

collect_init_inventory() {
    local init_system=$1

    case $init_system in
        systemd)
            write_command_output "systemd-running-services" systemctl list-units --type=service --state=running --no-pager --no-legend
            write_command_output "systemd-unit-files" systemctl list-unit-files --type=service --no-pager --no-legend
            write_command_output "systemd-timers" systemctl list-timers --all --no-pager
            write_command_output "systemd-sockets" systemctl list-sockets --all --no-pager
            write_command_output "systemd-failed" systemctl --failed --no-pager
            write_command_output "journal-errors" journalctl -p err -n 50 --no-pager
            ;;
        openrc)
            write_command_output "openrc-status" rc-status -a
            write_command_output "openrc-runlevels" rc-update show
            ;;
        runit)
            write_shell_output "runit-services" 'find /etc/service /var/service -maxdepth 1 -mindepth 1 -type l -o -type d 2>/dev/null | sort'
            write_shell_output "runit-status" 'for service_dir in /etc/service/* /var/service/*; do [ -e "$service_dir" ] && sv status "$service_dir"; done'
            ;;
        s6)
            write_command_output "s6-services" s6-rc -a list
            ;;
        sysvinit)
            if command_exists service; then
                write_command_output "sysv-service-status" service --status-all
            fi
            write_shell_output "sysv-init-scripts" 'find /etc/init.d -maxdepth 1 -mindepth 1 -type f | sort'
            ;;
        *)
            printf '## init-system\nunknown\n\n'
            ;;
    esac
}

collect_cron_inventory() {
    if [[ -r /etc/crontab ]]; then
        write_command_output "cron-system-crontab" cat /etc/crontab
    fi

    write_shell_output "cron-directories" 'find /etc -maxdepth 1 \( -name "cron.*" -o -name anacrontab \) -print 2>/dev/null | sort'

    if command_exists crontab; then
        write_shell_output "cron-current-user" 'crontab -l 2>/dev/null || echo "no crontab for current user"'
    fi
}

collect_services_inventory() {
    local output_file=$1
    local init_system=$2

    {
        printf 'init_system=%s\n\n' "$init_system"
        collect_init_inventory "$init_system"
        collect_cron_inventory
    } > "$output_file"
}