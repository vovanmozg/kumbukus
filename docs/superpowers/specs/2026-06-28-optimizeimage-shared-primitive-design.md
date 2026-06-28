# Выделение оптимизации картинок в общий примитив `optimizeimage.sh`

## Проблема

Логика локальной оптимизации картинок (mozjpeg для jpeg; pngquant-если-без-потерь + oxipng для
png) живёт в **двух** скриптах — `tinifyimage.sh` (`compress_local` + `detect_format`) и
`compresspdf.sh` (`optimize_image`). Копии уже разошлись за одну сессию: `compresspdf.sh`
починил баг `identify '%k %z'` (`read` падает на EOF), а `tinifyimage.sh` его всё ещё несёт.
Классический дрейф из-за нарушения DRY, с латентным багом в одной из копий.

## Цель и подход

Ввести третий скрипт `optimizeimage.sh`, который владеет всей логикой оптимизации (offline +
online Tinify), с интерфейсом `SRC DST` и без знания про папку `optimized/`. `tinifyimage.sh` и
`compresspdf.sh` становятся тонкими вызывающими; дублирующийся код оптимизации исчезает.

**`optimizeimage.sh` создаётся копированием `tinifyimage.sh`, а не переписыванием.** Авторитетный
источник логики оптимизации/метаданных/online — сам файл `apps/tinifyimage.sh`; этот спек НЕ
переописывает его внутренности, а фиксирует только дельту и решения. См. «Дельта».

## Решения (из brainstorming)

- **optimizeimage владеет обоими режимами** — offline (mozjpeg/pngquant/oxipng) и online (Tinify
  `--online`). У `tinifyimage.sh` своей логики оптимизации не остаётся.
- **Ресайз остаётся в `compresspdf.sh`** — optimizeimage чистый примитив «оптимизируй картинку»,
  про `--width` не знает. compresspdf сам делает `mogrify -resize`, потом зовёт optimizeimage.
- **Только прямые vendor-зависимости.** optimizeimage несёт требования
  mozjpeg/pngquant/oxipng/imagemagick/curl/exiftool; compresspdf — свои прямые (poppler-utils,
  imagemagick); у tinifyimage своего vendor-инструмента нет. Зависимость от соседнего
  `optimizeimage` фиксируется **обычным комментарием** `# depends on: optimizeimage.sh`, не
  строкой `# requirement:`.
- **Тулинг установки откладываем.** `installapps`/`requirements.sh` понимают только
  `# requirement: vendor/<dep>`; установка соседних скриптов — отдельный тикет позже. Пока
  установка обёрток требует ручной установки `optimizeimage.sh` — задокументированное
  ограничение.

## Источник правды

Репозиторий `~/pro/kumbukus`. Новый `apps/optimizeimage.sh` → ставится в `~/bin`. Изменяются
`apps/tinifyimage.sh`, `apps/compresspdf.sh`. Изменений в `config.json`/меню нет (меню зовёт
`tinifyimage.sh %f`, `tinifyimage.sh %f --no-metadata`, `compresspdf.sh %f`,
`compresspdf.sh %f --width=1000`).

## Карта компонентов

```
                    optimizeimage.sh        (offline local + online Tinify; SRC DST)
                   /                \
   tinifyimage.sh (обёртка optimized/)   compresspdf.sh (pdfimages → resize → optimize → сборка)
```

## Дельта: `optimizeimage.sh` = копия `tinifyimage.sh` со следующими изменениями

Берётся `apps/tinifyimage.sh` целиком (`compress_local`, `compress_online`, `restore_metadata`,
`detect_format`, `require`, `usage`, разбор флагов, диспетч) **дословно**, и применяются ровно
эти изменения:

1. **Интерфейс `SRC DST`.** Вместо одного позиционного аргумента — два: исходный `SRC` и
   выходной `DST`. Целевой файл записи — `DST` вместо `OPTIMIZED_DIR/basename`.
2. **Убрать логику `optimized/`.** Удалить вычисление `OPTIMIZED_DIR`/`OPTIMIZED_FILE` и
   `mkdir -p`. Каталог `DST` обязан существовать заранее (забота вызывающего); optimizeimage
   каталоги не создаёт. Везде, где код писал в `OPTIMIZED_FILE`, теперь пишет в `DST` (включая
   `${DST}.work.tmp` для атомарной замены — это даёт поддержку in-place, когда `SRC==DST`).
3. **Багфикс** `identify -format '%k %z'` → `'%k %z\n'` (перевод строки, чтобы `read` не падал
   на EOF).
4. **Выкинуть мёртвый алиас `--local`** (был синонимом `--offline`, который и так дефолт; нигде
   не используется).
5. **usage** обновить под `SRC DST` и без `--local`.
6. **Заголовки `# requirement:`** — оставить только инструменты оптимизации:
   `curl, exiftool, mozjpeg, pngquant, oxipng, imagemagick`.

Итоговый интерфейс: `optimizeimage.sh [--online|--offline] [--no-metadata] [-q N] [-h|--help]
SRC DST`. Режим по умолчанию `--offline`.

