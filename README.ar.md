# CleanDevMac

[English](README.md) | العربية | [Español](README.es.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

[![Downloads](https://img.shields.io/github/downloads/cleandevmac/cdm/total?style=flat-square&label=downloads&color=1f6feb)](https://github.com/cleandevmac/cdm/releases)
[![Latest release](https://img.shields.io/github/v/release/cleandevmac/cdm?style=flat-square&label=release&color=2da44e)](https://github.com/cleandevmac/cdm/releases/latest)
[![Stars](https://img.shields.io/github/stars/cleandevmac/cdm?style=flat-square&label=stars&color=d29922)](https://github.com/cleandevmac/cdm/stargazers)
[![License](https://img.shields.io/github/license/cleandevmac/cdm?style=flat-square&label=license&color=8957e5)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-111111?style=flat-square)](https://github.com/cleandevmac/cdm)
[![Donate](https://img.shields.io/badge/donate-PayPal-00457C?style=flat-square&logo=paypal&logoColor=white)](https://www.paypal.com/paypalme/hoangnc)

<div dir="rtl">

**CleanDevMac** — أو `cdm` في سطر الأوامر — هو واجهة طرفية تعثر على ذواكر التخزين المؤقت الخاصة بالتطوير، ومخرجات البناء، وبقايا بيانات التطبيقات التي تلتهم مساحة قرصك، وتعرض لك بالضبط ما هي وما حجمها، ثم تحذف ما تؤشّر عليه أنت فقط.

يَعُدّ شارة التنزيلات عدد مرات جلب ملف الإصدار `cdm`. كل أمر `curl` بالأسفل يصل إلى ذلك الملف، لذا فهو العدّاد الحقيقي لاستخدام هذه الأداة.

الموقع: **<https://cleandevmac.github.io>**

يعمل على macOS فقط. مكتوب بلغة bash خالصة، دون أي اعتماديات. بلا أي تتبّع — الاتصال الشبكي الوحيد الذي يجريه `cdm` هو جلب ملف قواعده بصيغة JSON.

## التشغيل

</div>

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash
```

<div dir="rtl">

لا توجد خطوة تثبيت. يعمل السكربت مباشرة من الأنبوب (pipe)، ويفحص نظامك، ثم يسلّمك الواجهة. وحين ينتهي، لا يترك أي أثر منه على جهاز Mac الخاص بك.

جرّب التشغيل التجريبي أولًا — يفحص ويُبلغ، ولا يحذف شيئًا:

</div>

```bash
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm | bash -s -- -n
```

<div dir="rtl">

## الاحتفاظ به (اختياري)

لا تفعل هذا إلا إذا أردت تشغيل `cdm` مجددًا دون الحاجة إلى الرابط. وهو الشيء الوحيد هنا الذي يترك ملفًا خلفه:

</div>

```bash
mkdir -p ~/.local/bin
curl -sSL https://github.com/cleandevmac/cdm/releases/latest/download/cdm -o ~/.local/bin/cdm
chmod +x ~/.local/bin/cdm
cdm
```

<div dir="rtl">

تأكّد من أن `~/.local/bin` موجود في `PATH` لديك (بإضافة `export PATH="$HOME/.local/bin:$PATH"` إلى ملف تهيئة الصدفة). أعِد تنفيذ سطر `curl -o` للتحديث. ولإلغاء التثبيت: `rm ~/.local/bin/cdm`.

![CleanDevMac](screenshot.png)

## ما الذي ينظّفه

**1. ذواكر التطوير المؤقتة ومخرجات البناء** — مجلدا DerivedData و DeviceSupport في Xcode، وذاكرة بناء ووحدات Go، و npm/npx/pnpm/yarn، وأدوات بناء JavaScript‏ (Turbo و Vite و webpack و Parcel و ESLint)، و Gradle، و Maven، و sbt/Ivy، و Cargo، و Python‏ (pip و uv و poetry و ruff و mypy)، و Ruby/Bundler، و Bun، و Deno، و CocoaPods، و SwiftPM، و Composer، و Bazel، و Zig، وأدوات السحابة‏ (kubectl و AWS و gcloud و Azure)، و Docker buildx، و JetBrains، و Playwright، وذاكرة تنزيلات Homebrew.

**2. ذواكر Electron والمتصفحات والتطبيقات** — ‏VS Code و Claude و Slack؛ و Chrome و Brave و Edge و Vivaldi و Arc تُفحص لكل ملف تعريف متصفح على حدة؛ و Firefox؛ وذواكر حِزم تقارير الأعطال والتتبّع‏ (Sentry و Crashlytics و Sparkle).

**3. مخلّفات المشاريع، مجمّعة حسب المستودع** — ‏`node_modules` و `dist` و `build` و `target` و `__pycache__`، والملفات التي يتجاهلها git. معطّلة افتراضيًا؛ مرّر `-p` لتفعيلها. أما في التشغيل التفاعلي فتُعرض عليك بعد انتهاء فحص الذواكر.

**4. Docker / Podman** — أمر `system prune -af`، ولا يُنفَّذ إلا باختيارك. لا تُمسّ وحدات التخزين المُسمّاة إطلاقًا.

**5. بيانات التطبيقات المهجورة** — مجلدات Application Support و Caches و Preferences العائدة لتطبيقات لم تعد مثبّتة.

## الأمان

- **لا يُحذف أي شيء دون تأكيد مفصّل بندًا بندًا.** ترى الخطة والأحجام، ثم تكتب `y`.
- **الذواكر المؤقتة تُحذف نهائيًا** — فهي تُنشأ من جديد مع أول عملية بناء تالية.
- **بيانات التطبيقات المهجورة والملفات التي يتجاهلها git تُنقل إلى سلة المهملات**، أي يمكن استرجاعها.
- **لا تُمسّ أبدًا مهما قالت القواعد:** `~/Documents` و `~/Desktop` و `~/Downloads` و `~/Pictures` و `~/.ssh` و iCloud Drive. هذه الحماية تقع أسفل محرك القواعد — فلا تستطيع أي قاعدة تجاوزها.
- **صناديق التطبيقات المعزولة والبيانات المملوكة لـ Apple أو للنظام لا تُمسّ إطلاقًا.**
- تُقرأ قائمة التطبيقات المثبّتة من **LaunchServices**، لذا لا تُصنَّف ملفات prefPane والإضافات وغيرها من الحزم غير `.app` خطأً على أنها مهجورة.
- الخيار `--dry-run` لا يحذف شيئًا.
- كل تشغيل يُسجَّل في `~/.cleandevmac/clean.log`.

## مفاتيح الواجهة

| المفتاح | الإجراء |
| --- | --- |
| `↑` / `↓`، `k` / `j` | التنقّل |
| `Space` | تبديل تأشير العنصر المحدد |
| `a` / `s` / `n` | تحديد الكل / الإعدادات الآمنة الافتراضية / إلغاء التحديد |
| `Enter` (أو `d`) | عرض المسارات والأحجام الدقيقة وراء العنصر |
| `c` | التنظيف — يبني خطة مفصّلة، تؤكّدها بـ `y` |
| `q` (أو `Esc`) | الخروج |

تُرتَّب العناصر من الأكبر إلى الأصغر. الذواكر الآمنة التي يُعاد إنشاؤها تلقائيًا تكون مؤشَّرة مسبقًا؛ أما مستودع Maven، ومتصفحات Playwright، وسجلات الأعطال، ومجلدات المشاريع، وبيانات التطبيقات المهجورة فتبدأ جميعها دون تأشير — والمفتاح `s` يعيد الضبط إلى هذا التحديد الافتراضي.

## قواعد قابلة للتحرير

الأهداف موجودة بصيغة JSON داخل `rules/`، لا في الشيفرة. أضِف المسارات أو احذفها بتحرير هذه الملفات:

| الملف | المحتوى |
| --- | --- |
| `index.json` | البيان — أي ملفات القواعد تُحمَّل، وبأي ترتيب |
| `dev-caches.json` | ذواكر التطوير المؤقتة ومخرجات البناء |
| `app-caches.json` | ذواكر Electron والمتصفحات والتطبيقات |
| `containers.json` | Docker / Podman |
| `project-junk.json` | مخلّفات المشاريع لكل مستودع |
| `orphans.json` | كشف بيانات التطبيقات المهجورة |

كل فئة هي كائن يحتوي على `icon` و `name` و `desc` و `paths` و `default` (مؤشَّرة مسبقًا أم لا) و `method` (‏`rm` للحذف، و `trash` للنقل إلى سلة المهملات). ووجّه `cdm` إلى مجموعتك الخاصة عبر `--patterns <مجلد-أو-رابط>`.

## الخيارات

| الخيار | الأثر |
| --- | --- |
| `-n`, `--dry-run` | يفحص ويُبلغ؛ ولا يحذف شيئًا |
| `-y`, `--yes` | وضع غير تفاعلي: ينظّف الذواكر الآمنة المؤشَّرة مسبقًا ثم يخرج. لا يمسّ مجلدات المشاريع ولا بيانات التطبيقات المهجورة ولا سلة المهملات |
| `-p`, `--projects` | يفحص أيضًا مستودعات الشيفرة بحثًا عن مخلّفات المشاريع |
| `--patterns SRC` | يحمّل القواعد من مجلد محلي أو من رابط أساسي |
| `--no-color` | يعطّل ألوان ANSI |
| `-h`, `--help` | طريقة الاستخدام |

## متغيرات البيئة

| المتغير | الأثر |
| --- | --- |
| `CDM_REMOTE` | الرابط الأساسي الذي تُجلب منه القواعد عند عدم العثور على نسخة محلية |
| `CDM_PATTERNS` | مصدر القواعد — مجلد محلي أو رابط أساسي (مثل `--patterns`) |

## الدعم

‏cdm أداة مجانية برخصة MIT، وستبقى كذلك — بلا نسخة مدفوعة، وبلا تتبّع، وبلا أي شيء محجوب. فإن أعادت إليك مساحة قرصك ورغبت في دعوتي إلى فنجان قهوة:

**[paypal.me/hoangnc](https://www.paypal.com/paypalme/hoangnc)**

ومنح المستودع نجمة أو إخبار مطوّر آخر عنه يساعد بالقدر نفسه.

## شكر وتقدير

جرت مراجعة بعض مواقع الذواكر المؤقتة بمقارنتها بأدوات تنظيف macOS مفتوحة المصدر أخرى:

- [PureMac](https://github.com/momenbasel/PureMac) — MIT
- [mac-cleaner-cli](https://github.com/guhcostan/mac-cleaner-cli) — MIT
- [mac-cleanup-go](https://github.com/2ykwang/mac-cleanup-go) — MIT
- [mac-cleanup-py](https://github.com/mac-cleanup/mac-cleanup-py) — Apache-2.0

أما القواعد هنا فقد كُتبت بشكل مستقل لمخطط هذه الأداة نفسها، وجرى التحقق من كل مسار قبل إضافته.

## الرخصة

MIT — انظر [LICENSE](LICENSE).

</div>
