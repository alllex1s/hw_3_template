**Отчёт по ДЗ 3**

**4 балла**

Сначала проверил один контейнер на порту `8082`.

```sh
docker build -t ipr-check-4:local .
docker run -d --name ipr-check-4 -p 127.0.0.1:8082:8000 \
  -e 'GREETING=ура 4 балла' ipr-check-4:local
curl http://127.0.0.1:8082/readyz
curl http://127.0.0.1:8082/
curl -X POST http://127.0.0.1:8082/increment
curl http://127.0.0.1:8082/
docker stop ipr-check-4
docker rm ipr-check-4
```

`/readyz` вернул `ready`. В ответах было приветствие `ура 4 балла` и `storage=sqlite`. Первый GET показал `0`, POST прибавил 1, второй GET показал `1`. [Лог запуска и запросов](report/level-4.log)

**6 баллов**

На этом этапе `app` использовал SQLite. Запустил отдельный проект `ipr-check-6` с пустым томом `sqlite_data`. На старте счётчик был `0`, после POST стал `1`.

```sh
APP_PORT=8082 GREETING='привет из compose' docker compose -p ipr-check-6 up -d --build
docker compose -p ipr-check-6 ps -q app
curl http://127.0.0.1:8082/
curl -X POST http://127.0.0.1:8082/increment
```

Потом сделал `down` и снова запустил Compose.

```sh
docker compose -p ipr-check-6 down
APP_PORT=8082 GREETING='привет из compose' docker compose -p ipr-check-6 up -d
docker compose -p ipr-check-6 ps -q app
curl http://127.0.0.1:8082/
```

- До `down` контейнер `62abe166bb65` вернул `count=1`
- После `up` контейнер `a3d1d85a3700` вернул `count=1`

У обоих контейнеров к `/data` был подключён один и тот же том `ipr-check-6_sqlite_data`.

Ещё проверил, что можно поменять порт и приветствие без пересборки образа.

```sh
APP_PORT=8083 GREETING='привет с нового порта' docker compose -p ipr-check-6 up -d
curl http://127.0.0.1:8083/
```

На порту `8083` получилось вот так.

```json
{"greeting": "привет с нового порта", "count": 1, "hostname": "383679038cdd", "storage": "sqlite"}
```

В конце удалил тестовый проект и его том через `docker compose -p ipr-check-6 down -v --rmi local`.

**8 баллов**

Дальше запустил `app` и Redis через Compose. Оба сервиса стали `healthy`. С компьютера открывался только порт приложения `8082`. У Redis был том `ipr-check-8_redis_data` в `/data`, а `CONFIG GET appendonly` показал `yes`.

```sh
APP_PORT=8082 GREETING='привет из redis' docker compose -p ipr-check-8 up --build --wait
docker compose -p ipr-check-8 ps
docker compose -p ipr-check-8 exec -T redis redis-cli CONFIG GET appendonly
curl -X POST http://127.0.0.1:8082/increment
curl -X POST http://127.0.0.1:8082/increment
curl -X POST http://127.0.0.1:8082/increment

docker compose -p ipr-check-8 down
APP_PORT=8082 GREETING='привет из redis' docker compose -p ipr-check-8 up --wait
curl http://127.0.0.1:8082/
```

После третьего POST было `3`. Сделал `down` и `up`, снова получил `3` и `привет из redis`.

Потом остановил только Redis и посмотрел коды ответов.

```sh
docker compose -p ipr-check-8 stop redis
curl -i http://127.0.0.1:8082/healthz
curl -i http://127.0.0.1:8082/readyz
curl -i -X POST http://127.0.0.1:8082/increment
```

- `GET /healthz` → `200`
- `GET /readyz` → `503`
- `POST /increment` → `503`

```sh
docker compose -p ipr-check-8 start redis
curl -i http://127.0.0.1:8082/readyz
curl http://127.0.0.1:8082/
curl -X POST http://127.0.0.1:8082/increment
```

После запуска Redis `/readyz` снова вернул `200`. У `app` остались тот же ID `4433be330f1b` и то же время запуска. GET показал `3`, ещё один POST — `4`.

**10 баллов**

Проверил настройки контейнера `app`.

```sh
docker compose exec -T app id -u
app_id=$(docker compose ps -q app)
docker inspect "$app_id" --format \
  '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}'
```

UID получился `10001`. Вторая команда вывела `true 268435456 1000000000`. Значит, корневая файловая система только для чтения, по памяти лимит 256 MiB, по процессору одно ядро.

Скрипт запустил два раза подряд.

```sh
./scripts/check.sh > report/check-1.log 2>&1
./scripts/check.sh > report/check-2.log 2>&1
```

В обоих запусках после пересоздания `app` счётчик был `3`, а при остановленном Redis получились коды `200 / 503 / 503`. Из архива восстановилось `4`.

- [Первый запуск](report/check-1.log)
- [Второй запуск](report/check-2.log)

Оба раза счётчик начинался с `0`, а в конце было `Проверка пройдена`. Перед бэкапом скрипт останавливал приложение и Redis. Потом удалял исходный том и восстанавливал счётчик в новом. Тестовые контейнеры, сети и тома удалились, архивы остались в `backups/`.

Ещё проверил, что будет, если `curl` вернёт ошибку. Скрипт написал, на каком этапе сломалась проверка, завершился с кодом `1` и убрал тестовый проект вместе с томом.
