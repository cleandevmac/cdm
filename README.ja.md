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

macOS 専用。純粋な bash で、依存関係はありません。テレメトリは一切なし — `cdm` が行うネットワーク通信は、自身のルール JSON の取得だけです。（クリーン後に `b` を押すと寄付リンクがブラウザで開きますが、送信されるものは何もありません。）

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

**1. 開発キャッシュとビルド成果物** — Xcode の DerivedData と DeviceSupport、Go のビルドキャッシュとモジュールキャッシュ、npm/npx/pnpm/yarn、JS のビルドツール（Turbo、Vite、webpack、Parcel、ESLint）、Gradle、Maven、sbt/Ivy、Cargo、Python（pip、uv、poetry、ruff、mypy）、Ruby/Bundler、Bun、Deno、CocoaPods、SwiftPM、Composer、Bazel、Zig、クラウド CLI（kubectl、AWS、gcloud、Azure）、Docker buildx、JetBrains、Playwright、Homebrew と PlatformIO のダウンロードキャッシュ、Android Studio のキャッシュとエミュレータのスナップショット、そしてもうどの AVD も使っていない Android のシステムイメージ。

**2. 再ダウンロードできる、インストール済みの SDK 一式** — すべてオプトインで、各行にどう元に戻るかが書かれています。PlatformIO のインストール済みプラットフォームとツールチェーン（次の `pio run` が必要な分を取得します）、Android の NDK・CMake・SDK ソース、最新版を除くすべての Android build-tools とプラットフォーム、60 日間だれも起動していない AVD のシステムイメージ（行にその AVD の名前が出ます。イメージを入れ直すまで、その AVD は起動しません）、そして既定でも stable でもない Rust ツールチェーン（`rustup toolchain uninstall` で削除します。それを固定しているリポジトリがあれば行に表示します）。`sdkmanager`、`adb`、エミュレータ、PlatformIO 自身の `pio` が候補になることはありません。

**3. 古い Claude Code のトランスクリプト** — オプトイン。30 日間触れていないセッションを、サブエージェントやツール出力のファイルごとゴミ箱に移します。実行中のセッション、自動メモリ、設定には触れません。履歴が大きいときは、Claude Code 自身に Desktop と Cowork の古いセッションを削除させる `~/.claude/settings.json` のキー（`desktopSessionCleanupPeriodDays`）も表示します。そのファイルを `cdm` が書き換えることはありません。

**4. Electron・ブラウザ・アプリのキャッシュ** — VS Code、Claude（プレビューごとの webview キャッシュと、オプトインで Cowork の VM イメージを含む）、Slack。Chrome、Brave、Edge、Vivaldi、Arc はブラウザのプロファイルごとにスキャンします。Firefox も対象です。さらにクラッシュ／テレメトリ SDK のキャッシュ（Sentry、Crashlytics、Sparkle）。

**5. プロジェクトのゴミ（リポジトリ単位でまとめて表示）** — `node_modules`、`dist`、`build`、`target`、`__pycache__`、および git で無視されているファイル。対象は、リポジトリ自身が git で無視しているものだけです。既定では無効で、`-p` を渡すと有効になります。対話的な実行では、キャッシュのスキャンが終わったあとに提案されます。

**6. Docker / Podman** — `system prune -af` と、buildx の各ビルダーのキャッシュに対する `buildx prune -af`（オプトイン。停止中のビルダーはそのために起動し、終わったら再び停止します）。名前付きボリュームは決して削除しません。

**7. 取り残されたアプリのデータ** — すでにインストールされていないアプリの Application Support、Caches、Preferences。

**再起動で空く容量。** スワップ、macOS が起動時に空にする一時フォルダ、そしてアプリが開いたままの削除済みファイルは、どのクリーナーにも削除できるファイルではありませんが、ディスクがいっぱいのときには合計で数十 GB になることがあります。それが空き容量を上回るとき、`cdm` はディスクの行の下とメニューの中にそのことを表示し、削除済みファイルを開いたままのアプリを挙げます。それらのアプリを終了すれば、その分は再起動せずに空きます。

## 安全性

