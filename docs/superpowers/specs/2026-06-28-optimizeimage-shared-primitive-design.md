# Выделение оптимизации картинок в общий примитив `optimizeimage.sh`

## Проблема

Логика локальной оптимизации картинок (mozjpeg для jpeg; pngquant-если-без-потерь + oxipng
для png) сейчас живёт в **двух** скриптах — `tinifyimage.sh` (`compress_local` +
`detect_format`) и `compresspdf.sh` (`optimize_image`). Копии уже разошлись за одну сессию:
`compresspdf.sh` починил баг `identify -format '%k %z'` (`read` падает на EOF), а
`tinifyimage.sh` его всё ещё несёт; плюс расхождения в правке на месте vs временная копия, в
`require()` и в `|| true`. Это классический дрейф из-за нарушения DRY, с латентным багом в одной
из копий.

## Цель

Ввести третий скрипт `optimizeimage.sh`, который владеет всей логикой оптимизации (локальный
offline **и** online Tinify), с простым интерфейсом `SRC DST` и без знания про папку
`optimized/`. `tinifyimage.sh` и `compresspdf.sh` становятся тонкими вызывающими. Дублирующийся
код оптимизации исчезает.

**Подход — не переписывание с нуля.** `optimizeimage.sh` создаётся копированием
`tinifyimage.sh` с четырьмя точечными изменениями (см. чеклист переноса ниже): (1) два
позиционных аргумента `SRC DST` вместо одного, (2) запись в `DST` вместо `optimized/<basename>`
и отказ от создания папки, (3) багфикс `identify '%k %z\n'`, (4) текст usage. Вся остальная
логика — включая рудиментарные куски — переносится **дословно**.

## Решения (из brainstorming)

- **optimizeimage владеет обоими режимами** — offline (mozjpeg/pngquant/oxipng) и online
  (Tinify `--online`). У `tinifyimage.sh` своей логики оптимизации не остаётся.
- **Ресайз остаётся в `compresspdf.sh`** — optimizeimage чистый примитив «оптимизируй картинку»
  и ничего не знает про `--width`. compresspdf сам делает `mogrify -resize`, потом зовёт
  optimizeimage.
- **Декларируем только прямые vendor-зависимости.** optimizeimage несёт требования
  mozjpeg/pngquant/oxipng/imagemagick/curl/exiftool; compresspdf держит свои прямые
  (poppler-utils, imagemagick); у tinifyimage своего vendor-инструмента нет. Зависимость от
  соседнего `optimizeimage` фиксируется **обычным комментарием**, а не строкой `# requirement:`.
- **Тулинг установки откладываем.** `installapps`/`requirements.sh` понимают только
  `# requirement: vendor/<dep>`; научить их ставить соседние скрипты — отдельный тикет позже.
  Пока установка обёрток требует ручной установки `optimizeimage.sh` — это задокументированное
  ограничение.

## Источник правды

Репозиторий `~/pro/kumbukus`. Новый скрипт `apps/optimizeimage.sh` → ставится в `~/bin`.
Изменяются: `apps/tinifyimage.sh`, `apps/compresspdf.sh`. Изменений в `config.json`/меню нет
(меню по-прежнему зовёт `tinifyimage.sh %f`, `tinifyimage.sh %f --no-metadata`,
`compresspdf.sh %f`, `compresspdf.sh %f --width=1000`).

## Карта компонентов

```
                    optimizeimage.sh        (offline local + online Tinify; SRC DST)
                   /                \
   tinifyimage.sh (обёртка optimized/)   compresspdf.sh (pdfimages → resize → optimize → сборка)
```

## 1. `apps/optimizeimage.sh` (новый)

**Интерфейс:** `optimizeimage.sh [--online|--offline|--local] [--no-metadata] [-q N] [-h|--help] SRC DST`
- Режим по умолчанию `--offline`. `--local` — принимаемый алиас `--offline` (сохранён из
  текущего `tinifyimage.sh`). `-h`/`--help` печатает usage и выходит 0.
- **Неподдержанный тип** (offline, вход не jpeg и не png): печатает сообщение и выходит 1 —
  поведение текущего `tinifyimage.sh`, сохраняется как есть. Почему это корректно и для
  `compresspdf.sh` — см. «Сохранность поведения».
