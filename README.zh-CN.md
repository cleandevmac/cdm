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

仅支持 macOS。纯 bash，无依赖。零遥测——`cdm` 唯一会发起的网络请求，就是拉取它自己的规则 JSON。

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

**1. 开发缓存与构建产物** — Xcode 的 DerivedData 和 DeviceSupport、Go 的构建与模块缓存、npm/npx/pnpm/yarn、JS 构建工具（Turbo、Vite、webpack、Parcel、ESLint）、Gradle、Maven、sbt/Ivy、Cargo、Python（pip、uv、poetry、ruff、mypy）、Ruby/Bundler、Bun、Deno、CocoaPods、SwiftPM、Composer、Bazel、Zig、云 CLI（kubectl、AWS、gcloud、Azure）、Docker buildx、JetBrains、Playwright，以及 Homebrew 的下载缓存。

**2. Electron、浏览器与应用缓存** — VS Code、Claude、Slack；Chrome、Brave、Edge、Vivaldi 和 Arc 会按浏览器配置文件分别扫描；Firefox；以及崩溃／遥测 SDK 的缓存（Sentry、Crashlytics、Sparkle）。

**3. 项目垃圾，按仓库分组** — `node_modules`、`dist`、`build`、`target`、`__pycache__`，以及被 git 忽略的文件。默认关闭，传入 `-p` 启用。交互式运行时，会在缓存扫描结束后询问你是否要扫描。

**4. Docker / Podman** — `system prune -af`，需要主动选择。具名卷永远不会被动到。

**5. 残留的应用数据** — 属于那些已经卸载的应用的 Application Support、Caches 和 Preferences。

## 安全性

- **没有逐项确认，就不会删除任何东西。** 你会先看到计划和大小，然后输入 `y`。
- **缓存会被永久删除**——它们会在下一次构建时重新生成。
- **残留的应用数据和被 git 忽略的文件会移到废纸篓**，因此可以恢复。
- **无论规则怎么写都绝不碰的位置：** `~/Documents`、`~/Desktop`、`~/Downloads`、`~/Pictures`、`~/.ssh` 和 iCloud Drive。这道防线位于规则引擎之下，规则无法绕过它。
- **应用沙盒以及归 Apple 或系统所有的数据永远不会被动到。**
- 已安装应用的列表读取自 **LaunchServices**，所以 prefPane、插件等非 `.app` 包不会被误判为残留。
- `--dry-run` 不会删除任何东西。
- 每一次运行都会记录到 `~/.cleandevmac/clean.log`。

## TUI 按键

| 按键 | 操作 |
| --- | --- |
| `↑` / `↓`、`k` / `j` | 移动 |
| `Space` | 切换当前项的勾选状态 |
| `a` / `s` / `n` | 全选／安全默认／全不选 |
| `Enter`（或 `d`） | 查看某一项背后确切的路径和大小 |
| `c` | 清理——生成逐项计划，按 `y` 确认 |
| `q`（或 `Esc`） | 退出 |

条目按占用从大到小排列。可安全再生的缓存会预先勾选；Maven 仓库、Playwright 浏览器、崩溃日志、项目文件夹和残留的应用数据默认都不勾选——按 `s` 会重置回这套默认选择。

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