- **項目ごとの確認なしに削除されるものはありません。** 計画とサイズを確認したうえで、`y` を入力します。
- **キャッシュは完全に削除されます** — 次のビルドで再生成されます。
- **取り残されたアプリのデータ、git で無視されているファイル、古い Claude Code のトランスクリプトはゴミ箱に入る**ので、元に戻せます。
- **インストール済みのソフトウェアを消すものは、すべて未選択で始まります** — SDK の一部、ツールチェーン、エミュレータのイメージ。各行にどう元に戻るかが書かれています。Rust のツールチェーンは `rm` ではなく `rustup` が削除します。
- **ルールに何が書かれていても決して触れない場所:** `~/Documents`、`~/Desktop`、`~/Downloads`、`~/Pictures`、`~/.ssh`、iCloud Drive。このガードはルールエンジンより下の層にあり、ルール側から無効にすることはできません。
- **フォルダがプロジェクトのゴミになるのは、リポジトリが git で無視している場合だけです。** `dist`、`build`、`Pods` のような名前に一致するだけでは足りません。cdm はそのディレクトリが無視されていて、*かつ*追跡されていないことを git で確かめるので、リリース用スクリプトを入れた追跡中の `build/` やコミット済みの `dist/` はそのまま残ります。
- **`.env*` ファイルが削除の候補になることはありません。** git で無視されていても、プロジェクトのスキャンはこれらを飛ばします。秘密情報やローカル設定が入っていて、何からも再生成できないからです。
- **アプリのサンドボックスと、Apple やシステムが所有するデータには一切触れません。**
- インストール済みアプリの一覧は **LaunchServices** から読み取るため、prefPane やプラグインなど `.app` ではないバンドルが取り残しと誤判定されることはありません。
- `--dry-run` は何も削除しません。
- すべての実行が `~/.cleandevmac/clean.log` に記録されます。

## TUI のキー操作

`cdm` はスキャン前にディスクの状態（合計・使用中・空き）を表示し、スキャン後には解放できる最大量を、クリーン後には現在のディスクの状態を表示します。

| キー | 動作 |
| --- | --- |
| `↑` / `↓`、`k` / `j` | 移動 |
| `Space` | 選択中の項目を切り替え |
| `a` / `s` / `n` | すべて選択 / 安全な既定値 / すべて解除 |
| `Enter`（または `d`） | その項目の実際のパスとサイズを表示 |
| `c` | クリーン — 項目ごとの計画を作り、`y` で確定 |
| `q`（または `Esc`） | 終了 |

クリーン後は結果を表示し、次にどうするか尋ねます: `r` 再スキャン・`b` コーヒーをおごる・`q` 終了（既定。Enter やその他のキーも同じ）。

項目は大きい順に並びます。安全に再生成されるキャッシュはあらかじめ選択済みです。Maven リポジトリ、Playwright のブラウザ、クラッシュログ、インストール済みの SDK 一式、古い Claude Code のトランスクリプト、プロジェクトフォルダ、取り残されたアプリのデータは未選択の状態で始まります。`s` を押すと、この既定の選択に戻ります。

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

カテゴリには `procs` も指定できます。実行中にそのキャッシュを書き戻してしまうアプリのプロセス名です（`"procs": ["Google Chrome", "Code"]`）。動いているアプリのキャッシュを消しても容量はすぐ戻ってしまうので、`cdm` は確認を求める前に、開いているものを挙げます。名前は `pgrep -x` と完全に一致する必要があります。

いくつかのカテゴリは `kind` を持ち、何を候補にするかをスクリプトが判断します: `android-images`（どの AVD も起動しないシステムイメージ）、`android-idle-images`（`idleDays` の間起動されていない AVD だけが使うイメージ）、`older-versions`（各 glob がバージョンの一群で、最新版以外）、`rust-toolchains`（既定と stable 以外のツールチェーン）、`claude-transcripts`（`idleDays` の間触れていないセッション。必ずゴミ箱へ）。これらは glob を `paths` ではなく `images` か `candidates` から読むので、その kind を知らない古い `cdm` は何も候補にしません。

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
