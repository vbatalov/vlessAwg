# DockerVPN Gateway (VLESS direct + VLESS TrustChannel)

Проект поднимает один контейнер `gateway`:

- `xray` (только VLESS inbounds)
- `trusttunnel_client` (внутренний upstream для TrustChannel)

Поддерживаются 2 режима подключения:

- `VLESS VPS` -> `MAC -> VPS -> Internet`
- `VLESS TrustChannel` -> `MAC -> VPS -> TrustChannel -> Internet`

SOCKS5 для внешних клиентов отключен (не публикуется).

## Быстрый запуск на новом VPS

1. Склонировать репозиторий.
2. Убедиться, что файл `config/trustchannel-client.toml` присутствует.
3. Запустить:

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
- нормализует дефолты VLESS/TrustChannel
- проверяет `config/trustchannel-client.toml`
- прописывает `SERVER_HOST`
- собирает и поднимает `gateway`
- запускает debug:
  - `docker compose ps`
  - `docker compose logs --tail=80 gateway`
  - вывод ссылок подключения
  - проверка egress (`host_ip`, `container_direct_ip`, `container_trust_ip`)
  - серия `trust_probe` через внутренний TrustChannel SOCKS

## Получить ссылки подключений

```bash
./scripts/vless-link.sh
```

Скрипт выводит:

- `VLESS VPS`
- `VLESS TrustChannel`
