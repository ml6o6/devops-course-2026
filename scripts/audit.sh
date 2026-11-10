#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C.UTF-8

PASS=0
FAIL=0

check() {
    local description=$1 expected=$2 actual=$3
    if [[ $actual == "$expected" ]]; then
        printf ' [OK] %s\n' "$description"
        ((PASS += 1))
    else
        printf " [FAIL] %s (ожидалось: '%s', получено: '%s')\n" "$description" "$expected" "$actual"
        ((FAIL += 1))
    fi
}

printf 'Аудит конфигурации: %s, %s\n' "$(hostname -f)" "$(date '+%F %T')"
echo '[1] Служба SSH'
sshd_config=$(sudo sshd -T)
check 'Вход root запрещён' no "$(awk '$1 == "permitrootlogin" {print $2}' <<< "$sshd_config")"
check 'Аутентификация по паролю отключена' no "$(awk '$1 == "passwordauthentication" {print $2}' <<< "$sshd_config")"
ssh_port=$(awk '$1 == "port" {print $2}' <<< "$sshd_config")
if [[ $ssh_port =~ ^[0-9]+$ && $ssh_port != 22 ]]; then
    check 'Порт SSH отличается от 22' yes yes
else
    check 'Порт SSH отличается от 22' yes "no: ${ssh_port:-unknown}"
fi
check 'MaxAuthTries равно 3' 3 "$(awk '$1 == "maxauthtries" {print $2}' <<< "$sshd_config")"

echo '[2] Межсетевой экран'
ufw_status=$(sudo ufw status verbose)
check 'Межсетевой экран активен' active "$(awk '/^Status:/ {print $2}' <<< "$ufw_status")"
check 'Входящие подключения запрещены по умолчанию' deny "$(awk '/^Default:/ {print $2}' <<< "$ufw_status")"

echo '[3] Учётные записи'
awk -F: '$3 >= 1000 && $3 < 65534 {printf " %s (uid=%s)\n", $1, $3}' /etc/passwd

echo '[4] Веб-сервер'
check 'Служба Nginx активна' active "$(systemctl is-active nginx)"
nginx_syntax=no
if sudo nginx -t >/dev/null 2>&1; then nginx_syntax=yes; fi
check 'Конфигурация Nginx корректна' yes "$nginx_syntax"
cert_valid=no
if openssl x509 -checkend "${AUDIT_CERT_MIN_SECONDS:-2592000}" \
    -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then
    cert_valid=yes
fi
check 'Сертификат действителен не менее заданного срока' yes "$cert_valid"
world_writable=$(find /var/www/devops-site -perm -o+w -print -quit)
key_mode=$(sudo stat -c '%a' /etc/ssl/private/devops.key)
if [[ -z $world_writable ]]; then
    check 'Права ресурса и закрытого ключа' 600 "$key_mode"
else
    check 'Права ресурса и закрытого ключа' 600 "world-writable: $world_writable"
fi

printf 'Пройдено: %s, не пройдено: %s\n' "$PASS" "$FAIL"
((FAIL == 0))
