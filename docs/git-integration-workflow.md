# Flujo de Integracion Git para ServerAM1

Esta guia adapta el workflow de integracion usado en `senderman` al contexto real de ServerAM1.

## Objetivo

- Mantener `master` como rama de release.
- Introducir `develop` como rama de integracion.
- Asegurar que los cambios entren por PR con direccion valida.
- Automatizar tags semver desde GitHub Actions.
- Requerir revision de CODEOWNERS con `@CarloAndrePonceMiranda` para `master` y `develop`.

## Politica de ramas

- `feature/*` va a `develop`.
- `bugfix/*` va a `develop`.
- `hotfix/*` va a `master`.
- La parte despues del prefijo puede ser numerica, alfabetica o alfanumerica.
- Los mensajes de commit deben usar `fix(...)`, `feature(...)`, `hotfix(...)` o `chore(...)` seguidos de una descripcion.

Ejemplos validos:

- `feature/3-titulo-de-mercado`
- `feature/mercado-divisas-live`
- `bugfix/login-shell`
- `hotfix/v0-2-1-launcher`

## Excepcion legacy

La rama `3-titulo-de-mercado-a-indice-y-divisas` se mantiene como excepcion transitoria porque forma parte del historial temprano del repo. El workflow la acepta solo hacia `develop` y la trata como `feature` para efectos de release mientras siga activa.

No deben crearse ramas nuevas fuera de `feature/*`, `bugfix/*` o `hotfix/*`.

## CODEOWNERS

El archivo `.github/CODEOWNERS` define los owners activos del repo e incluye a `@CarloAndrePonceMiranda` como revisor requerido dentro del esquema de propietarios. Para que esto se convierta en control real, GitHub debe requerir review de CODEOWNERS en `master` y `develop`.

## Release check local

Antes de preparar una release, ejecuta:

```bash
bash scripts/check_release.sh
```

Ese check:

- valida el estado del arbol Git
- espera que los caches runtime vivan fuera de rutas versionadas, por ejemplo en `tmp/`
- valida que el ultimo tag siga `vX.Y.Z`
- ejecuta `bash tests/run_tests.sh`

Opciones utiles:

```bash
bash scripts/check_release.sh --allow-dirty
bash scripts/check_release.sh --skip-tests
bash scripts/check_commit_messages.sh --range origin/develop..HEAD
```

## Nomenclatura de commits

Formato esperado:

```text
fix(scope) Descripcion de cambios
feature(scope) Descripcion de cambios
hotfix(scope) Descripcion de cambios
chore(scope) Descripcion de cambios
```

Ejemplos:

- `fix(panel) corrige el estado vacio del ticker`
- `feature(workflow) agrega validacion de commits en PR`
- `hotfix(installer) corrige la apertura del launcher`
- `chore(release) actualiza la documentacion del flujo git`

Notas:

- Una rama `bugfix/*` normalmente debe contener commits `fix(...)`.
- La validacion automatica corre en PR mediante `.github/workflows/branch-policy.yml`.
- Los merge commits pueden omitirse de esta validacion; los commits de trabajo normales no.

## GitHub Actions

### Branch policy

`.github/workflows/branch-policy.yml` valida la direccion del PR:

- `feature/*` y `bugfix/*` solo pueden apuntar a `develop`
- `hotfix/*` solo puede apuntar a `master`
- la rama legacy `3-titulo-de-mercado-a-indice-y-divisas` solo puede apuntar a `develop`

Despues de un merge exitoso, las ramas `feature/*` y `bugfix/*` del mismo repo se eliminan automaticamente.

### Release management

`.github/workflows/release-management.yml` corre al hacer push a `master` o manualmente por `workflow_dispatch`.

Reglas de versionado:

- merge desde `feature/*` => bump minor
- merge desde `bugfix/*` => bump patch
- merge desde `hotfix/*` => bump patch
- merge desde la rama legacy => tratar como `feature`

Si el cambio viene de un hotfix, el workflow intenta abrir una PR de cascada `master -> develop`.

## Configuracion manual en GitHub

Estos pasos siguen siendo manuales y no viven dentro del repo:

1. Crear la rama `develop` desde `master`.
2. Cambiar la rama por defecto a `develop` cuando el equipo este listo.
3. Activar branch protection en `master` y `develop`.
4. Requerir pull request antes de merge.
5. Requerir review de CODEOWNERS.
6. Bloquear pushes directos a ramas protegidas.
7. Habilitar auto-delete de ramas.
8. Permitir a GitHub Actions escribir tags y abrir PRs.

## Recomendacion de adopcion

1. Fusionar o estabilizar la rama legacy actual.
2. Crear `develop`.
3. Subir `.github/`, `scripts/check_release.sh` y esta guia.
4. Activar branch protection.
5. Probar PRs validos y no validos.
6. Activar el tagging automatico en el siguiente merge a `master`.