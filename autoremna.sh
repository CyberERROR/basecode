#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'
LOG_FILE="/tmp/remna_install.log"

> "$LOG_FILE"

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -n " "
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

run_quiet() {
    local msg=$1
    shift
    echo -ne "${YELLOW}$msg...${NC}"
    "$@" >> "$LOG_FILE" 2>&1 &
    spinner $!
    echo -e "${GREEN} Чётко!${NC}"
}

normalize_input() {
    echo "$1" | tr -d '\r' | sed 's/[^a-zA-Z0-9@._-]//g'
}

print_step() {
    echo -e "\n${PURPLE}${BOLD}[*] $1${NC}"
}

print_error() {
    echo -e "${RED}${BOLD}[!] Э, брат, косяк: $1${NC}"
    echo -e "${RED}Глянь логи, если чё: $LOG_FILE${NC}"
}

print_banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "  ____                                                  "
    echo " |  _ \ ___ _ __ ___  _ __   __ ___      ____ ___   _____ "
    echo " | |_) / _ \ '_ \` _ \| '_ \ / _\` \ \ /\ / / _\` \ \ / / _ \\"
    echo " |  _ <  __/ | | | | | | | | (_| |\ V  V / (_| |\ V /  __/"
    echo " |_| \_\___|_| |_| |_|_| |_|\__,_| \_/\_/ \__,_| \_/ \___|"
    echo "                                                        "
    echo -e "      ${YELLOW}INSTALLER by CyberERROR ${NC}"
    echo -e "${BLUE}======================================================${NC}\n"
}

print_banner

print_step "Слышь, брат, давай перетрем за цифры (Сбор инфы)..."

if [ ! -t 0 ] && [ ! -e /dev/tty ]; then
    print_error "Терминал не тот, братан! Запусти нормально."
    exit 1
fi

echo -e "${YELLOW}Нам нужен адрес для панели. Какой базар будет? (напр. panel.domain.com)${NC}"
read -p "👉 Вводи сюда: " PANEL_DOMAIN < /dev/tty

echo -e "\n${YELLOW}А для подписки подгони адресок? (напр. sub.domain.com)${NC}"
read -p "👉 Вводи сюда: " SUB_DOMAIN < /dev/tty

echo -e "\n${YELLOW}Скинь маляву (Email) чисто для сертификатов:${NC}"
read -p "👉 Вводи сюда: " USER_EMAIL < /dev/tty

PANEL_DOMAIN=$(normalize_input "$PANEL_DOMAIN")
SUB_DOMAIN=$(normalize_input "$SUB_DOMAIN")
USER_EMAIL=$(normalize_input "$USER_EMAIL")

if [ -z "$PANEL_DOMAIN" ] || [ -z "$SUB_DOMAIN" ] || [ -z "$USER_EMAIL" ]; then
    print_error "Ты чё, пустой лист мне суешь? Миша, всё хуйня, давай по новой!"
    exit 1
fi

if [ "$PANEL_DOMAIN" == "$SUB_DOMAIN" ]; then
    print_error "Брат, ты попутал? Домены одинаковые, так дела не делаются."
    exit 1
fi

print_step "Ща глянем, чё там по Докеру..."
if ! command -v docker &> /dev/null; then
    run_quiet "Докера нет, подтягиваем братву" bash -c "curl -fsSL https://get.docker.com | sh"
else
    echo -e "${GREEN}Докер уже на месте, всё ровно.${NC}"
fi

print_step "Готовим поляну (создаем папки)..."
mkdir -p /opt/remnawave
mkdir -p /opt/remnawave/nginx
mkdir -p /opt/remnawave/subscription
echo -e "${GREEN}Папки нарезали.${NC}"

cd /opt/remnawave || exit
print_step "Настраиваем движуху (Remnawave Panel)..."

run_quiet "Тянем конфиги с общака" bash -c "curl -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml && curl -o .env https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample"

echo -e "${YELLOW}Генерируем секретные шифры...${NC}"
sed -i "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" .env
sed -i "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" .env
sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env

