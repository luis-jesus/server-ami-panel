# ServerAM1

Inventario, monitoreo y revisión de actualizaciones para equipos Linux multi-distro, con salida por CLI y un panel web local sin dependencias externas.

El proyecto está pensado para documentar un host real con foco en desarrollo, ciberseguridad, servidor y gaming, sin amarrarse a una sola distribución. En lugar de depender del nombre de la distro, detecta capacidades disponibles en el sistema y degrada de forma segura cuando faltan herramientas o permisos.

## Características

- Genera snapshots locales del sistema con reportes de hardware, kernel, red, almacenamiento, software, servicios, seguridad, contenedores, gaming y configuraciones relevantes.
- Detecta automáticamente familia de distro, gestor de paquetes, sistema de init, backend de firewall y herramientas de contenedores.
- Permite revisar actualizaciones pendientes, identificar advisories de seguridad cuando el backend lo soporta y validar la confianza de los repositorios configurados.
- Incluye un panel web local para ejecutar jobs, seguir salida en vivo, revisar reportes históricos y monitorear servicios.
- Exporta artefactos útiles para auditoría y automatización, incluyendo `manifest.txt`, `summary.txt`, `report.json` y archivos TSV.
- Mantiene compatibilidad degradable: si una utilidad no existe o no hay permisos suficientes, la ejecución continúa y deja evidencia en `warnings.log`.

## Casos de uso

- Levantar un inventario rápido de una estación Linux.
- Auditar cambios planeados antes de actualizar paquetes.
- Monitorear estado de `ssh`, `samba`, `docker` y `firewall` desde un panel local.
- Conservar snapshots comparables entre ejecuciones del mismo host.
- Revisar configuraciones y servicios antes de migraciones, endurecimiento o troubleshooting.

## Requisitos

### Obligatorios

- Linux.
- `bash`.
- `python3` 3.10 o superior recomendado para el panel y las pruebas.
- Utilidades base normalmente presentes en una instalación estándar: `grep`, `sed`, `awk`, `find`, `tar`, `hostname`, `date` y `mktemp`.
- Permisos de escritura en la raíz del proyecto o en el directorio indicado con `--output-root`.

### Opcionales según el host

- `sudo` para ampliar visibilidad sobre servicios, firewall, puertos, logs y configuraciones del sistema.
- Un backend de paquetes soportado: `dpkg`, `rpm`, `pacman`, `zypper`, `apk`, `xbps`, `portage` o `nix`.
- Un sistema de init soportado: `systemd`, `openrc`, `runit`, `s6` o `sysvinit`.
- Herramientas de firewall como `ufw`, `firewalld`, `nft` o `iptables`.
- Herramientas de virtualización o contenedores como `docker`, `podman`, `incus`, `lxc` o `virsh` si quieres inventariar ese stack.

### Dependencias externas

No requiere `pip install`, `npm install` ni frameworks adicionales para funcionar. El panel corre con la librería estándar de Python.

La instalación administrada sí crea un entorno virtual local para encapsular la ejecución del panel y de sus launchers, aunque actualmente no descargue dependencias Python de terceros.

## Instalación

### 1. Clonar el repositorio

```bash
git clone https://github.com/luis-jesus/server-ami-panel.git
cd server-ami-panel
```

### 2. Instalar dependencias base del sistema

Puedes dejar que el proyecto detecte tu backend e imprima o ejecute el comando adecuado:

```bash
bash scripts/install_requirements.sh --print
```

Para instalar automáticamente `python3` y `pip` del sistema cuando el backend esté soportado:

```bash
bash scripts/install_requirements.sh -y
```

En backends tipo Debian también se incluirá `python3-venv`, porque el instalador usa un entorno virtual administrado por usuario.

### 3. Verificar dependencias mínimas

```bash
bash --version
python3 --version
```

Si `python3` no está instalado:

- Debian, Ubuntu, Linux Mint:

```bash
sudo apt update
sudo apt install -y python3
```

- Fedora:

```bash
sudo dnf install -y python3
```

- Arch Linux:

```bash
sudo pacman -S python
```

- openSUSE:

```bash
sudo zypper install -y python3
```

### 4. Probar el entorno

```bash
bash tests/run_tests.sh
```

La suite valida sintaxis, detección multi-distro, una corrida rápida del inventario, el backend Python del panel, la generación del payload de servicios y el flujo de revisión de actualizaciones.

## Flujo de integración Git

El repositorio está migrando a un workflow de integración con `develop` como rama de integración y `master` como rama de release.

