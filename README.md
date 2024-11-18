# Что это?
Это адаптер для запуска популрных конфигов обхода замедления ютуба [Zapret Discord Youtube Flowseal](https://github.com/Flowseal/zapret-discord-youtube)
Был написан за пару вечеров без желания думать. Задача была сделать скрипт Plug-And-Play.

ПРОВЕРЕНО НА UBUNTU24.04 nftables

# Как запустить

```bash
git clone git@github.com:Sergeydigl3/zapret-discord-youtube-linux.git
cd zapret-discord-youtube-linux
sudo chmod +x nfqws
sudo bash main_script.sh
```
1. Скрипт спросит у вас нужно ли обновление (первый раз нужно нажать да). Потом необязательно
2. Потом попросит выбрать стратегию
3. Потом попросит выбрать интерфейс

Эти вопросы можно сохранить в файле `conf.env` 
и потом делать быстрый старт `sudo bash main_script.sh -nointeractive`.
Можно включить отладку парсинга флагом `-debug`

Если вы хотите auto_update каждый раз, то ставите auto_update="true".
```bash
strategy=./general.bat
auto_update=n
interface=enp0s3
```

Как посмотреть список всех интерфейсов:
```bash
ls /sys/class/net
```

# Важно
- Скрипт работает только с nftables.
- Если остановите скрипт. Правила фаервола почистятся. И фоновый процес nfqws остановится.
- Если у вас прописаны кастомные рулы. В nftables забэкапьте их. Так как я писав этот скрипт. Первый раз с ними работал и не особо вникал.

# Автозагрузка
Заполните конфиг conf.env и запустите скрипт:
```bash
sudo bash service.sh
```
Просмотреть статус сервиса тут:
```bash
systemctl status zapret_discord_youtube.service
```

- Значения в стратегия при автозагрузке берется из конфига.

# Совет
- Не включайте автоапгрейд. Так как если потом как-то сильно изменится репозиторий [основной](https://github.com/Flowseal/zapret-discord-youtube). Все может поломаться из-за костыльного частично кода парсинга)

# Поддержка
- Если есть идеи по улучшению. Делайте МР и посмотрим. (к примеру добавить тот-же iptables).
- Если что-то не работает не стоит писать мне в лички и почты. Написать в issues, и надейтесь, что другие юзеры или я вам смогут помочь
