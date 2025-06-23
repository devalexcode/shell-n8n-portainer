#!/usr/bin/env bash
set -euo pipefail

# Colores ANSI
GREEN='\033[0;32m'
NC='\033[0m' # No Color (reset)

# ─────────────────────────────────────────────────────────────────────────────
# Cargar variables de entorno del .env (requiere que exista en el mismo directorio)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    set -a && source .env && set +a
else
    echo "ERROR: No se encontró el archivo .env. Crea uno con PORTAINER_PORT, N8N_PORT, N8N_TIME_ZONE y N8N_HOST."
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Determinar protocolo y configuración de cookie según N8N_HOST
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${N8N_HOST}" =~ ^https?:// ]]; then
    N8N_PROTOCOL="https"
    N8N_SECURE_COOKIE="true"
else
    N8N_PROTOCOL="http"
    N8N_SECURE_COOKIE="false"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Actualizar repositorios y paquetes
# ─────────────────────────────────────────────────────────────────────────────
sudo apt update && sudo apt upgrade -y

# ─────────────────────────────────────────────────────────────────────────────
# Instalar prerequisitos (si faltan)
# ─────────────────────────────────────────────────────────────────────────────
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Docker (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker no encontrado. Instalando Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
        sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo -e "${GREEN}Docker instalado: $(docker --version)${NC}"
else
    echo "Docker ya está instalado: $(docker --version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Docker Compose CLI plugin (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose CLI plugin no encontrado. Instalando..."
    sudo apt-get install -y docker-compose-plugin
    echo -e "${GREEN}Docker Compose instalado: $(docker compose version)${NC}"
else
    echo "Docker Compose ya está instalado: $(docker compose version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Portainer (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if sudo docker container inspect portainer >/dev/null 2>&1; then
    echo "Portainer ya está instalado y configurado."
else
    echo "Instalando Portainer..."
    sudo docker volume create portainer_data
    sudo docker run -d --name portainer --restart=always \
        -p 8000:8000 -p "${PORTAINER_PORT}":9000 \
        -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data \
        portainer/portainer-ce
    sudo docker restart portainer
    echo -e "${GREEN}Portainer instalado y accesible en: http://$(hostname -I | awk '{print $1}'):${PORTAINER_PORT}${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de n8n (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if sudo docker container inspect n8n >/dev/null 2>&1; then
    echo "n8n ya está instalado y configurado."
else
    echo "Instalando n8n..."
    sudo docker volume create n8n_data

    sudo docker run -d --name n8n --restart=always \
        -p "${N8N_PORT}":5678 \
        -v n8n_data:/home/node/.n8n \
        -e TZ="${N8N_TIME_ZONE}" \
        -e GENERIC_TIMEZONE="${N8N_TIME_ZONE}" \
        -e N8N_SECURE_COOKIE="${N8N_SECURE_COOKIE}" \
        -e N8N_PROTOCOL="${N8N_PROTOCOL}" \
        -e N8N_HOST="${N8N_HOST}" \
        -e WEBHOOK_TUNNEL_URL="${WEBHOOK_TUNNEL_URL}" \
        -e N8N_EDITOR_BASE_URL="${N8N_EDITOR_BASE_URL}" \
        -e WEBHOOK_URL="${WEBHOOK_URL}" \
        n8nio/n8n:latest

    INSTALLED_N8N_URL="${N8N_HOST}:${N8N_PORT}"

    echo -e "${GREEN}n8n instalado y accesible en: ${INSTALLED_N8N_URL}${NC}"

    # Notificar si se ha deshabilitado la cookie secure
    if [[ "${N8N_SECURE_COOKIE}" == "false" ]]; then
        echo "ADVERTENCIA: la cookie 'secure' está deshabilitada (N8N_SECURE_COOKIE=false)."
    fi
fi

# Refrescar grupos para la sesión actual
newgrp docker