- `feature/*` y `bugfix/*` deben abrir PR hacia `develop`.
- `feature-major/*` debe abrir PR hacia `develop` y genera un incremento major.
- `hotfix/*` debe abrir PR hacia `master`.
- Las ramas nuevas deben usar prefijo obligatorio seguido por un nombre numérico, alfabético o alfanumérico.
- `@CarloAndrePonceMiranda` queda como CODEOWNER para revisiones requeridas en ramas protegidas.
- Los commits deben usar formato `fix(scope) Descripcion`, `feature(scope) Descripcion`, `hotfix(scope) Descripcion` o `chore(scope) Descripcion`.

Antes de preparar una release, ejecuta:

```bash
bash scripts/check_release.sh
bash scripts/check_commit_messages.sh
```

El cache persistente del briefing se guarda bajo `tmp/` para no ensuciar el arbol Git del repositorio.

La guía completa del flujo está en [docs/git-integration-workflow.md](docs/git-integration-workflow.md).

El tipo de version se determina por la rama: `feature-major/*` genera major, `feature/*` y `bugfix/*` generan minor, y `hotfix/*` genera patch. Los merges hacia `develop` crean o actualizan una PR draft de promocion `develop -> master`; al fusionarla se publica el tag y la GitHub Release se crea manualmente.

## Instalador interactivo

El repositorio incluye un instalador principal en `install.sh`.

```bash
bash install.sh
```

Características del instalador:

- Primera ejecución: muestra `install`, `log` y `exit`.
- Después de instalar: muestra `reinstall`, `update`, `uninstall`, `log` y `exit`.
- Crea un entorno virtual en `~/.local/share/serveram1/venv`.
- Genera accesos directos en `~/.local/share/applications/`.
- Instala shims en `~/.local/bin/`.
- Renderiza el menú con colores ANSI, fondo negro cuando la terminal lo soporte y ajuste dinámico al ancho de la ventana maximizada.

### Subcomandos útiles

```bash
bash install.sh install
bash install.sh reinstall
bash install.sh update
bash install.sh uninstall
bash install.sh log
bash install.sh run
```

`run` arranca el panel local usando el Python del entorno virtual instalado y abre la interfaz web en el navegador disponible, con preferencia por modo app cuando el navegador lo soporte.

## Uso rápido

### Generar inventario completo

```bash
bash scripts/collect_inventory.sh
```

### Generar inventario rápido

```bash
bash scripts/collect_inventory.sh --quick
```

### Cambiar directorio de salida

```bash
bash scripts/collect_inventory.sh --output-root /ruta/de/salida
```

## Revisión de actualizaciones

### Reporte sin aplicar cambios

```bash
bash scripts/update_packages.sh --check
```

### Reporte sin refrescar metadatos

```bash
bash scripts/update_packages.sh --check --no-refresh
```

### Aplicar actualizaciones

```bash
bash scripts/update_packages.sh --apply
```

### Aplicar sin preguntas cuando el backend lo soporte

```bash
bash scripts/update_packages.sh --apply --yes
```

### Permitir orígenes no confiables de forma explícita

```bash
bash scripts/update_packages.sh --apply --allow-untrusted-sources
```

El archivo local [config/trusted-sources.txt](config/trusted-sources.txt) funciona como allowlist local de orígenes esperados. Si ya revisaste un repositorio de terceros y forma parte normal de tu entorno, agrégalo ahí para que el reporte lo clasifique como `allowed` en lugar de `review`.

## Panel web local

El panel usa `python3` y expone una interfaz HTTP local sobre `127.0.0.1:8765`.

### Arranque rápido

```bash
bash scripts/run_panel.sh
```

### Host y puerto personalizados

```bash
bash scripts/run_panel.sh --host 127.0.0.1 --port 8765
```

### Qué puedes hacer desde el panel

- Ejecutar `collect_inventory.sh` en modo normal o rápido.
- Ejecutar `update_packages.sh` en modo `check` o `apply`.
- Ver jobs activos con salida en vivo.
- Revisar reportes recientes en `output/` y `update-reports/`.
- Previsualizar archivos como `manifest.txt`, `summary.txt`, `report.json`, `security.txt` y `source-trust.txt`.
- Filtrar reportes por modo, estado de trust, quick/full y búsquedas libres.
- Descargar artefactos puntuales del reporte.
- Comparar ejecuciones del mismo tipo.
- Exportar CSV de inventarios o updates filtrados.
- Monitorear `ssh`, `samba`, `docker` y `firewall` con refresco automático.
- Consultar logs recientes y ejecutar acciones `start`, `stop` y `restart` cuando el backend lo soporte.

