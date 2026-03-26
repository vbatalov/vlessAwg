# DockerVPN VLESS

## 1. Set build variables

```bash
cp .env.example .env
# edit .env and set SERVER_HOST
```

## 2. Build and start (VLESS config is generated during build)

```bash
./scripts/init-vless.sh
```

## 3. Print VLESS link again

```bash
./scripts/vless-link.sh
```
