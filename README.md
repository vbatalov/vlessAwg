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