**Важно — копировать дословно, НЕ «прибираясь»:** вся семантика метаданных (offline jpeg при
`--no-metadata` хранит только `Orientation`; png — ничего; online принудительно
`Orientation=Horizontal`), сообщения вывода (`(local)`/`(online)` + `-X%`), `require()`-проверки
и **рудименты** (`METADATA_FILE`, `OPTIMIZED_FILE_PROGRESS` — создаются/удаляются, но для
восстановления не используются) переносятся как есть. «Улучшение» этих кусков изменило бы
поведение и здесь запрещено. Единственные намеренные изменения поведения — пункты 3 и 4 выше.

## `tinifyimage.sh` → тонкая обёртка

- Сохраняет тот же CLI (минус `--local`): `[--online|--offline] [--no-metadata] [-q N]
  [-h|--help] FILE`. Меню не затронуто.
- Считает `DST="$(dirname SRC)/optimized/$(basename SRC)"`, `mkdir -p` папки, делегирует с
  пробросом всех флагов: `optimizeimage <флаги> "$SRC" "$DST"`.
- Удаляет весь перенесённый код (`compress_local`, `compress_online`, `restore_metadata`,
  `detect_format`, `require`).
- Комментарий `# depends on: optimizeimage.sh`.

## `compresspdf.sh` → убирает inline-оптимизатор

- Удаляет функцию `optimize_image()`.
- В цикле по страницам: сохраняет `mogrify -resize "${WIDTH}x>"` при `--width`, затем зовёт
  `optimizeimage --offline --no-metadata "$img" "$img" >/dev/null` (in-place; метаданные для
  промежуточных картинок не нужны; stdout подавлен).
- **Не трогаются:** разбор `--width`, `-*`→exit 1, «No such file»→exit 1, `pdfimages -all`,
  «No images found»→exit 0, `mkdir -p optimized`, `convert "$TEMP_DIR"/img*` сборка, сообщение
  «Compression finished: <pdf>».
- `# requirement:` — только `poppler-utils`, `imagemagick`; комментарий
  `# depends on: optimizeimage.sh`.

## Сохранность поведения (проверено по текущим скриптам)

- **jpg/png PDF в compresspdf** — идентичный результат (та же связка mozjpeg/pngquant/oxipng,
  теперь через optimizeimage).
- **не-jpg/png PDF (CCITT/JBIG2/CMYK-как-ppm)** — *эмпирически текущий скрипт уже падает*:
  `pdfimages -all` выдаёт файл не-jpg/png (+ сайдкар `.params`), и финальный `convert` без
  декодера для CCITT/PARAMS выходит 1 без результата. Рефактор воспроизводит ненулевой выход на
  тех же входах (optimizeimage выходит 1 на неподдержанной странице раньше). Рабочая
  функциональность не теряется. Флаг `--skip-unsupported` рассматривался и **отклонён**: он не
  заставит такие PDF собраться (downstream `convert` всё равно не читает CCITT). Поддержка
  экзотических форматов — отдельное будущее улучшение, вне рамок.

## Обработка ошибок

- optimizeimage: SRC существует и файл; DST задан; unknown-опция → usage + exit 1; неподдержанный
  тип в offline → сообщение + exit 1 (как сейчас).
- Обёртки: если `optimizeimage` не установлен — «command not found» (exit 127). Дружелюбный guard
  не добавляем (установка отложена); ограничение задокументировано здесь.

## Вне рамок (YAGNI / отложено)

- Поддержка sibling-зависимостей в `installapps`/`requirements.sh` — отдельный тикет.
- `--width`/ресайз в optimizeimage.
- Online in-place (`SRC==DST` c `--online`).
- Переименование вокруг похожего `optimizeimagejpegoptim.sh` (оставляем как есть).

## Тестирование

Новый `tests/behavior/test_optimizeimage.sh` (через `tests/selftest/assert.sh`; нужны
imagemagick/mozjpeg/pngquant/oxipng/file):

1. **offline jpeg** → DST меньше SRC и валидный JPEG.
2. **offline png-палитра** (≤256 цветов, 8 бит) → DST валидный PNG, не больше SRC.
3. **offline png-фото** (>256 цветов) → DST валидный PNG (lossless-путь без ошибок).
4. **in-place** (`SRC==DST`) → файл оптимизирован на месте, валиден.
5. **SRC≠DST** → DST создан в существующем каталоге, SRC не тронут.
6. **неподдержанный тип** (`.txt`) в offline → exit 1.
7. **`--no-metadata` на jpeg** → DST валиден, тег `Orientation` сохранён, остальной EXIF сброшен.

Регрессия:
- `tests/behavior/test_compresspdf.sh` продолжает проходить (теперь через optimizeimage).
- Минимальный `test_tinifyimage.sh`: offline на сгенерированном jpeg → валидный `optimized/<name>`
  меньше исходного (обёртка работает end-to-end).

Не проверяем: не-jpg/png PDF продолжают падать в `compresspdf` как сегодня (это существующий сбой,
а не регрессия). Online (Tinify) автоматически не тестируется (нужны ключ и сеть).