- Пишет оптимизированную картинку в **DST** (не в `optimized/<basename>`). Каталог DST обязан
  уже существовать — optimizeimage каталоги не создаёт.
- **In-place поддерживается:** `SRC` может совпадать с `DST`. Реализация пишет во временный файл
  (`${DST}.work.tmp`), затем `mv -f` поверх DST — SRC читается полностью до замены. (Это
  поддержанный in-place путь для **offline**; online in-place вне рамок.)
- **Формат:** `file -b --mime-type` → jpeg/png, фолбэк по расширению.
- **offline jpeg:** `djpeg SRC | cjpeg -quality $JPEG_QUALITY -quant-table 3 -progressive -optimize`.
- **offline png:** если `%k`≤256 цветов и `%z`≤8 бит → `pngquant 256 --skip-if-larger --force`
  (если pngquant отказался — оставить оригинал), иначе только lossless; затем
  `oxipng -o4 --strip safe --alpha`.
- **online:** Tinify API (`source ~/.env`, `TINYPNG_API_KEY`, `curl … api.tinify.com`), запись в
  DST.
- **Константы:** `JPEG_QUALITY=75`, `OXIPNG_LEVEL=4`, `MOZJPEG_BIN=/opt/mozjpeg/bin`.
- **`require()`** (проверка наличия инструментов) сохраняется.
- **Отчёт в stdout:** те же строки, что печатает сейчас `tinifyimage.sh` — offline
  `Compression finished (local): <DST>  (o -> n bytes, -X%)`, online
  `Compression finished (online): <DST>` — чтобы stdout обёртки не изменился. Вызывающие могут
  перенаправлять.

**Метаданные — копировать дословно из текущего `tinifyimage.sh`, не пересказом:**
- `--no-metadata` false: восстановить все теги из SRC в DST
  (`exiftool -tagsfromfile SRC -all:all DST`); сохранить mtime (`touch -r SRC DST`).
- `--no-metadata` true: jpeg сохраняет **только** `Orientation`; png — **ничего**.
- online: после скачивания снять все теги, восстановить из SRC и принудительно
  `Orientation=Horizontal` (Tinify «запекает» поворот в пиксели) — ровно как в текущем
  `compress_online`.
- **Рудименты тоже копируются дословно:** `METADATA_FILE` (создаётся `exiftool -j SRC`, потом
  удаляется, но для восстановления НЕ используется) и `OPTIMIZED_FILE_PROGRESS` (touch/rm). План
  НЕ должен их «вычищать» — это изменило бы поведение. Просто переносим как есть, заменив базу
  пути на DST.

**Багфиксы при копировании:**
- `identify -format '%k %z\n'` (добавить перевод строки, чтобы `read` не падал на EOF — баг,
  который сейчас несёт `tinifyimage.sh`). Это **единственное** намеренное изменение поведения;
  всё остальное сохраняется эквивалентно байт-в-байт.

**Заголовки требований:**
```
# requirement: vendor/curl
# requirement: vendor/exiftool
# requirement: vendor/mozjpeg
# requirement: vendor/pngquant
# requirement: vendor/oxipng
# requirement: vendor/imagemagick
```

## Чеклист переноса логики `tinifyimage.sh` (ничего не теряем)

Каждый элемент текущего `tinifyimage.sh` и его судьба в `optimizeimage.sh`:

