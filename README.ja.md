# CleanDevMac

[English](README.md) | [العربية](README.ar.md) | [Español](README.es.md) | 日本語 | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

[![Downloads](https://img.shields.io/github/downloads/cleandevmac/cdm/total?style=flat-square&label=downloads&color=1f6feb)](https://github.com/cleandevmac/cdm/releases)
[![Latest release](https://img.shields.io/github/v/release/cleandevmac/cdm?style=flat-square&label=release&color=2da44e)](https://github.com/cleandevmac/cdm/releases/latest)
[![Stars](https://img.shields.io/github/stars/cleandevmac/cdm?style=flat-square&label=stars&color=d29922)](https://github.com/cleandevmac/cdm/stargazers)
[![License](https://img.shields.io/github/license/cleandevmac/cdm?style=flat-square&label=license&color=8957e5)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-111111?style=flat-square)](https://github.com/cleandevmac/cdm)
[![Donate](https://img.shields.io/badge/donate-PayPal-00457C?style=flat-square&logo=paypal&logoColor=white)](https://www.paypal.com/paypalme/hoangnc)

**CleanDevMac**（コマンドラインでは `cdm`）は、ディスクを圧迫している開発キャッシュ・ビルド成果物・アプリの残骸データを見つけ出し、それが何でどれくらいの大きさなのかを正確に見せたうえで、チェックを入れたものだけを削除するターミナル UI です。

ダウンロードのバッジは、リリースアセット `cdm` の取得回数を数えています。下にある `curl` はすべてそのアセットを叩くので、これがこのツールの実際の利用回数を表します。

サイト: **<https://cleandevmac.github.io>**

macOS 専用。純粋な bash で、依存関係はありません。テレメトリは一切なし — `cdm` が行うネットワーク通信は、自身のルール JSON の取得だけです。

## 実行する

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash
```

インストール手順はありません。スクリプトはパイプからそのまま実行され、スキャンして TUI を表示します。終了すると、Mac には何も残りません。

まずはドライラン。スキャンして報告するだけで、何も削除しません。

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash -s -- -n
```

## 手元に残す（任意）

URL なしで `cdm` を再実行したい場合だけ、これを行ってください。ここで唯一、ファイルが残る方法です。

```bash
mkdir -p ~/.local/bin
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm -o ~/.local/bin/cdm
chmod +x ~/.local/bin/cdm
cdm
```

`~/.local/bin` が `PATH` に含まれていることを確認してください（シェルの rc に `export PATH="$HOME/.local/bin:$PATH"`）。更新するには `curl -o` の行を再実行します。アンインストールは `rm ~/.local/bin/cdm` です。

![CleanDevMac](screenshot.png)

## 何を掃除するか

**1. 開発キャッシュとビルド成果物** — Xcode の DerivedData と DeviceSupport、Go のビルドキャッシュとモジュールキャッシュ、npm/npx/pnpm/yarn、JS のビルドツール（Turbo、Vite、webpack、Parcel、ESLint）、Gradle、Maven、sbt/Ivy、Cargo、Python（pip、uv、poetry、ruff、mypy）、Ruby/Bundler、Bun、Deno、CocoaPods、SwiftPM、Composer、Bazel、Zig、クラウド CLI（kubectl、AWS、gcloud、Azure）、Docker buildx、JetBrains、Playwright、そして Homebrew のダウンロードキャッシュ。

**2. Electron・ブラウザ・アプリのキャッシュ** — VS Code、Claude、Slack。Chrome、Brave、Edge、Vivaldi、Arc はブラウザのプロファイルごとにスキャンします。Firefox も対象です。さらにクラッシュ／テレメトリ SDK のキャッシュ（Sentry、Crashlytics、Sparkle）。

**3. プロジェクトのゴミ（リポジトリ単位でまとめて表示）** — `node_modules`、`dist`、`build`、`target`、`__pycache__`、および git で無視されているファイル。既定では無効で、`-p` を渡すと有効になります。対話的な実行では、キャッシュのスキャンが終わったあとに提案されます。

**4. Docker / Podman** — `system prune -af`（オプトイン）。名前付きボリュームには一切触れません。

**5. 取り残されたアプリのデータ** — すでにインストールされていないアプリの Application Support、Caches、Preferences。

## 安全性

- **項目ごとの確認なしに削除されるものはありません。** 計画とサイズを確認したうえで、`y` を入力します。
- **キャッシュは完全に削除されます** — 次のビルドで再生成されます。
- **取り残されたアプリのデータと git で無視されているファイルはゴミ箱に入る**ので、元に戻せます。
- **ルールに何が書かれていても決して触れない場所:** `~/Documents`、`~/Desktop`、`~/Downloads`、`~/Pictures`、`~/.ssh`、iCloud Drive。このガードはルールエンジンより下の層にあり、ルール側から無効にすることはできません。
- **アプリのサンドボックスと、Apple やシステムが所有するデータには一切触れません。**
- インストール済みアプリの一覧は **LaunchServices** から読み取るため、prefPane やプラグインなど `.app` ではないバンドルが取り残しと誤判定されることはありません。
- `--dry-run` は何も削除しません。
- すべての実行が `~/.cleandevmac/clean.log` に記録されます。

## TUI のキー操作

| キー | 動作 |
| --- | --- |
| `↑` / `↓`、`k` / `j` | 移動 |
| `Space` | 選択中の項目を切り替え |
| `a` / `s` / `n` | すべて選択 / 安全な既定値 / すべて解除 |
| `Enter`（または `d`） | その項目の実際のパスとサイズを表示 |
| `c` | クリーン — 項目ごとの計画を作り、`y` で確定 |
| `q`（または `Esc`） | 終了 |

項目は大きい順に並びます。安全に再生成されるキャッシュはあらかじめ選択済みです。Maven リポジトリ、Playwright のブラウザ、クラッシュログ、プロジェクトフォルダ、取り残されたアプリのデータは未選択の状態で始まります。`s` を押すと、この既定の選択に戻ります。

## 編集できるルール

対象はコードではなく `rules/` 以下の JSON にあります。パスの追加や削除は、次のファイルを編集して行います。

| ファイル | 内容 |
| --- | --- |
| `index.json` | マニフェスト — どのルールファイルを、どの順で読み込むか |
| `dev-caches.json` | 開発キャッシュとビルド成果物 |
| `app-caches.json` | Electron・ブラウザ・アプリのキャッシュ |
| `containers.json` | Docker / Podman |
| `project-junk.json` | リポジトリ単位のプロジェクトのゴミ |
| `orphans.json` | 取り残されたアプリのデータの検出 |

各カテゴリは `icon`、`name`、`desc`、`paths`、`default`（あらかじめ選択するかどうか）、`method`（`rm` は削除、`trash` はゴミ箱へ移動）を持つオブジェクトです。`--patterns <ディレクトリまたは URL>` で、自分のルールセットを `cdm` に読み込ませられます。

## オプション

| オプション | 効果 |
| --- | --- |
| `-n`, `--dry-run` | スキャンして報告するだけ。何も削除しない |
| `-y`, `--yes` | 非対話モード: あらかじめ選択された安全なキャッシュを掃除して終了する。プロジェクトフォルダ、取り残されたアプリのデータ、ゴミ箱には一切触れない |
| `-p`, `--projects` | コードリポジトリのプロジェクトのゴミもスキャンする |
| `--patterns SRC` | ローカルディレクトリまたはベース URL からルールを読み込む |
| `--no-color` | ANSI カラーを無効にする |
| `-h`, `--help` | 使い方 |

## 環境変数

| 変数 | 効果 |
| --- | --- |
| `CDM_REMOTE` | ローカルにコピーが見つからないときに、ルールを取得するベース URL |
| `CDM_PATTERNS` | ルールの取得元 — ローカルディレクトリまたはベース URL（`--patterns` と同じ） |

## 支援する

cdm は無料の MIT ライセンスで、これからもそのままです。有料版もテレメトリもなく、出し惜しみもしません。ディスクが戻ってきて、コーヒーでもおごろうかと思ってもらえたなら:

**[paypal.me/hoangnc](https://www.paypal.com/paypalme/hoangnc)**

リポジトリにスターを付けたり、ほかの開発者に紹介したりするのも、同じくらい助けになります。

## クレジット

いくつかのキャッシュの場所は、ほかのオープンソースの macOS クリーナーと照合して確認しました。

- [PureMac](https://github.com/momenbasel/PureMac) — MIT
- [mac-cleaner-cli](https://github.com/guhcostan/mac-cleaner-cli) — MIT
- [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go) — MIT
- [mac-cleanup-py](https://github.com/mac-cleanup/mac-cleanup-py) — Apache-2.0

ここにあるルールはこのツール独自のスキーマ向けに独自に書かれており、各パスは追加前に検証しています。

## ライセンス

MIT — [LICENSE](LICENSE) を参照してください。