### Endpoints útiles

- `GET /api/system`: resumen del host.
- `GET /api/status`: estado del panel, jobs y metadatos del sistema.
- `GET /api/home-briefing`: resumen ligero del entorno y briefing agregado.
- `GET /api/services`: estado normalizado de servicios y capacidades derivadas.
- `GET /api/services/<id>/logs?lines=N`: logs recientes del servicio.
- `GET /api/reports?kind=inventory|update`: lista de reportes.
- `GET /api/reports/<kind>/<id>`: detalle agregado de un reporte.
- `POST /api/jobs/inventory`: lanza inventario.
- `POST /api/jobs/update`: lanza revisión o aplicación de actualizaciones.
- `POST /api/services/action`: ejecuta acciones sobre servicios soportados.

## Estructura del proyecto

- `scripts/collect_inventory.sh`: punto de entrada del inventario.
- `scripts/update_packages.sh`: revisión y aplicación de actualizaciones.
- `scripts/run_panel.sh`: arranque del panel local.
- `scripts/lib/`: librerías de detección e inventario.
- `panel/server.py`: backend HTTP del panel.
- `panel/static/`: frontend estático del panel.
- `config/trusted-sources.txt`: allowlist local de repositorios esperados.
- `docs/compatibility-matrix.md`: matriz manual de compatibilidad.
- `tests/run_tests.sh`: suite de validación del proyecto.
- `output/`: snapshots de inventario.
- `update-reports/`: reportes de revisión o aplicación de paquetes.

## Artefactos generados

### Inventario

Cada ejecución crea un directorio con formato `<hostname>_<timestamp>` dentro de `output/`.

Archivos esperados:

- `manifest.txt`
- `warnings.log`
- `text/compatibility.txt`
- `text/system.txt`
- `text/software.txt`
- `text/services.txt`
- `text/security.txt`
- `text/containers.txt`
- `text/gaming.txt`
- `text/user-configs.txt`
- `configs/configs.tar.gz`

### Actualizaciones

Según el modo y el backend, el reporte puede incluir:

- `manifest.txt`
- `report.json`
- `plan.txt`
- `security.txt`
- `source-trust.txt`
- `packages-before.tsv`
- `packages-after.tsv`
- `planned-installed.tsv`
- `planned-updated.tsv`
- `planned-removed.tsv`
- `changes-installed.tsv`
- `changes-updated.tsv`
- `changes-removed.tsv`
- `summary.txt`
- `operations.log`
- `warnings.log`

Dentro de `report.json`, los bloques más útiles para automatización son `manifest`, `summary`, `trust`, `security`, `planned_changes` y `applied_changes`.

## Compatibilidad prevista

| Categoría | Backends contemplados |
| --- | --- |
| Paquetes | `dpkg`, `rpm`, `pacman`, `zypper`, `apk`, `xbps`, `portage`, `nix` |
| Init | `systemd`, `openrc`, `runit`, `s6`, `sysvinit` |
| Firewall | `ufw`, `firewalld`, `nftables`, `iptables` |
| Contenedores | `docker`, `podman`, `incus`, `lxc`, `libvirt` |

La compatibilidad es degradable. Si una utilidad no existe o no hay permisos suficientes, el colector continúa y lo deja registrado en la salida o en `warnings.log`.

## Recomendaciones de ejecución

- Ejecuta como usuario normal para una foto básica del equipo.
- Ejecuta con `sudo` si necesitas más visibilidad sobre servicios, firewall, puertos, logs y configuraciones del sistema.
- Revisa el contenido de `configs.tar.gz` antes de moverlo, compartirlo o versionarlo.
- Trata la salida como inventario local sensible; no se sanitizan secretos automáticamente.

## Limitaciones actuales

- No restaura el sistema ni aplica rollback de configuraciones.
- La cobertura multi-distro depende de validarlo en varias familias de Linux reales.
- La detección de advisories y trust depende del backend de paquetes disponible en el host.

## Pruebas

```bash
bash tests/run_tests.sh
```

La prueba rápida usa un directorio temporal y no modifica los snapshots existentes dentro de `output/`.

## Licencia

Agrega aquí la licencia con la que vayas a publicar el repositorio, por ejemplo MIT, Apache-2.0 o GPL-3.0.