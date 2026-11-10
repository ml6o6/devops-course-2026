# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

VirtualBox 7.2.22, Ubuntu Server 24.04 LTS, 2 vCPU, 2048 МБ ОЗУ, динамический диск 25 ГБ. Исходная точка — `01-clean-install` с пользователем `student` и установленным OpenSSH. Исходный профиль содержит 2 vCPU. Для воспроизводимого запуска после зависания VirtualBox на этом хосте рабочий профиль использует 1 vCPU.

## 2. Сетевые интерфейсы

| Интерфейс | Режим | IPv4 | Назначение |
| --- | --- | --- | --- |
| `enp0s3` | NAT | `10.0.2.15/24` | Исходящий доступ, включая APT |
| `enp0s8` | Host-only | `192.168.56.101/24` | Доступ хоста к ВМ |

Проверьте текущий адрес Host-only командой `ip -brief -4 address`. В хостовой среде Ubuntu WSL 1 добавьте в `/etc/hosts` строку `192.168.56.101 devops.local` по фактическому адресу. Если WSL генерирует файл заново, установите `generateHosts=false` в секции `[network]` файла `/etc/wsl.conf` перед изменением.

## 3. Правило проброса портов

В адаптере NAT правило `ssh` использует TCP и адрес хоста `127.0.0.1:2222`. После отката гостевой порт равен `22`. Меняйте его на `2222` после проверки нового слушающего порта через Host-only, оставляя старое SSH-соединение открытым.

## 4. Учётные записи

В консоли ВМ при необходимости запустите `sudo systemctl enable --now ssh.socket` и сверьте отпечаток `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` с отпечатком SSH-клиента. Подключитесь `ssh -p 2222 student@127.0.0.1`. Создайте `sudo adduser devops` и `sudo usermod -aG sudo devops`.

На хосте используйте отдельный `~/.ssh/devops_vm`, созданный `ssh-keygen -t ed25519 -C devops-vm-key -f ~/.ssh/devops_vm`. После отката повторно загрузите существующий открытый ключ командой `ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1`. Каталог `~/.ssh` на сервере должен иметь права `700`, файл `authorized_keys` — `600`, владелец `devops`.

```sshconfig
Host devops devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops
    HostName 127.0.0.1
```

Проверьте `ssh -o BatchMode=yes devops`. Отдельно проверьте, что `groups devops` включает `sudo`.

## 5. Служба SSH

Сохраните `sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup`. Разместите в `/etc/ssh/sshd_config.d/99-hardening.conf` следующие директивы.

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Закомментируйте конфликтующее `PasswordAuthentication yes` в раннем файле из `/etc/ssh/sshd_config.d/`, если оно найдено. Проверьте `sudo sshd -t` и `sudo sshd -T`. Выполните `sudo systemctl disable --now ssh.socket`, `sudo systemctl enable --now ssh.service`, `sudo systemctl restart ssh`. Проверьте `sudo ss -tlnp | grep sshd`, смените гостевой порт правила NAT и откройте новую сессию `ssh devops`. Затем проверьте отказ для `root` и входа с `-o PubkeyAuthentication=no`.

На ВМ команда `sudo hostnamectl set-hostname devops-vm` устанавливает короткое имя. Строка `127.0.1.1 devops-vm.devops.local devops-vm` в `/etc/hosts` задаёт FQDN. Проверьте `hostname -f`.

## 6. Правила межсетевого экрана

Задайте политики `sudo ufw default deny incoming` и `sudo ufw default allow outgoing`. До активации добавьте `sudo ufw allow 2222/tcp`, `sudo ufw allow 80/tcp`, `sudo ufw allow 443/tcp`. После `sudo ufw --force enable` проверьте новый SSH-вход. Затем установите `sudo ufw limit 2222/tcp` и `sudo ufw logging medium`. В `sudo ufw status verbose` должны остаться `2222/tcp LIMIT`, `80/tcp ALLOW`, `443/tcp ALLOW`.

Скопируйте `scripts/audit.sh` на ВМ и выполните `bash audit.sh` от имени `devops`. Нормальная конфигурация должна давать код `0`.

## 7. Снимки состояния

- `01-clean-install` — Ubuntu Server с OpenSSH и двумя сетевыми адаптерами.
- `02-keys-configured` — отдельный `devops`, вход по ключу, исходные параметры SSH.
- `03-ssh-hardened` — SSH на порту 2222 после проверки входа по ключу и отказов.


## 8. Веб-сервер

Установите `nginx` и `rsync` из репозитория Ubuntu. Служба `nginx.service` включена и запускается автоматически. Ресурс `devops.local` определён в `/etc/nginx/sites-available/devops-site`, включён одноимённой ссылкой в `sites-enabled`; стандартная ссылка `default` отключена.

Каталог `/var/www/devops-site` принадлежит `devops:devops`, права каталога `755`, файлов `644`. Рабочие процессы `www-data` читают файлы. Для `/404.html` используется `error_page 404 /404.html`. Журналы: `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log`.

Для порта 80 используйте `return 301 https://$host$request_uri;`. Для порта 443 задайте `ssl_protocols TLSv1.2 TLSv1.3;` и укажите сертификат `/etc/ssl/certs/devops.crt` (root, `644`) и ключ `/etc/ssl/private/devops.key` (root, `600`).

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj /CN=devops.local -addext subjectAltName=DNS:devops.local
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
sudo nginx -t && sudo systemctl reload nginx
```

На хосте передайте открытый сертификат через SSH: `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`. Проверьте `curl --cacert ~/devops.crt -I https://devops.local/`. Из чистого рабочего дерева запустите `bash scripts/deploy.sh --dry-run`, затем `bash scripts/deploy.sh`.


## 9. Контейнеризация

Версии: Docker version 29.9.3, build 5457199; Docker Compose version v5.7.0. Установлены пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` и `docker-compose-plugin` из официального APT-репозитория `https://download.docker.com/linux/ubuntu`. Открытый ключ хранится в `/etc/apt/keyrings/docker.asc`, описание источника — в `/etc/apt/sources.list.d/docker.sources`. Служба Docker включена. Пользователь `devops` состоит в группе `docker`, дающей полномочия, эквивалентные root.

Доставьте каталог проекта из корня репозитория командой `rsync -avz --delete --exclude=.env app/ devops:app/`. Проект находится в `/home/devops/app`. В этом каталоге создайте `.env` из `.env.example`, ограничьте права до `600` и замените заглушку `POSTGRES_PASSWORD` случайным значением `openssl rand -hex 16`. Рабочий файл хранится только на ВМ.

Запуск: `docker compose up -d --build --wait`. Образ `devops-app:1.0` запускает Gunicorn как пользователь `app`. PostgreSQL `postgres:16-alpine` находится в сети `app_backend` под именем `db`, использует том `app_db_data` и не публикует порт 5432. Приложение публикуется как `127.0.0.1:5000:5000`. `docker compose down` сохраняет том, а `down -v` удаляет его.

В HTTPS-блоке Nginx добавьте `location /app/` с `proxy_pass http://127.0.0.1:5000/;` и заголовками `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`. После `nginx -t` примените конфигурацию через `systemctl reload nginx`. Проверьте `https://devops.local/`, `https://devops.local/app/` и `https://devops.local/app/health` с доверенным сертификатом.