DB_PASS=$(openssl rand -hex 24)
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$DB_PASS/" .env
sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^\@]*\(@.*\)|\1$DB_PASS\2|" .env

sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$PANEL_DOMAIN|" .env
sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_DOMAIN|" .env

cd /opt/remnawave/subscription || exit
print_step "Мутим страницу подписки..."

cat > docker-compose.yml <<EOF
services:
    remnawave-subscription-page:
        image: remnawave/subscription-page:latest
        container_name: remnawave-subscription-page
        hostname: remnawave-subscription-page
        restart: always
        env_file:
            - .env
        ports:
            - '127.0.0.1:3010:3010'
        networks:
            - remnawave-network

networks:
    remnawave-network:
        driver: bridge
        external: true
EOF

cat > .env <<EOF
APP_PORT=3010
REMNAWAVE_PANEL_URL=http://remnawave:3000
META_TITLE="Subscription page"
META_DESCRIPTION="Subscription page description"
CUSTOM_SUB_PREFIX=
MARZBAN_LEGACY_LINK_ENABLED=false
MARZBAN_LEGACY_SECRET_KEY=
REMNAWAVE_API_TOKEN=
CADDY_AUTH_API_TOKEN=
EOF

echo -e "${GREEN}Настройки на базе.${NC}"

print_step "Оформляем ксивы (SSL сертификаты)..."

for cert_file in "fullchain.pem" "privkey.key" "subdomain_fullchain.pem" "subdomain_privkey.key"; do
    if [ -d "/opt/remnawave/nginx/$cert_file" ]; then
        run_quiet "Убираем мусор за Докером" rm -rf "/opt/remnawave/nginx/$cert_file"
    fi
done

run_quiet "Обновляем списки" sudo apt-get update

if [ -f /etc/needrestart/needrestart.conf ]; then
    sudo sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
fi

run_quiet "Ставим нужный софт (cron, socat)" sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" cron socat

run_quiet "Загружаем acme.sh для авторитета" bash -c "curl https://get.acme.sh | sh -s email=\"$USER_EMAIL\""

source ~/.bashrc
export PATH="$HOME/.acme.sh:$PATH"

run_quiet "Настраиваем CA" ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

run_quiet "Выбиваем сертификат на ПАНЕЛЬ ($PANEL_DOMAIN)" ~/.acme.sh/acme.sh --issue --standalone -d "$PANEL_DOMAIN" \
    --key-file /opt/remnawave/nginx/privkey.key \
    --fullchain-file /opt/remnawave/nginx/fullchain.pem

run_quiet "Выбиваем сертификат на ПОДПИСКУ ($SUB_DOMAIN)" ~/.acme.sh/acme.sh --issue --standalone -d "$SUB_DOMAIN" \
    --key-file /opt/remnawave/nginx/subdomain_privkey.key \
    --fullchain-file /opt/remnawave/nginx/subdomain_fullchain.pem

if [ ! -f /opt/remnawave/nginx/fullchain.pem ] || [ ! -f /opt/remnawave/nginx/subdomain_fullchain.pem ]; then
    print_error "Брат, беда. Сертификаты не дали. Проверь DNS и логи."
fi

cd /opt/remnawave/nginx || exit
print_step "Пишем маляву для Nginx (Конфиг)..."

cat > nginx.conf <<EOF
upstream remnawave {
    server remnawave:3000;
}

upstream remnawave-subscription-page {
    server remnawave-subscription-page:3010;
}