| Текущий элемент (tinifyimage.sh) | Судьба в optimizeimage.sh |
|---|---|
| Константы `JPEG_QUALITY/OXIPNG_LEVEL/MOZJPEG_BIN` (24–26) | копируются дословно |
| `usage()` (28–40) | копируется, текст обновлён под `SRC DST`/`--local`/`-h` |
| Разбор флагов `--online` (46–48) | копируется |
| `--offline` / `--local` (49) | копируется (алиас сохранён) |
| `--no-metadata` (50) | копируется |
| `-q\|--quality N` (51) | копируется |
| `-h\|--help` → usage exit 0 (52) | копируется |
| unknown `-*` → usage + exit 1 (53) | копируется |
| позиционный аргумент (54) | **изменено:** теперь ДВА — `SRC` и `DST` |
| пустой SOURCE → usage exit 1 (59–61) | копируется (для SRC) |
| не файл → exit 1 (62–64) | копируется (для SRC) |
| `OPTIMIZED_DIR`/`mkdir -p`/`OPTIMIZED_FILE` (66–69) | **удалено:** DST приходит снаружи, каталог не создаём |
| `compress_online`: `source ~/.env` (73) | копируется |
| online: METADATA_FILE/PROGRESS (75–81, 89, 99) | копируется дословно (рудименты тоже), база пути → DST |
| online: `curl … shrink` + парс Location (85–86) | копируется |
| online: `curl -L … --output` (93) | копируется, цель → DST |
| online: strip + restore + `Orientation=Horizontal` (96–99) | копируется |
| online: `touch -r` + сообщение `(online)` (102–103) | копируется, цель → DST |
| online: нет Location → error exit 1 (104–107) | копируется |
| `require()` (111–117) | копируется |
| `restore_metadata()` incl. png-без-Orientation-нюанс (119–126) | копируется |
| `detect_format()` (128–142) | копируется |
| `compress_local`: jpeg `djpeg\|cjpeg …` (151–157) | копируется, выход → DST |
| `compress_local`: png `identify %k %z` гейт + pngquant/cp + oxipng (159–174) | копируется + багфикс `\n` |
| `compress_local`: неподдержанный тип → exit 1 (176–179) | копируется |
| `touch -r` + `mv tmp → OPTIMIZED_FILE` (182–183) | копируется, цель → DST (поддержка SRC==DST) |
| отчёт `-X%` через awk (185–188) | копируется, цель → DST |
| диспетч `MODE online/offline` (191–195) | копируется |

Итог: единственные изменения — две строки про аргумент/DST и багфикс `\n`. Логика не теряется.

## 2. `apps/tinifyimage.sh` (становится тонкой обёрткой)

- Сохраняет **точно тот же** CLI, что и сейчас — `[--online|--offline|--local] [--no-metadata]
  [-q N] [-h|--help] FILE`, включая алиас `--local` и `-h`/usage — чтобы пункты меню
  (`tinifyimage.sh %f`, `tinifyimage.sh %f --no-metadata`) и любое использование из терминала
  работали без изменений.
- Считает `DST="$(dirname SRC)/optimized/$(basename SRC)"`, делает `mkdir -p` этой папки и
  делегирует, пробрасывая все свои флаги: `optimizeimage <те же флаги> "$SRC" "$DST"`.
- Удаляет весь код оптимизации/online (теперь в optimizeimage): `require()`, `detect_format`,
  `compress_local`, `compress_online`.
- Прямых vendor-зависимостей у себя нет; добавляется комментарий `# depends on: optimizeimage.sh`
  (не строка `# requirement:`).

## 3. `apps/compresspdf.sh` (убирает inline-оптимизатор)

- Удаляет функцию `optimize_image()`.
- В цикле по страницам: сохраняет `mogrify -resize "${WIDTH}x>"` при заданном `--width`, затем
  зовёт `optimizeimage --offline --no-metadata "$img" "$img" >/dev/null` (in-place; метаданные
  для промежуточных постраничных картинок бессмысленны; stdout подавлен, чтобы не печатать
  строку на каждую страницу).
- Сбои оптимизации на реальных jpg/png прерывают скрипт под `set -euo pipefail` ровно как сейчас
  делает inline `optimize_image()`. Про не-jpg/png страницы — см. «Сохранность поведения».
- Элементы, которые **не трогаются**: разбор `--width`, `-*` → exit 1, «No such file» → exit 1,
  `pdfimages -all`, «No images found» → exit 0, `mkdir -p optimized`, `convert "$TEMP_DIR"/img*`
  сборка, сообщение «Compression finished: <pdf>».
- Заголовки требований оставляют только прямые инструменты:
  ```
  # requirement: vendor/poppler-utils
  # requirement: vendor/imagemagick
  ```
  плюс комментарий `# depends on: optimizeimage.sh`.

## Сохранность поведения (проверено по текущим скриптам)

Всё текущее поведение сохраняется; единственное намеренное изменение — багфикс `identify`-`\n`.

- **CLI tinifyimage** — `--online`, `--offline`, алиас `--local`, `--no-metadata`,
  `-q/--quality N`, `-h/--help`/usage, ошибка+usage на unknown `-*`, exit 1 на отсутствующий/
  пустой файл — всё пробрасывается в optimizeimage. Меню не затронуто.
