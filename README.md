# Ringtone Switcher - Vencord auto-update installer

Установщик Vencord с плагином **RingtoneSwitcher**. Он собирает Vencord из
исходников, устанавливает плагин и внедряет Vencord в Discord.

## Что умеет плагин

- меняет рингтон входящего звонка Discord;
- содержит Classic, Halloween и Christmas рингтоны прошлых лет;
- позволяет добавлять собственные аудиофайлы;
- позволяет переключаться между несколькими пользовательскими рингтонами;
- имеет предварительное прослушивание и удаление пользовательских файлов;
- сохраняет пользовательские звуки локально на текущем устройстве;
- меняет только звук `call_ringing`, не затрагивая остальные звуки Discord.

## Установщик

Комплект сделан по схеме auto-update installer:

```text
Ringtone-Switcher-Vencord/
├── INSTALL-autoupdate.cmd       # первая установка
├── UPDATE.cmd                   # обновление Vencord и плагина
├── UNINSTALL.cmd                # восстановление Discord и удаление
├── install-autoupdate.ps1
├── update.ps1
├── uninstall.ps1
├── installer-common.ps1         # общие функции установщика
└── plugin/
    ├── index.tsx
    └── ringtones.ts
```

Установщик хранит или переиспользует клон Vencord в:

```text
%LOCALAPPDATA%\OrionVencord
```

Если `OrionVencord` уже существует, он используется повторно. Это сохраняет
уже установленные userplugins, включая Orion Quests и Quest UI. Если такого
клона нет, создаётся `%LOCALAPPDATA%\RingtoneSwitcherVencord`.

## Установка Windows

1. Скачай или клонируй весь репозиторий.
2. Не отделяй файлы друг от друга: папка `plugin` должна находиться рядом
   с `INSTALL-autoupdate.cmd`.
3. Закрой Discord.
4. Запусти `INSTALL-autoupdate.cmd` двойным щелчком.
5. Дождись завершения установки и сборки.
6. В Discord открой **Settings → Vencord → Plugins**.
7. Включи **RingtoneSwitcher**.

Установка может занять несколько минут, потому что скачиваются исходники
Vencord, зависимости и выполняется сборка.

Требования:

- Windows;
- Git;
- Node.js 22 или новее;
- рабочее интернет-соединение;
- установленный Discord Stable, Canary или PTB.

Если установлено несколько вариантов Discord, установщик попросит указать
вариант. Можно передать его сразу:

```powershell
.\INSTALL-autoupdate.cmd -DiscordBranch stable
.\INSTALL-autoupdate.cmd -DiscordBranch canary
.\INSTALL-autoupdate.cmd -DiscordBranch ptb
```

Чтобы собрать Vencord, но не внедрять его в Discord:

```powershell
.\INSTALL-autoupdate.cmd -SkipInject
```

## Обновление

После обновления исходников Vencord или плагина запусти:

```text
UPDATE.cmd
```

Скрипт обновит клон Vencord через Git, обновит исходники плагина, установит
зависимости, пересоберёт Vencord и перезапустит Discord, если он был запущен.

Чтобы не перезапускать Discord автоматически:

```powershell
.\UPDATE.cmd -SkipRestart
```

## Удаление

1. Запусти `UNINSTALL.cmd`.
2. Скрипт закроет Discord.
3. Удалит только `ringtoneSwitcher`.
4. Пересоберёт Vencord и повторно внедрит его в Discord.
5. Discord будет запущен снова, если он был запущен до удаления.

Другие userplugins, например `orionQuests` и `QuestUI`, не удаляются и
остаются в сборке.

После удаления Vencord остаётся установленным, потому что он может содержать
другие плагины. Не удаляй папку установки вручную, если продолжаешь
использовать Orion или другие userplugins:

```text
%LOCALAPPDATA%\OrionVencord
```

Если используется существующий `OrionVencord`, не удаляй его: в нём могут
находиться другие плагины. Node.js и Git установщик не удаляет.

## Ручная установка плагина

Если нужен только исходник плагина без автоматического установщика, скопируй
`plugin/index.tsx` и `plugin/ringtones.ts` в:

```text
Vencord/src/userplugins/ringtoneSwitcher/
```

Затем в папке Vencord выполни:

```sh
pnpm install
pnpm build
pnpm inject
```

## Важные замечания

- Discord должен быть закрыт во время внедрения и удаления.
- Не удаляй `%LOCALAPPDATA%\OrionVencord` или
  `%LOCALAPPDATA%\RingtoneSwitcherVencord`, пока Vencord внедрён в Discord.
  Сначала запусти `UNINSTALL.cmd`.
- При ошибке сборки установщик не должен оставлять непроверенную новую сборку.
- Если Discord не запускается после неудачного обновления, используй
  официальный установщик Vencord и выбери Repair.
- Плагин зависит от внутреннего модуля Discord `WebAudioSound.ensureAudio`.
  После крупных обновлений Discord может потребоваться обновление плагина.

## Лицензия

Vencord распространяется по лицензии GPL-3.0-or-later. Плагин предназначен
для использования как пользовательский плагин Vencord.
