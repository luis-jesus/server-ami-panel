# Matriz de Compatibilidad y Validación

Este documento sirve para verificar qué tan bien se adapta el inventario a cada familia de distribuciones Linux y qué revisar cuando la detección o un colector no arrojan el resultado esperado.

## Familias previstas

| Familia inferida | Señales típicas | Backend de paquetes esperado | Init más común |
| --- | --- | --- | --- |
| Debian | `debian`, `ubuntu`, `linuxmint`, `pop` | `dpkg` | `systemd` |
| RHEL | `rhel`, `fedora`, `centos`, `rocky`, `alma`, `ol` | `rpm` | `systemd` |
| Arch | `arch`, `manjaro`, `endeavouros` | `pacman` | `systemd` |
| SUSE | `opensuse`, `suse`, `sled`, `sles` | `zypper` o `rpm` | `systemd` |
| Alpine | `alpine` | `apk` | OpenRC |
| Void | `void` | `xbps` | `runit` |
| Gentoo | `gentoo` | `portage` | OpenRC |
| NixOS | `nixos` | `nix` | `systemd` |

## Qué valida `compatibility.txt`

- Datos de `os-release`
- Familia de distro inferida
- Backend de paquetes detectado
- Sistema de init detectado
- Backend de firewall detectado
- Backends de contenedores detectados
- Disponibilidad de comandos críticos por categoría
- Presencia de rutas indicativas como `/run/systemd/system`, `/etc/init.d`, `/etc/service` y `/var/service`

## Checklist manual por familia

### Debian/Ubuntu

- Confirmar `distro_family=debian`.
- Confirmar `package_backend=dpkg`.
- Revisar que `software.txt` liste paquetes mediante `dpkg-query`.
- Revisar que `services.txt` use `systemctl` cuando `systemd` esté presente.

### RHEL/Fedora

- Confirmar `distro_family=rhel`.
- Confirmar `package_backend=rpm`.
- Revisar que `software.txt` use `rpm -qa`.
- Si `firewalld` está presente, confirmar `firewall_backend=firewalld` incluso cuando `nft` también exista en `PATH`.

### Arch

- Confirmar `distro_family=arch`.
- Confirmar `package_backend=pacman`.
- Revisar que `software.txt` use `pacman -Q`.

### openSUSE/SUSE

- Confirmar `distro_family=suse`.
- Si `zypper` está disponible, confirmar `package_backend=zypper` aunque `rpm` también exista.
- Si `zypper` no está disponible, revisar el fallback a `rpm`.
- Confirmar inventario de servicios mediante `systemctl`.

### Alpine

- Confirmar `distro_family=alpine`.
- Confirmar `package_backend=apk`.
- Confirmar `init_system=openrc` si aplica.
- Revisar que `services.txt` use `rc-status` y `rc-update`.

### Void

- Confirmar `distro_family=void`.
- Confirmar `package_backend=xbps`.
- Confirmar `init_system=runit`.
- Revisar que `services.txt` enumere `/etc/service` o `/var/service`.

### Gentoo

- Confirmar `distro_family=gentoo`.
- Confirmar `package_backend=portage` cuando `qlist` esté presente.
- Confirmar `init_system=openrc` en instalaciones típicas.

### NixOS

- Confirmar `distro_family=nixos`.
- Confirmar `package_backend=nix`.
- Revisar que `software.txt` use `nix-store` o `nix profile list` como fallback.

## Diagnóstico rápido cuando algo no cuadra

- Si la familia sale `unknown`, revisar el contenido de `/etc/os-release`.
- Si el backend de paquetes sale `unknown`, verificar si el binario del gestor está en `PATH`.
- Si el init sale `sysvinit` pero el host usa otra cosa, revisar la presencia real de `systemctl`, `rc-status`, `sv` o `s6-rc`.
- Si un colector falla, revisar `warnings.log` y la sección correspondiente del archivo de texto generado.

## Validación mínima recomendada

1. Ejecutar `bash scripts/collect_inventory.sh --quick`.
2. Abrir `manifest.txt` y `text/compatibility.txt`.
3. Confirmar que familia, init y backends coincidan con el host real.
4. Revisar que los archivos `system.txt`, `software.txt`, `services.txt` y `security.txt` tengan contenido útil.
5. Repetir con `sudo` cuando se requiera mayor cobertura de firewall, servicios y configuraciones.

## Validación complementaria del panel

1. Ejecutar `bash scripts/run_panel.sh --host 127.0.0.1 --port 8765`.
2. Confirmar en la pantalla principal que sistema operativo, hostname e IP principal coincidan con el host.
3. Abrir `Monitoreo de servicios` y revisar que `ssh`, `samba`, `docker` y `firewall` muestren un backend y un origen razonables para la distro.
4. Verificar que los puertos activos detectados coincidan con los servicios realmente expuestos por el host.
5. En `ssh`, confirmar que `sftp` aparezca como capacidad derivada cuando exista una directiva `Subsystem sftp`.
6. En `docker`, contrastar tres señales distintas: estado del servicio, presencia y permisos de `docker.sock`, y acceso real del cliente mediante `Docker CLI`.
7. Si Docker esta instalado, revisar que la tarjeta muestre `owner`, `group`, `mode`, usuario efectivo del panel y permisos de lectura/escritura del socket, junto con version del servidor, driver y conteo de contenedores cuando `docker info` sea accesible.
8. Usar `Ver logs` en al menos un servicio y comprobar que el origen de logs sea coherente con el host, por ejemplo `journalctl` en `systemd`.