- **Метаданные** — offline jpeg хранит Orientation при `--no-metadata` и все теги иначе; offline
  png при `--no-metadata` не хранит ничего; online запекает `Orientation=Horizontal`. Копируется
  дословно.
- **Сообщения вывода** — `(local)`/`(online)` + `-X%` сохранены.
- **compresspdf на jpg/png PDF** — идентичный результат (optimizeimage гоняет ту же связку
  mozjpeg/pngquant/oxipng, что compresspdf делал inline).
- **compresspdf на не-jpg/png PDF (CCITT/JBIG2/CMYK-как-ppm и т.п.)** — *эмпирически текущий
  скрипт уже падает* на таких: `pdfimages -all` выдаёт файл не-jpg/png (плюс сайдкар `.params`),
  и финальный `convert "$TEMP_DIR"/img* …` не имеет декодера для CCITT/PARAMS — выходит 1 без
  пригодного результата. Рефактор воспроизводит ненулевой выход на тех же входах (optimizeimage
  выходит 1 на неподдержанной странице раньше). Никакая рабочая функциональность не теряется.
  Флаг `--skip-unsupported` (pass-through) рассматривался и **отклонён**: он не заставит такие
  PDF успешно собраться (downstream `convert` всё равно не читает CCITT), то есть добавляет
  поверхность, ничего не сохраняя и не починяя. Полноценная поддержка экзотических форматов
  страниц — отдельное будущее улучшение, явно вне рамок.

## Обработка ошибок

- optimizeimage проверяет: SRC существует и это файл; DST задан; unknown-опция → usage + exit 1;
  неподдержанный тип в offline → сообщение + exit 1 (как сейчас).
- Обёртки: если `optimizeimage` не установлен, вызов падает с «command not found» (exit 127).
  Дружелюбный guard сейчас НЕ добавляется (поддержка установки отложена); ограничение
  «нет соседнего скрипта» задокументировано в этом спеке.

## Вне рамок (YAGNI / отложено)

- Научить `installapps`/`requirements.sh` ставить sibling-зависимости — отдельный тикет.
- Добавление `--width`/ресайза в optimizeimage.
- Online in-place (`SRC==DST` c `--online`).
- Переименование вокруг уже существующего похожего `optimizeimagejpegoptim.sh` (оставляем как
  есть).

## Тестирование

Новый `tests/behavior/test_optimizeimage.sh` (использует `tests/selftest/assert.sh`; нужны
imagemagick/mozjpeg/pngquant/oxipng/file):

1. **offline jpeg** — сгенерированный jpeg → DST меньше SRC и валидный JPEG
   (`file --mime-type` = image/jpeg).
2. **offline png-палитра** (≤256 цветов, 8 бит) → DST существует, валидный PNG, не больше SRC.
3. **offline png-фото** (>256 цветов) → DST существует и валидный PNG (lossless-путь без ошибок).
4. **in-place** (`SRC==DST`) → файл оптимизирован на месте и остаётся валидным.
5. **SRC≠DST** → DST создан в существующем каталоге, SRC не тронут.
6. **неподдержанный тип** (например `.txt`) в offline → exit 1.
7. **`--no-metadata` на jpeg** → DST валидный, его тег `Orientation` сохранён, остальной EXIF
   сброшен (страхует нюанс метаданных).

Регрессия:
- `tests/behavior/test_compresspdf.sh` продолжает проходить (теперь гоняет optimizeimage через
  постраничный вызов) — включая jpeg/mozjpeg, png, `--width=600` и проверку отсутствия облака
  Tinify.
- Минимальный `test_tinifyimage.sh`: `tinifyimage.sh` (offline, по умолчанию) на сгенерированном
  jpeg создаёт валидный `optimized/<name>` меньше исходного — подтверждает, что обёртка работает
  end-to-end.

Не проверяем (это была бы проверка уже существующего сбоя, а не регрессии): не-jpg/png PDF
продолжают падать в `compresspdf` ровно как сегодня; ни один тест не делает вид, что они
проходят.

Online (Tinify) пути автоматически не тестируются (нужны ключ и сеть).
