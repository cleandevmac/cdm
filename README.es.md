# CleanDevMac

[English](README.md) | [العربية](README.ar.md) | Español | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

[![Downloads](https://img.shields.io/github/downloads/cleandevmac/cdm/total?style=flat-square&label=downloads&color=1f6feb)](https://github.com/cleandevmac/cdm/releases)
[![Latest release](https://img.shields.io/github/v/release/cleandevmac/cdm?style=flat-square&label=release&color=2da44e)](https://github.com/cleandevmac/cdm/releases/latest)
[![Stars](https://img.shields.io/github/stars/cleandevmac/cdm?style=flat-square&label=stars&color=d29922)](https://github.com/cleandevmac/cdm/stargazers)
[![License](https://img.shields.io/github/license/cleandevmac/cdm?style=flat-square&label=license&color=8957e5)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-111111?style=flat-square)](https://github.com/cleandevmac/cdm)
[![Donate](https://img.shields.io/badge/donate-PayPal-00457C?style=flat-square&logo=paypal&logoColor=white)](https://www.paypal.com/paypalme/hoangnc)

**CleanDevMac** — `cdm` en tu línea de comandos — es una interfaz de terminal que encuentra las cachés de desarrollo, los artefactos de compilación y los restos de datos de aplicaciones que se están comiendo tu disco, te muestra exactamente qué son y cuánto ocupan, y borra solo lo que tú marques.

La insignia de descargas cuenta las peticiones al recurso de release `cdm`. Cada `curl` de aquí abajo llega a ese recurso, así que es el contador real de uso de esta herramienta.

Sitio: **<https://cleandevmac.github.io>**

Solo para macOS. Bash puro, sin dependencias. Cero telemetría: la única llamada de red que hace `cdm` es la descarga de su propio JSON de reglas.

## Ejecútalo

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash
```

No hay paso de instalación. El script se ejecuta directamente desde la tubería, escanea y te entrega la TUI. Cuando termina, no deja nada suyo en tu Mac.

Prueba primero en seco: escanea e informa, no borra nada.

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash -s -- -n
```

## Consérvalo (opcional)

Haz esto solo si quieres volver a ejecutar `cdm` sin la URL. Es lo único de aquí que sí deja un archivo:

```bash
mkdir -p ~/.local/bin
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm -o ~/.local/bin/cdm
chmod +x ~/.local/bin/cdm
cdm
```

Asegúrate de que `~/.local/bin` esté en tu `PATH` (`export PATH="$HOME/.local/bin:$PATH"` en el rc de tu shell). Vuelve a ejecutar la línea `curl -o` para actualizar. Para desinstalar: `rm ~/.local/bin/cdm`.

![CleanDevMac](screenshot.png)

## Qué limpia

**1. Cachés de desarrollo y artefactos de compilación** — DerivedData y DeviceSupport de Xcode, caché de compilación y de módulos de Go, npm/npx/pnpm/yarn, herramientas de build de JS (Turbo, Vite, webpack, Parcel, ESLint), Gradle, Maven, sbt/Ivy, Cargo, Python (pip, uv, poetry, ruff, mypy), Ruby/Bundler, Bun, Deno, CocoaPods, SwiftPM, Composer, Bazel, Zig, CLIs de nube (kubectl, AWS, gcloud, Azure), Docker buildx, JetBrains, Playwright y la caché de descargas de Homebrew.

**2. Cachés de Electron, navegadores y aplicaciones** — VS Code, Claude, Slack; Chrome, Brave, Edge, Vivaldi y Arc analizados por perfil de navegador; Firefox; y cachés de SDK de fallos y telemetría (Sentry, Crashlytics, Sparkle).

**3. Basura de proyectos, agrupada por repositorio** — `node_modules`, `dist`, `build`, `target`, `__pycache__` y archivos ignorados por git. Desactivado por defecto; usa `-p` para habilitarlo. Las ejecuciones interactivas te lo ofrecen al terminar el escaneo de cachés.

**4. Docker / Podman** — `system prune -af`, opcional. Los volúmenes con nombre nunca se tocan.

**5. Datos de aplicaciones huérfanos** — Application Support, Caches y Preferences que pertenecen a aplicaciones que ya no están instaladas.

## Seguridad

- **No se borra nada sin una confirmación detallada.** Ves el plan y los tamaños, y entonces escribes `y`.
- **Las cachés se borran de forma permanente**: se regeneran en la siguiente compilación.
- **Los datos huérfanos de aplicaciones y los archivos ignorados por git van a la Papelera**, así que se pueden recuperar.
- **Nunca se tocan, digan lo que digan las reglas:** `~/Documents`, `~/Desktop`, `~/Downloads`, `~/Pictures`, `~/.ssh` y iCloud Drive. Esta protección está por debajo del motor de reglas: una regla no puede saltársela.
- **Los sandboxes de aplicaciones y los datos propiedad de Apple o del sistema nunca se tocan.**
- La lista de aplicaciones instaladas se lee de **LaunchServices**, así que los prefPanes, plugins y otros paquetes que no son `.app` no se marcan por error como huérfanos.
- `--dry-run` no borra nada.
- Cada ejecución se registra en `~/.cleandevmac/clean.log`.

## Teclas de la TUI

| Tecla | Acción |
| --- | --- |
| `↑` / `↓`, `k` / `j` | Moverse |
| `Space` | Marcar o desmarcar el elemento seleccionado |
| `a` / `s` / `n` | Seleccionar todo / valores seguros por defecto / nada |
| `Enter` (o `d`) | Mostrar las rutas y los tamaños exactos detrás de un elemento |
| `c` | Limpiar: construye un plan detallado, confirma con `y` |
| `q` (o `Esc`) | Salir |

Los elementos se ordenan de mayor a menor. Las cachés regenerables seguras vienen premarcadas; el repositorio de Maven, los navegadores de Playwright, los registros de fallos, las carpetas de proyectos y los datos de aplicaciones huérfanos empiezan sin marcar. `s` restablece esa selección por defecto.

## Reglas editables

Los objetivos viven en JSON dentro de `rules/`, no en el código. Añade o quita rutas editando estos archivos:

| Archivo | Contenido |
| --- | --- |
| `index.json` | Manifiesto: qué archivos de reglas se cargan y en qué orden |
| `dev-caches.json` | Cachés de desarrollo y artefactos de compilación |
| `app-caches.json` | Cachés de Electron, navegadores y aplicaciones |
| `containers.json` | Docker / Podman |
| `project-junk.json` | Basura de proyectos por repositorio |
| `orphans.json` | Detección de datos de aplicaciones huérfanos |

Cada categoría es un objeto con `icon`, `name`, `desc`, `paths`, `default` (premarcada o no) y `method` (`rm` para borrar, `trash` para mover a la Papelera). Apunta `cdm` a tu propio conjunto con `--patterns <directorio-o-url>`.

## Opciones

| Opción | Efecto |
| --- | --- |
| `-n`, `--dry-run` | Escanea e informa; no borra nada |
| `-y`, `--yes` | No interactivo: limpia las cachés seguras premarcadas y sale. Nunca toca carpetas de proyectos, datos de aplicaciones huérfanos ni la Papelera |
| `-p`, `--projects` | Analiza también los repositorios de código en busca de basura de proyectos |
| `--patterns SRC` | Carga las reglas desde un directorio local o una URL base |
| `--no-color` | Desactiva el color ANSI |
| `-h`, `--help` | Uso |

## Entorno

| Variable | Efecto |
| --- | --- |
| `CDM_REMOTE` | URL base desde la que se descargan las reglas cuando no se encuentra una copia local |
| `CDM_PATTERNS` | Origen de las reglas: un directorio local o una URL base (igual que `--patterns`) |

## Apoyo

cdm es gratuito y MIT, y seguirá siéndolo: sin versión de pago, sin telemetría, sin nada reservado. Si te ha devuelto tu disco y te apetece invitarme a un café:

**[paypal.me/hoangnc](https://www.paypal.com/paypalme/hoangnc)**

Darle una estrella al repositorio o hablarle de él a otra persona que programe ayuda igual de bien.

## Créditos

Algunas ubicaciones de cachés se contrastaron con otros limpiadores de macOS de código abierto:

- [PureMac](https://github.com/momenbasel/PureMac) — MIT
- [mac-cleaner-cli](https://github.com/guhcostan/mac-cleaner-cli) — MIT
- [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go) — MIT
- [mac-cleanup-py](https://github.com/mac-cleanup/mac-cleanup-py) — Apache-2.0

Las reglas de aquí están escritas de forma independiente para el esquema propio de esta herramienta, y cada ruta se verificó antes de añadirla.

## Licencia

MIT — consulta [LICENSE](LICENSE).
