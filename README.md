# DockerVPN Gateway (VLESS + SOCKS, VPS + VPN)

Один контейнер поднимает:

- `xray` (входы VLESS/SOCKS)
- `AmneziaWG` клиент (`amneziawg-go` + `awg`)
- локальный `danted`, через который Xray отправляет VPN-трафик

Поддерживаются 2 режима в рамках одного проекта:

- `VPS` (чистый внешний IP VPS)
- `VPN` (выход через `awg0`)

И 2 типа входа для каждого режима:

- `VLESS`
- `SOCKS`

`VPN`-режим строго идет только через `awg0` (без fallback на прямой `VPS`).

## Файлы

- `config/awg0.conf` — клиентский конфиг AmneziaWG
- `.env` — порты, хост, имена соединений
- `docker-compose.yml` — сервис `gateway`

## Подготовка

```bash
cp .env.example .env
# заполнить SERVER_HOST
```

Проверить, что `config/awg0.conf` существует.

На VPS должен быть включен:

```bash
sysctl -w net.ipv4.conf.all.src_valid_mark=1
```

## Запуск

```bash
./scripts/init-vless.sh
```

## Получить все подключения

```bash
./scripts/vless-link.sh
```

Скрипт печатает:

- `VLESS VPS` (прямой выход через VPS)
- `VLESS VPN` (выход через awg)
- `SOCKS VPS`
- `SOCKS VPN`

## AWG watchdog

Контейнер включает watchdog для `awg0`: при слишком старом handshake автоматически перезапускает AWG-стек и локальный VPN SOCKS.

Параметры в `.env`:

- `AWG_WATCHDOG_ENABLED`
- `AWG_WATCHDOG_INTERVAL`
- `AWG_WATCHDOG_STALE_SECONDS`
- `AWG_WATCHDOG_FAIL_THRESHOLD`
- `AWG_MTU_OVERRIDE`
- `AWG_TCP_MSS`
