# DockerVPN Gateway (VLESS only)

Проект поднимает один контейнер `gateway` с `xray` и одним входом `VLESS + REALITY`.

Подключение только одно:

- `VLESS` -> `MAC -> VPS -> Internet`

## Быстрый запуск на новом VPS

1. Склонировать репозиторий.
2. Запустить:

```bash
sudo ./install.sh
```

Если нужно явно задать IP сервера:

```bash
sudo ./install.sh <SERVER_IP>
```

Полная пересборка образа:

```bash
sudo ./install.sh <SERVER_IP> --force
```

## Что делает `install.sh`

- ставит системные пакеты и Docker
- включает/запускает Docker daemon
- создает `.env` из `.env.example` (если его нет)
- нормализует дефолты VLESS
- прописывает `SERVER_HOST`
- собирает и поднимает `gateway`
- запускает debug:
  - `docker compose ps`
  - `docker compose logs --tail=80 gateway`
  - вывод ссылки подключения
  - проверка egress (`host_ip`, `container_ip`)

## Получить ссылку подключения

```bash
./scripts/vless-link.sh
```

Скрипт выводит:

- `VLESS`
