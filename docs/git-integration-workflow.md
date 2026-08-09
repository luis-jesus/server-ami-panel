# Flujo de Integracion Git para ServerAM1

Esta guia adapta el workflow de integracion usado en `senderman` al contexto real de ServerAM1.

## Objetivo

- Mantener `master` como rama de release.
- Introducir `develop` como rama de integracion.
- Asegurar que los cambios entren por PR con direccion valida.
- Automatizar tags semver desde GitHub Actions.
- Requerir revision de CODEOWNERS con `@CarloAndrePonceMiranda` para `master` y `develop`.

## Politica de ramas

- `feature-major/*` va a `develop` y solicita un incremento major.
- `feature/*` va a `develop`.
- `bugfix/*` va a `develop`.
- `hotfix/*` va a `master`.
- `develop` va a `master` unicamente mediante la PR automatica de promocion.
- `master` va a `develop` unicamente mediante una PR de cascada de hotfix.
- La parte despues del prefijo puede ser numerica, alfabetica o alfanumerica.
- Los mensajes de commit deben usar `fix(...)`, `feature(...)`, `hotfix(...)` o `chore(...)` seguidos de una descripcion.

Ejemplos validos:

- `feature-major/api-v2`
- `feature/3-titulo-de-mercado`
- `feature/mercado-divisas-live`
- `bugfix/login-shell`
- `hotfix/v0-2-1-launcher`

## Excepcion legacy

La rama `3-titulo-de-mercado-a-indice-y-divisas` se mantiene como excepcion transitoria porque forma parte del historial temprano del repo. El workflow la acepta solo hacia `develop` y la trata como `feature` para efectos de release mientras siga activa.

No deben crearse ramas nuevas fuera de `feature-major/*`, `feature/*`, `bugfix/*` o `hotfix/*`.

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

- `feature-major/*`, `feature/*` y `bugfix/*` solo pueden apuntar a `develop`
- `hotfix/*` solo puede apuntar a `master`
- `develop` solo puede apuntar a `master` para una promocion de release
- `master` solo puede apuntar a `develop` para una cascada
- la rama legacy `3-titulo-de-mercado-a-indice-y-divisas` solo puede apuntar a `develop`

Despues de un merge exitoso, las ramas `feature-major/*`, `feature/*` y `bugfix/*` del mismo repo se eliminan automaticamente.

### Release promotion

`.github/workflows/release-promotion.yml` corre despues de cada PR fusionada hacia `develop` y tambien mediante `workflow_dispatch`.

- El tipo se obtiene del nombre de la rama fusionada, nunca del mensaje de commit.
- `feature-major/*` solicita major.
- `feature/*` y `bugfix/*` solicitan minor.
- Si hay varios cambios pendientes, se aplica la precedencia `major > minor > patch`.
- El workflow crea o actualiza una sola PR draft `develop -> master`.
- La PR conserva el tipo en una etiqueta `release-kind:*` y en metadatos de su cuerpo.
- Un maintainer debe marcar la PR como Ready for review para ejecutar checks y solicitar revisiones.

Reglas SemVer:

| Rama origen | Tipo | Ejemplo desde `v1.4.2` |
| --- | --- | --- |
| `feature-major/*` | major | `v2.0.0` |
| `feature/*` | minor | `v1.5.0` |
| `bugfix/*` | minor | `v1.5.0` |
| `hotfix/*` | patch | `v1.4.3` |

### Release management

`.github/workflows/release-management.yml` corre al hacer push a `master` o manualmente por `workflow_dispatch`.

El flujo automatico acepta dos entradas a `master`:

- PR `develop -> master`: lee el tipo desde la etiqueta y valida los metadatos de la PR.
- PR `hotfix/* -> master`: aplica patch directamente desde el prefijo de rama.

El workflow crea un tag anotado, pero la GitHub Release se publica manualmente. Si el cambio viene de un hotfix, abre una PR draft de cascada `master -> develop`.

El tagging es reanudable. Si un tag SemVer ya apunta al mismo commit de `master`, el workflow reutiliza ese tag y continua con la cascada pendiente. Nunca debe calcular otro patch para reparar una PR de cascada fallida.

Para una recuperacion manual se puede ejecutar `workflow_dispatch` indicando explicitamente `release_kind` y `source_branch`.

## Recuperacion de una cascada fallida

Si el tag se publico pero la PR `master -> develop` fallo:

1. No reejecutar una version antigua del workflow que calcule el siguiente tag sin comprobar `HEAD`.
2. Conservar el tag ya publicado.
3. Habilitar el permiso de creacion de PRs para Actions.
4. Reejecutar el workflow reanudable o abrir manualmente `master -> develop`.
5. Fusionar la cascada sin generar otro incremento de version.

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
9. En `Settings -> Actions -> General -> Workflow permissions`, seleccionar permisos de escritura y habilitar `Allow GitHub Actions to create and approve pull requests`.

Los workflows declaran `contents: write`, `pull-requests: write` e `issues: write` donde corresponde. Esos permisos YAML no sustituyen el control general del repositorio.

## Recomendacion de adopcion

1. Fusionar o estabilizar la rama legacy actual.
2. Crear `develop`.
3. Subir `.github/`, `scripts/check_release.sh` y esta guia.
4. Activar branch protection.
5. Probar PRs validos y no validos.
6. Activar el tagging automatico en el siguiente merge a `master`.