server {
    server_name $PANEL_DOMAIN;

    listen 443 ssl reuseport;
    listen [::]:443 ssl reuseport;
    http2 on;

    location /api/ {
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
    }

    location / {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    ssl_protocols          TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;

    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets    off;
    ssl_certificate "/etc/nginx/ssl/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/privkey.key";
    ssl_trusted_certificate "/etc/nginx/ssl/fullchain.pem";

    ssl_stapling           on;
    ssl_stapling_verify    on;
    resolver               1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 208.67.222.222 208.67.220.220 valid=60s;
    resolver_timeout       2s;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_types
        application/atom+xml
        application/geo+json
        application/javascript
        application/x-javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rdf+xml
        application/rss+xml
        application/xhtml+xml
        application/xml
        font/eot
        font/otf
        font/ttf
        image/svg+xml
        text/css
        text/javascript
        text/plain
        text/xml;
}

server {
    server_name $SUB_DOMAIN;

    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;

    location / {
        proxy_http_version 1.1;
        proxy_pass http://remnawave-subscription-page;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    ssl_protocols          TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;

    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets    off;
    ssl_certificate "/etc/nginx/ssl/subdomain_fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/subdomain_privkey.key";
    ssl_trusted_certificate "/etc/nginx/ssl/subdomain_fullchain.pem";

    ssl_stapling           on;
    ssl_stapling_verify    on;
    resolver               1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 208.67.222.222 208.67.220.220 valid=60s;
    resolver_timeout       2s;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_types
        application/atom+xml
        application/geo+json
        application/javascript
        application/x-javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rdf+xml
        application/rss+xml
        application/xhtml+xml
        application/xml
        font/eot
        font/otf
        font/ttf
        image/svg+xml
        text/css
        text/javascript
        text/plain
        text/xml;
}

server {
    server_name _;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_reject_handshake on;
}
EOF

cat > docker-compose.yml <<EOF
services:
    remnawave-nginx:
        image: nginx:1.28
        container_name: remnawave-nginx
        hostname: remnawave-nginx
        volumes:
            - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
            - ./fullchain.pem:/etc/nginx/ssl/fullchain.pem:ro
            - ./privkey.key:/etc/nginx/ssl/privkey.key:ro
            - ./subdomain_fullchain.pem:/etc/nginx/ssl/subdomain_fullchain.pem:ro
            - ./subdomain_privkey.key:/etc/nginx/ssl/subdomain_privkey.key:ro
        restart: always
        ports:
            - '0.0.0.0:443:443'
        networks:
            - remnawave-network

networks:
    remnawave-network:
        name: remnawave-network
        driver: bridge
        external: true
EOF

print_step "Всё по красоте, запускаем моторы..."

cd /opt/remnawave || exit
run_quiet "Поднимаем Backend" docker compose up -d

cd /opt/remnawave/subscription || exit
run_quiet "Поднимаем Страницу подписки" docker compose up -d

cd /opt/remnawave/nginx || exit
run_quiet "Поднимаем Nginx (Шлюз)" docker compose up -d

print_banner
echo -e "${YELLOW}Брат, ждем 5 секунд, пусть системы прогрузятся...${NC}"
sleep 5

echo -e "\n${PURPLE}${BOLD}[*] Последний штрих, брат!${NC}"
echo -e "${YELLOW}Надо связать подписку с панелью. Без этого кина не будет.${NC}"
echo -e "1. Залетай на панель: ${CYAN}https://$PANEL_DOMAIN${NC}"
echo -e "2. Логинься (создавай админа)."
echo -e "3. Иди в ${BOLD}Настройки -> API Токены${NC}."
echo -e "4. Создавай новый токен и копируй его сюда."

while [ -z "$TOKEN" ]; do
    read -p "👉 Вставляй токен: " TOKEN < /dev/tty
    TOKEN=$(echo "$TOKEN" | tr -d '\r' | xargs)
    
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Брат, без токена никак. Давай по новой.${NC}"
    fi
done

cd /opt/remnawave/subscription || exit
run_quiet "Привязываем токен и перезагружаем подписку" bash -c "sed -i \"s/^REMNAWAVE_API_TOKEN=.*/REMNAWAVE_API_TOKEN=$TOKEN/\" .env && docker compose down && docker compose up -d"

print_banner
echo -e "${GREEN}${BOLD}Всё, брат, обнял! Установка завершена 🚀${NC}"
echo -e "${CYAN}Залетай на панель:${NC} https://$PANEL_DOMAIN"
echo -e "${CYAN}Страница подписки:${NC} https://$SUB_DOMAIN"
echo -e "${PURPLE}Пользуйся на здоровье!${NC}"
