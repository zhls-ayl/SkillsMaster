

# SkillsMaster

English | [简体中文](README_CN.md)

SkillsMaster es una aplicación nativa de macOS para gestionar archivos de Skills y de raíz de Agentes entre múltiples agentes de codificación por IA desde una única interfaz de escritorio unificada.

Reúne operaciones que de otro modo estarían dispersas en el sistema de archivos, enlaces simbólicos, archivos de bloqueo, repositorios de Git y mercados, en una única aplicación local.

> Origen: este repositorio evolucionó a partir de un fork de [crossoverJie/SkillDeck](https://github.com/crossoverJie/SkillDeck.git) y ahora se mantiene como el producto independiente `SkillsMaster`.

## Por qué SkillsMaster

Si utilizas múltiples agentes de codificación por IA simultáneamente, suele surgir los mismos problemas:

- Las Skills están dispersas en diferentes directorios y son difíciles de inspeccionar de manera consistente
- `SKILL.md`, frontmatter, repositorio de origen y el estado de instalación son difíciles de rastrear
- Diferentes agentes heredan o leen Skills de manera distinta, por lo que el estado real de instalación no es obvio
- La instalación desde `Skills.sh`, ClawHub, SkillsHub o repositorios personalizados es inconsistente
- Mantener manualmente los enlaces simbólicos, copias físicas, comprobaciones de actualizaciones y archivos de bloqueo es tedioso

SkillsMaster convierte esos flujos de trabajo en una experiencia nativa de macOS.

## Capacidades principales

- Escanea y muestra Skills locales, incluidas instalaciones directas y heredadas
- Busca, ordena, edita, elimina, reasigna Agentes y verifica actualizaciones en `Installed > All Skills`
- Mantiene `SKILL.md` como la página principal de detalles al navegar por archivos relacionados dentro de la misma carpeta de la Skill, con vista previa y edición contextual
- Navega por los directorios raíz de los Agentes en `Agent Files` con vista previa de texto, edición integrada y acciones de Finder/Terminal/editor externo
- Configura el modo de instalación predeterminado de cada Agente: `symbolic link` o `physical copy`
- Instala Skills desde `Skills.sh`, ClawHub, SkillsHub y repositorios personalizados
- Verifica actualizaciones por lotes para Skills respaldadas por Git y SkillsHub
- Actualiza la aplicación de forma automática, priorizando el archivo de lanzamiento `universal.zip`
- Distribuye los artefactos de GitHub Release como `universal.zip`, `arm64.zip`, `x86_64.zip` y `universal.dmg`
- Admite la localización completa de la interfaz de la aplicación con `English` y `简体中文`, siguiendo la configuración del sistema de forma predeterminada y permitiendo una anulación manual en Ajustes

## Instalación

### Homebrew

```bash
brew tap zhls-ayl/skillsmaster
brew install --cask skillsmaster
```

Esta es la opción recomendada para la mayoría de los usuarios.

### Lanzamiento de GitHub

También puedes descargar los artefactos de lanzamiento directamente:

- `SkillsMaster-v<version>-universal.zip`
- `SkillsMaster-v<version>-arm64.zip`
- `SkillsMaster-v<version>-x86_64.zip`
- `SkillsMaster-v<version>-universal.dmg`

Página de lanzamiento:

- [GitHub Releases](https://github.com/zhls-ayl/SkillsMaster/releases)

### Ejecución desde el código fuente

```bash
git clone https://github.com/zhls-ayl/SkillsMaster.git
cd SkillsMaster
./run
```

## Requisitos

- macOS 14+
- Xcode 26+
- Swift 6.2+

Para la traducción en línea de inglés a chino simplificado en las páginas de detalles:

- macOS 26+
- Paquete de traducción sin conexión de inglés a chino simplificado instalado en el sistema
- Los artefactos de lanzamiento y las compilaciones locales de código fuente deben usar Swift 6.2+; las versiones más antiguas de las toolchains excluirán silenciosamente el soporte para `Translation.framework` en la compilación

## Agentes compatibles

- Claude Code
- Codex
- Gemini CLI
- GitHub Copilot
- OpenCode
- Antigravity
- Cursor
- Kiro CLI
- CodeBuddy
- OpenClaw
- Trae
- Hermes
- WorkBuddy
- ZCode

## Navegación principal

- `Installed`: inspeccionar, editar, asignar, eliminar y actualizar Skills locales
- `Marketplace`: explorar e instalar desde `Skills.sh`, ClawHub y SkillsHub
- `Repositories`: agregar repositorios SSH, HTTPS público o HTTPS autenticado con token, o importar `SKILL.md` / carpetas de skills locales a la fuente fija `LocalSkill`; luego explorar e instalar desde ellos
- `Agents`: inspeccionar Skills de Agente y archivos raíz de Agente

## Rutas importantes

- Directorio de Skills gestionadas canónico: `~/.skillsmaster/skills`
- Archivo de bloqueo canónico privado: `~/.skillsmaster/.skill-lock.json`
- Archivo de bloqueo de CLI de Skills heredado: `~/.agents/.skill-lock.json` (origen de importación manual en Ajustes)
- `Agent Files > skills/` está protegido y es de solo lectura dentro de la aplicación
- La actualización dentro de la aplicación requiere ejecutarse desde un paquete `.app` real; `swift run`, aplicaciones montadas en DMG y ubicaciones de descompresión temporal no están garantizadas para actualizarse in situ

## Capturas de pantalla

### Todas las Skills

![SkillsMaster All Skills](docs/screenshots/dashboard.png)

### Detalle de Skill

![SkillsMaster Skill Detail](docs/screenshots/skill-detail.png)

### Skills.sh

![SkillsMaster Skills.sh](docs/screenshots/Skills.sh.png)

### ClawHub

![SkillsMaster ClawHub](docs/screenshots/clawhub.png)

### SkillsHub

![SkillsMaster SkillsHub](docs/screenshots/SkillsHub.png)

### Repositorios

![SkillsMaster Repositories](docs/screenshots/Repositories.png)

### Archivos de Agente

![SkillsMaster Agent Files](docs/screenshots/AgentFiles.png)

### Skills de Agente

![SkillsMaster Agent Skills](docs/screenshots/AgentSkills.png)

## Comandos comunes

`./run` es el punto de entrada unificado del repositorio. Sin argumentos, por defecto se ejecuta `./run dev`.

```bash
./run
./run test
./run build -c release
./run package --version 1.2.3 --release-assets
./run release v1.2.3 --remote zhls-ayl --yes
./run ship 1.2.3 --yes
```

## Documentación

- [`README.md`](README.md): Descripción general en inglés, instalación, inicio rápido, capturas de pantalla
- [`README_CN.md`](README_CN.md): Descripción general en chino, instalación, inicio rápido, capturas de pantalla
- [`docs/Index.md`](docs/Index.md): Navegación de documentación y guía de actualizaciones
- [`docs/architecture.md`](docs/architecture.md): Estructura de implementación y rutas de almacenamiento
- [`docs/development.md`](docs/development.md): Flujo de trabajo de desarrollo y verificación
- [`docs/release.md`](docs/release.md): Empaquetado, lanzamiento, Homebrew y distribución
- [`AGENTS.md`](AGENTS.md): Reglas de colaboración, límites de confirmación y requisitos de validación
