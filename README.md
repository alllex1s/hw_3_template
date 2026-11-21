**ДЗ 3 по Docker**

Тут счётчик на Python. Через Compose запускаются приложение и Redis. Redis пишет изменения на диск в том `redis_data`. С компьютера доступен только порт приложения.

Сначала скопируй настройки из примера и запусти Compose.

```sh
cp .env.example .env
docker compose up --build --wait
```

Счётчик будет на `http://127.0.0.1:8080/`.

```sh
curl http://127.0.0.1:8080/readyz
curl http://127.0.0.1:8080/
curl -X POST http://127.0.0.1:8080/increment
```

Порт и приветствие можно поменять в `.env`. За порт отвечает `APP_PORT`, за приветствие — `GREETING`. После этого ещё раз запусти `docker compose up --wait`.

Чтобы остановить проект, выполни `docker compose down`. При следующем запуске счётчик продолжит с того же числа.

**Проверка**

```sh
./scripts/check.sh
```

Скрипт проверяет счётчик после пересоздания `app` и остановки Redis. Потом делает бэкап в `backups/`, восстанавливает счётчик в новом томе и убирает тестовые проекты.

Что получилось, записал в [отчёте](REPORT.md). [Условие ДЗ](https://github.com/Nikfilk2030/missing_semester_hse_cs/blob/main/2026/amcs/year_1/hw_3/README.md)
