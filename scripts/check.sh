#!/usr/bin/env bash
set -euo pipefail

stage='Переход в корень проекта'
project="ipr-check-$$-${RANDOM}${RANDOM}"
restored="${project}-restore"
archive="backups/${project}.tar"
source_created=0
restore_created=0
n=3

dc() {
    local project_name=$1
    shift
    APP_PORT=0 docker compose -f compose.yaml -p "$project_name" "$@"
}

cleanup() {
    local result=$?
    if (( result != 0 )); then
        printf 'Ошибка на этапе «%s» (код %s)\n' "$stage" "$result" >&2
    fi
    if (( restore_created )); then
        dc "$restored" down -v --rmi local || result=1
    fi
    if (( source_created )); then
        dc "$project" down -v --rmi local || result=1
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$(dirname "$0")/.."

phase() {
    stage=$1
    printf '\n%s\n' "$stage"
}

expect() {
    local expected=$1 actual=$2
    if [[ "$actual" != "$expected" ]]; then
        printf 'Ожидалось %s, получено %s\n' "$expected" "$actual" >&2
        return 1
    fi
}

base_url() {
    local address
    address=$(dc "$1" port app 8000) || return 1
    printf 'http://%s\n' "$address"
}

count() {
    local project_name=$1 url=$2 method=$3 endpoint=$4
    curl -fsS --max-time 5 -X "$method" "$url$endpoint" |
        dc "$project_name" exec -T app python -c \
            'import json, sys; print(json.load(sys.stdin)["count"])'
}

status() {
    curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -X "$1" "$2"
}

wait_ready() {
    local url=$1 attempt
    for ((attempt=1; attempt<=20; attempt++)); do
        if curl -fs --max-time 2 "$url/readyz" >/dev/null; then
            return 0
        fi
        sleep 1
    done
    printf 'Сервис не стал готов: %s/readyz\n' "$url" >&2
    return 1
}

archive_redis() {
    local project_name=$1
    shift
    dc "$project_name" run --rm -T --no-deps --pull never \
        --user 0:0 --entrypoint tar redis "$@"
}

phase 'Запуск отдельного Compose-проекта'
source_created=1
dc "$project" up --build --wait --wait-timeout 60
url=$(base_url "$project")

phase 'Проверка исходного значения и трёх инкрементов'
expect 0 "$(count "$project" "$url" GET /)"
for ((index=1; index<=n; index++)); do
    expect "$index" "$(count "$project" "$url" POST /increment)"
done
expect "$n" "$(count "$project" "$url" GET /)"
printf 'Счётчик вырос с 0 до %s\n' "$n"

phase 'Пересоздание только приложения'
old_app=$(dc "$project" ps -q app)
old_redis=$(dc "$project" ps -q redis)
dc "$project" up --no-deps --force-recreate --wait --wait-timeout 60 app
app=$(dc "$project" ps -q app)
[[ -n "$app" && "$app" != "$old_app" ]]
expect "$old_redis" "$(dc "$project" ps -q redis)"
url=$(base_url "$project")
expect "$n" "$(count "$project" "$url" GET /)"
printf 'После пересоздания приложения count=%s\n' "$n"

phase 'Остановка и повторный запуск Redis'
dc "$project" stop redis
expect 200 "$(status GET "$url/healthz")"
expect 503 "$(status GET "$url/readyz")"
expect 503 "$(status POST "$url/increment")"
printf 'HTTP-коды при отказе: 200 / 503 / 503\n'
dc "$project" start redis
wait_ready "$url"
expect "$app" "$(dc "$project" ps -q app)"
expect "$n" "$(count "$project" "$url" GET /)"
final_count=$((n + 1))
expect "$final_count" "$(count "$project" "$url" POST /increment)"
printf 'После запуска Redis счётчик вырос с %s до %s\n' "$n" "$final_count"

phase 'Согласованный бэкап Redis'
mkdir -p backups
dc "$project" stop app
dc "$project" stop redis
archive_redis "$project" -C /data -cpf - . > "$archive"
archive_redis "$project" -tf - < "$archive"

phase 'Удаление исходного проекта и его volumes'
dc "$project" down -v --rmi local
source_created=0

phase 'Восстановление архива в новый volume'
restore_created=1
archive_redis "$restored" -C /data -xpf - < "$archive"
dc "$restored" up --build --wait --wait-timeout 60
restore_url=$(base_url "$restored")
expect "$final_count" "$(count "$restored" "$restore_url" GET /)"
printf 'Восстановлен count=%s из %s\n' "$final_count" "$archive"

phase 'Очистка проекта восстановления'
dc "$restored" down -v --rmi local
restore_created=0
printf '\nПроверка пройдена\n'
