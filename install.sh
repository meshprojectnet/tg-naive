#!/usr/bin/env bash
# tg-naive · локальная или SSH-сборка/деплой через Docker Compose
#
# Запуск локально:
#   bash scripts/install-docker.sh --local --hostname endpoint.hy2.fun --site studio-garden [--secret HEX]
#
# Запуск по SSH:
#   bash scripts/install-docker.sh --ssh user@host --hostname endpoint.hy2.fun --site studio-garden
set -euo pipefail

mode=""
ssh_target=""
hostname=""
site=""
secret=""
repo_dir=""

usage() {
	cat <<'EOF'
tg-naive deploy

  install-docker.sh --local --hostname FQDN --site NAME [--secret HEX]
  install-docker.sh --ssh user@host --hostname FQDN --site NAME

  --local          выполнять сборку и запуск на текущем хосте
  --ssh TARGET     выполнять сборку и запуск на удалённом сервере по SSH
  --hostname FQDN  домен (например, endpoint.hy2.fun)
  --site NAME      имя шаблона сайта (например, studio-garden)
  --secret HEX     (опционально) 32 hex-символа секрета MTProxy
EOF
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--local) mode="local"; shift ;;
		--ssh) mode="ssh"; ssh_target="${2:-}"; shift 2 ;;
		--hostname) hostname="${2:-}"; shift 2 ;;
		--site) site="${2:-}"; shift 2 ;;
		--secret) secret="${2:-}"; shift 2 ;;
		--email) shift 2 ;; # Игнорируем флаг email для обратной совместимости
		-h|--help) usage ;;
		*) echo "Неизвестный параметр: $1" >&2; usage ;;
	esac
done

[[ -z "$mode" || -z "$hostname" || -z "$site" ]] && usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

generate_secret() {
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -hex 16
	else
		head -c 16 /dev/urandom | xxd -p | tr -d '\n'
	fi
}

if [[ -z "$secret" ]]; then
	secret="$(generate_secret)"
fi

# Нормализация секрета (приведение к нижнему регистру)
secret="${secret,,}"

deploy_local() {
	cd "$REPO_DIR"

	echo "==> Создание конфигурационного файла .env..."
	cat <<EOF > .env
TPROXY_HOSTNAME=${hostname}
TPROXY_SECRET=${secret}
TPROXY_SITE=${site}
EOF

	echo "==> Сборка и запуск Docker контейнеров..."
	docker compose up -d --build --remove-orphans

	echo ""
	echo "=================================================="
	echo " Установка tg-naive успешно завершена!"
	echo "=================================================="
	echo " Hostname : ${hostname}"
	echo " Site     : ${site}"
	echo " Secret   : ${secret}"
	echo "=================================================="
}

deploy_ssh() {
	echo "==> Подключение к $ssh_target через SSH..."
	ssh "$ssh_target" "mkdir -p /opt/tg-naive"
	
	echo "==> Копирование файлов проекта на $ssh_target..."
	rsync -avz --exclude='.git' --exclude='runtime/site' "$REPO_DIR/" "$ssh_target:/opt/tg-naive/"

	echo "==> Запуск установки на удалённом сервере..."
	ssh "$ssh_target" "bash /opt/tg-naive/scripts/install-docker.sh --local --hostname '$hostname' --site '$site' --secret '$secret'"
}

if [[ "$mode" == "local" ]]; then
	deploy_local
elif [[ "$mode" == "ssh" ]]; then
	deploy_ssh
fi
