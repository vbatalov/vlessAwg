# DockerVPN Gateway (VLESS + SOCKS, VPS + VPN)

Проект поднимает один контейнер `gateway`:

- `xray` (inbounds: VLESS + SOCKS)
- `AmneziaWG` клиент (`awg`)

Режимы выхода:

- `VPS` (прямой IP VPS)
- `VPN` (строго через `awg0`, без fallback на прямой VPS)

## Быстрый запуск на новом VPS

1. Склонировать репозиторий.
2. Положить приватный файл `config/awg0.conf` (он не хранится в git).
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
- ставит `amneziawg` kernel module, грузит модуль
- включает sysctl `net.ipv4.conf.all.src_valid_mark=1`
- создает `.env` из `.env.example` (если его нет)
- прописывает `SERVER_HOST`, `AWG_BACKEND=kernel`, `AWG_LISTEN_PORT=20000`
- собирает и поднимает `gateway`
- запускает debug:
  - `docker compose ps`
  - `docker compose logs --tail=80 gateway`
  - вывод ссылок подключения
  - проверка egress (`host`, `socks_vps`, `socks_vpn`)
  - серия VPN probe-запросов

## Получить ссылки подключений

```bash
./scripts/vless-link.sh
```

Скрипт выводит:

- `VLESS VPS`
- `VLESS VPN`
- `SOCKS VPS`
- `SOCKS VPN`
