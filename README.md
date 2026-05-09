# podkop-update

Скрипт автообновления списков доменов и подсетей для [podkop](https://github.com/itdoginfo/podkop) из репозитория [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains).

## Что делает

- Скачивает 12 актуальных `.lst` файлов из `allow-domains` (Russia, Discord, Twitter, Meta, Google AI, Roblox, Telegram — домены и IPv4-субнеты).
- Сравнивает с локальными копиями в `/etc/podkop/lists/`.
- Если что-то изменилось — атомарно подменяет файлы и делает `reload` подкопа (без обрыва туннелей и DHCP-передоговорок).
- Если ничего не изменилось — молча выходит.

Расчёт на запуск из cron раз в сутки.

## Особенности

- **Атомарная замена** через staging-файл `$dst.new` на той же FS → финальный `mv` это `rename(2)`.
- **Single-instance lock** через `flock` на `/tmp/podkop-updater.lock` — два cron-запуска не передерутся.
- **Sanity check** на скачанный файл — отсекает HTML-страницы (404 и т.п.) и пустые/мусорные ответы.
- **Graceful reload**, а не restart — `sing-box` не перезапускается, `nft` сеты обновляются на лету, интерфейс не передёргивается.
- **Не трогает flash, если контент не изменился** — `cmp` отрабатывает в tmpfs, до записи в `/etc/` дело не доходит.
- **Логирование** одновременно в syslog (`logread -e podkop-updater`) и stdout — удобно и для cron, и для ручной проверки.

## Требования

- OpenWrt (тестировалось на 23.05).
- [podkop](https://github.com/itdoginfo/podkop) уже установлен и работает.
- `wget` с поддержкой HTTPS — BusyBox stock wget не подходит, нужен `wget-ssl`:

```sh
opkg update
opkg install wget-ssl
```

`podkop` обычно тянет это сам как зависимость.

## Установка

**1. Положить скрипт:**

```sh
wget -O /usr/sbin/podkop-update.sh https://raw.githubusercontent.com/j3ngoos/podkop-local-list-updater/main/podkop-update.sh
chmod 755 /usr/sbin/podkop-update.sh
```

**2. Чтобы пережил `sysupgrade`:**

```sh
echo '/usr/sbin/podkop-update.sh' >> /etc/sysupgrade.conf
```

**3. Тестовый прогон вручную:**

```sh
/usr/sbin/podkop-update.sh
```

Первый запуск (если списков ещё нет): `UPDATED ...` × 12 + `podkop reloaded`.
Повторный: `all lists up to date`.

**4. Подключить списки в podkop через UI:**

В поле **Local Domain Lists** добавить:

```
/etc/podkop/lists/domains/russia_inside.lst
/etc/podkop/lists/domains/discord.lst
/etc/podkop/lists/domains/twitter.lst
/etc/podkop/lists/domains/meta.lst
/etc/podkop/lists/domains/google_ai.lst
/etc/podkop/lists/domains/roblox.lst
/etc/podkop/lists/domains/telegram.lst
```

В поле **Local Subnet Lists** добавить:

```
/etc/podkop/lists/subnets/discord.lst
/etc/podkop/lists/subnets/twitter.lst
/etc/podkop/lists/subnets/meta.lst
/etc/podkop/lists/subnets/roblox.lst
/etc/podkop/lists/subnets/telegram.lst
```

В разделе **Community Lists** снять **все** галочки ❌ — встроенные подборки полностью покрываются локальными списками; если оставить — получится дублирование правил.

**5. Cron** — например, раз в сутки в 04:17:

```sh
echo '17 4 * * * /usr/sbin/podkop-update.sh' >> /etc/crontabs/root
/etc/init.d/cron enable
/etc/init.d/cron restart
```

Проверка: `crontab -l`.

## Логи

```sh
logread -e podkop-updater          # история
logread -f -e podkop-updater       # follow в реальном времени
```

Пример успешного no-op:

```
podkop-updater: Checking for list updates...
podkop-updater: all lists up to date
```

Пример с обновлением:

```
podkop-updater: Checking for list updates...
podkop-updater: UPDATED domains/discord.lst
podkop-updater: 1 file(s) updated, 0 failed — reloading podkop
podkop-updater: podkop reloaded
```

## Откат

```sh
sed -i '/podkop-update.sh/d' /etc/crontabs/root
/etc/init.d/cron restart
rm -f /usr/sbin/podkop-update.sh /tmp/podkop-updater.lock
sed -i '\#/usr/sbin/podkop-update.sh#d' /etc/sysupgrade.conf
```

Списки в `/etc/podkop/lists/` останутся — podkop продолжит работать с последней успешной версией.

## Кастомизация

Список синкаемых файлов прописан явно в нижней части скрипта — добавить/убрать строки несложно:

```sh
sync_one "Services/discord.lst"  domains  discord.lst
#         ^путь в репо           ^папка   ^имя локально
```

Чтобы добавить, например, `youtube.lst`:

```sh
sync_one "Services/youtube.lst"  domains  youtube.lst
```

## Как это понимает «свежесть»

Никакой даты/версии/ETag — чисто **побайтовое сравнение** через `cmp -s`. «UPDATED» означает буквально «байты на GitHub отличаются от локальных». Откат upstream'ом на старую версию тоже триггернёт обновление. Для 12 мелких файлов раз в сутки этого с запасом достаточно.

## Лицензия

MIT — см. [LICENSE](LICENSE).

## Благодарности

- [itdoginfo/podkop](https://github.com/itdoginfo/podkop) — собственно сам подкоп.
- [itdoginfo/allow-domains](https://github.com/itdoginfo/allow-domains) — источник списков.
