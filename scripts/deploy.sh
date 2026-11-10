#!/usr/bin/env bash
set -euo pipefail

REMOTE=devops
REMOTE_DIR=/var/www/devops-site
SITE_URL=https://devops.local/
CA_CERT="$HOME/devops.crt"
REPO_ROOT=$(git rev-parse --show-toplevel)
LOCAL_DIR="$REPO_ROOT/site"
RSYNC_ARGS=(-avz --delete --chmod=D755,F644)
DRY_RUN=false

case "$#" in
    0) ;;
    1)
        if [[ $1 != --dry-run ]]; then
            echo 'Использование: scripts/deploy.sh [--dry-run]' >&2
            exit 1
        fi
        DRY_RUN=true
        RSYNC_ARGS+=(--dry-run)
        ;;
    *)
        echo 'Использование: scripts/deploy.sh [--dry-run]' >&2
        exit 1
        ;;
esac

if [[ ! -f "$LOCAL_DIR/index.html" ]]; then
    echo 'Деплой отменён: отсутствует site/index.html.' >&2
    exit 1
fi

if [[ -n $(git -C "$REPO_ROOT" status --porcelain) ]]; then
    echo 'Деплой отменён: в репозитории есть незафиксированные изменения.' >&2
    exit 1
fi

if ! rsync "${RSYNC_ARGS[@]}" -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' \
    "$LOCAL_DIR/" "$REMOTE:$REMOTE_DIR/"; then
    echo 'Не удалось синхронизировать ресурс.' >&2
    exit 1
fi

if $DRY_RUN; then
    echo 'Пробный запуск: файлы на сервере не изменены.'
    exit 0
fi

if ! curl --fail --silent --show-error --max-time 10 --cacert "$CA_CERT" \
    --output /dev/null "$SITE_URL"; then
    echo 'Синхронизация завершена, но HTTPS-проверка не пройдена.' >&2
    exit 1
fi

printf 'Опубликован коммит %s\n' "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
