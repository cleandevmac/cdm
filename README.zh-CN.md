# CleanDevMac

[English](README.md) | [العربية](README.ar.md) | [Español](README.es.md) | [日本語](README.ja.md) | 简体中文 | [繁體中文](README.zh-TW.md)

[![Downloads](https://img.shields.io/github/downloads/cleandevmac/cdm/total?style=flat-square&label=downloads&color=1f6feb)](https://github.com/cleandevmac/cdm/releases)
[![Latest release](https://img.shields.io/github/v/release/cleandevmac/cdm?style=flat-square&label=release&color=2da44e)](https://github.com/cleandevmac/cdm/releases/latest)
[![Stars](https://img.shields.io/github/stars/cleandevmac/cdm?style=flat-square&label=stars&color=d29922)](https://github.com/cleandevmac/cdm/stargazers)
[![License](https://img.shields.io/github/license/cleandevmac/cdm?style=flat-square&label=license&color=8957e5)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-111111?style=flat-square)](https://github.com/cleandevmac/cdm)
[![Donate](https://img.shields.io/badge/donate-PayPal-00457C?style=flat-square&logo=paypal&logoColor=white)](https://www.paypal.com/paypalme/hoangnc)

**CleanDevMac**（命令行里就是 `cdm`）是一个终端界面工具：它找出正在吞噬你磁盘的开发缓存、构建产物和应用残留数据，清楚地告诉你它们是什么、占了多大，然后只删除你勾选的那些。

下载徽章统计的是 `cdm` 这个发布资源的抓取次数。下面每一条 `curl` 命令都会请求该资源，所以它就是这个工具真实的使用计数。

网站：**<https://cleandevmac.github.io>**

仅支持 macOS。纯 bash，无依赖。零遥测——`cdm` 唯一会发起的网络请求，就是拉取它自己的规则 JSON。（清理后按 `b` 会在浏览器里打开捐赠链接；不会向任何地方发送任何数据。）

## 运行

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash
```

没有安装步骤。脚本直接从管道运行、扫描，然后把 TUI 交给你。退出之后，它不会在你的 Mac 上留下任何东西。

建议先跑一次预演：只扫描并报告，不删除任何东西。

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash -s -- -n
```

## 留在本地（可选）

只有当你想不带 URL 再次运行 `cdm` 时才需要这样做。这是这里唯一会留下文件的做法：

```bash
mkdir -p ~/.local/bin
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm -o ~/.local/bin/cdm
chmod +x ~/.local/bin/cdm
cdm
```

请确认 `~/.local/bin` 在你的 `PATH` 中（在 shell 的 rc 文件里加入 `export PATH="$HOME/.local/bin:$PATH"`）。重新执行 `curl -o` 那一行即可更新。卸载：`rm ~/.local/bin/cdm`。

![CleanDevMac](screenshot.png)

## 它清理什么

**1. 开发缓存与构建产物** — Xcode 的 DerivedData 和 DeviceSupport、Go 的构建与模块缓存、npm/npx/pnpm/yarn、JS 构建工具（Turbo、Vite、webpack、Parcel、ESLint）、Gradle、Maven、sbt/Ivy、Cargo、Python（pip、uv、poetry、ruff、mypy）、Ruby/Bundler、Bun、Deno、CocoaPods、SwiftPM、Composer、Bazel、Zig、云 CLI（kubectl、AWS、gcloud、Azure）、Docker buildx、JetBrains、Playwright、Homebrew 和 PlatformIO 的下载缓存、Android Studio 缓存与模拟器快照，以及已不被任何 AVD 使用的 Android 系统镜像。

**2. 会重新下载的已安装 SDK 组件** — 全部需要主动勾选，每一行都写明它如何恢复：PlatformIO 已安装的平台与工具链（下一次 `pio run` 会下载所需的部分）；Android NDK、CMake 与 SDK 源码；除最新版之外的所有 Android build-tools 与平台版本；60 天内没人启动过的 AVD 的系统镜像（该行会列出 AVD 名称，镜像重新安装之前该 AVD 无法启动）；以及默认与 stable 之外的每个 Rust 工具链，用 `rustup toolchain uninstall` 移除（该行会列出固定使用它的仓库）。`sdkmanager`、`adb`、模拟器以及 PlatformIO 自己的 `pio` 永远不会被列出。

**3. 旧的 Claude Code 对话记录** — 需要主动勾选：30 天未动过的会话，连同其子代理与工具输出文件，会移到废纸篓。运行中的会话、自动记忆和设置永远不会被动到。历史记录很大时，`cdm` 还会打印 `~/.claude/settings.json` 里该加的键（`desktopSessionCleanupPeriodDays`）：加上后，Claude Code 会自己删除过期的 Desktop 与 Cowork 会话。`cdm` 从不修改那个文件。

**4. Electron、浏览器与应用缓存** — VS Code、Claude（包括每个预览的 webview 缓存，以及可选的 Cowork 虚拟机镜像）、Slack；Chrome、Brave、Edge、Vivaldi 和 Arc 会按浏览器配置文件分别扫描；Firefox；以及崩溃／遥测 SDK 的缓存（Sentry、Crashlytics、Sparkle）。

**5. 项目垃圾，按仓库分组** — `node_modules`、`dist`、`build`、`target`、`__pycache__`，以及被 git 忽略的文件。只会是仓库自己用 git 忽略的内容。默认关闭，传入 `-p` 启用。交互式运行时，会在缓存扫描结束后询问你是否要扫描。

**6. Docker / Podman** — `system prune -af`，以及对每个 buildx builder 的缓存执行 `buildx prune -af`（已停止的 builder 会为此启动，完成后再停止），需要主动选择。具名卷永远不会被删除。

**7. 残留的应用数据** — 属于那些已经卸载的应用的 Application Support、Caches 和 Preferences。

**重启能释放多少空间。** 交换空间（swap）、macOS 开机时清空的临时文件夹，以及仍被应用打开着的已删除文件，都不是任何清理工具能删除的文件；磁盘快满时，它们加起来可能有几十 GB。当它们超过剩余空间时，`cdm` 会在磁盘那一行下面说明，并在菜单里再显示一次，同时列出仍打开着已删除文件的应用：退出这些应用，不用重启就能释放这一部分。

## 安全性

- **没有逐项确认，就不会删除任何东西。** 你会先看到计划和大小，然后输入 `y`。
- **缓存会被永久删除**——它们会在下一次构建时重新生成。
- **残留的应用数据、被 git 忽略的文件以及旧的 Claude Code 对话记录会移到废纸篓**，因此可以恢复。
- **凡是会移除已安装软件的项目都默认不勾选**——SDK 组件、工具链、模拟器镜像——并且每一行都写明如何恢复。Rust 工具链由 `rustup` 移除，从不使用 `rm`。
- **无论规则怎么写都绝不碰的位置：** `~/Documents`、`~/Desktop`、`~/Downloads`、`~/Pictures`、`~/.ssh` 和 iCloud Drive。这道防线位于规则引擎之下，规则无法绕过它。
- **只有被仓库 git 忽略的文件夹才算项目垃圾。** 仅仅匹配 `dist`、`build` 或 `Pods` 这样的名字是不够的——cdm 会用 git 确认该目录既被忽略*又*未被跟踪，所以存放发布脚本、受版本控制的 `build/`，或已提交的 `dist/`，都会原样保留。
- **`.env*` 文件永远不会被列入删除。** 即使它们被 git 忽略，项目扫描也会跳过——里面存放着无法重新生成的密钥和本地配置。
- **应用沙盒以及归 Apple 或系统所有的数据永远不会被动到。**
- 已安装应用的列表读取自 **LaunchServices**，所以 prefPane、插件等非 `.app` 包不会被误判为残留。
- `--dry-run` 不会删除任何东西。
- 每一次运行都会记录到 `~/.cleandevmac/clean.log`。

## TUI 按键

`cdm` 会在扫描前显示磁盘状况——总容量、已用、可用；扫描结束后显示最多能回收多少；清理之后再显示一次磁盘现在的状况。

| 按键 | 操作 |
| --- | --- |
| `↑` / `↓`、`k` / `j` | 移动 |
| `Space` | 切换当前项的勾选状态 |
| `a` / `s` / `n` | 全选／安全默认／全不选 |
| `Enter`（或 `d`） | 查看某一项背后确切的路径和大小 |
| `c` | 清理——生成逐项计划，按 `y` 确认 |
| `q`（或 `Esc`） | 退出 |

清理完成后会打印结果，并询问下一步：`r` 重新扫描 · `b` 请我喝杯咖啡 · `q` 退出（默认——按 Enter 或任意其他键同样是退出）。

条目按占用从大到小排列。可安全再生的缓存会预先勾选；Maven 仓库、Playwright 浏览器、崩溃日志、已安装的 SDK 组件、旧的 Claude Code 对话记录、项目文件夹和残留的应用数据默认都不勾选——按 `s` 会重置回这套默认选择。

## 可编辑的规则

清理目标写在 `rules/` 下的 JSON 里，而不是代码里。增删路径只需编辑这些文件：

| 文件 | 内容 |
| --- | --- |
| `index.json` | 清单——加载哪些规则文件，以及加载顺序 |
| `dev-caches.json` | 开发缓存与构建产物 |
| `app-caches.json` | Electron、浏览器与应用缓存 |
| `containers.json` | Docker / Podman |
| `project-junk.json` | 按仓库归类的项目垃圾 |
| `orphans.json` | 残留应用数据的识别 |

每个分类都是一个对象，包含 `icon`、`name`、`desc`、`paths`、`default`（是否预先勾选）和 `method`（`rm` 表示删除，`trash` 表示移到废纸篓）。用 `--patterns <目录或 URL>` 可以让 `cdm` 使用你自己的规则集。

分类还可以带 `procs`——运行时会重写这些缓存的应用的进程名（`"procs": ["Google Chrome", "Code"]`）。`cdm` 会在请你确认之前列出其中正在运行的应用，因为在应用运行时清除它的缓存，空间马上又会被占回去。名称必须与 `pgrep -x` 完全一致。

少数分类设有 `kind`，由脚本算出要列出的内容：`android-images`（没有任何 AVD 启动的系统镜像）、`android-idle-images`（只被闲置达 `idleDays` 的 AVD 启动的镜像）、`older-versions`（每个 glob 是一组版本，列出除最新版外的全部）、`rust-toolchains`（默认与 stable 之外的工具链）和 `claude-transcripts`（`idleDays` 内未动过的会话，一律移到废纸篓）。它们从 `images` 或 `candidates` 读取 glob，从不读 `paths`，因此不认识该 kind 的旧版 `cdm` 什么也不会列出。

## 选项

| 选项 | 作用 |
| --- | --- |
| `-n`, `--dry-run` | 扫描并报告；不删除任何东西 |
| `-y`, `--yes` | 非交互模式：清理预先勾选的安全缓存后退出。绝不触碰项目文件夹、残留应用数据或废纸篓 |
| `-p`, `--projects` | 同时扫描代码仓库中的项目垃圾 |
| `--patterns SRC` | 从本地目录或基础 URL 加载规则 |
| `--no-color` | 关闭 ANSI 颜色 |
| `-h`, `--help` | 用法 |

## 环境变量

| 变量 | 作用 |
| --- | --- |
| `CDM_REMOTE` | 找不到本地副本时，拉取规则所用的基础 URL |
| `CDM_PATTERNS` | 规则来源——本地目录或基础 URL（等同于 `--patterns`） |

## 支持

cdm 是免费的 MIT 项目，并且会一直如此——没有付费版，没有遥测，也不藏私。如果它帮你把磁盘空间要了回来，而你想请我喝杯咖啡：

**[paypal.me/hoangnc](https://www.paypal.com/paypalme/hoangnc)**

给仓库点个 star，或者把它告诉另一位开发者，同样很有帮助。

## 致谢

部分缓存位置参考并交叉核对了其他开源的 macOS 清理工具：

- [PureMac](https://github.com/momenbasel/PureMac) — MIT
- [mac-cleaner-cli](https://github.com/guhcostan/mac-cleaner-cli) — MIT
- [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go) — MIT
- [mac-cleanup-py](https://github.com/mac-cleanup/mac-cleanup-py) — Apache-2.0

这里的规则是针对本工具自己的 schema 独立编写的，每一条路径在加入前都经过了验证。

## 许可证

MIT — 见 [LICENSE](LICENSE)。
