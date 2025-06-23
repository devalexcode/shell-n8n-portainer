#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Cargar variables de entorno del .env (requiere que exista en el mismo directorio)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    set -a
    source .env
    set +a
else
    echo "ERROR: No se encontró el archivo .env. Crea uno con PORTAINER_PORT y N8N_PORT."
    exit 1
fi

# Validar que las variables existan
: "${PORTAINER_PORT:?Falta definir PORTAINER_PORT en .env}"
: "${N8N_PORT:?Falta definir N8N_PORT en .env}"
: "${N8N_TIME_ZONE:?Falta definir N8N_TIME_ZONE en .env}"

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

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" |
        sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io

    sudo systemctl enable docker
    sudo systemctl start docker

    sudo usermod -aG docker "$USER"
    echo "Docker instalado: $(docker --version)"
else
    echo "Docker ya está instalado: $(docker --version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Docker Compose CLI plugin (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose CLI plugin no encontrado. Instalando..."
    sudo apt-get install -y docker-compose-plugin
    echo "Docker Compose instalado: $(docker compose version)"
else
    echo "Docker Compose ya está instalado: $(docker compose version)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de Portainer (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if docker container inspect portainer >/dev/null 2>&1; then
    echo "Portainer ya está instalado y configurado."
else
    echo "Instalando Portainer..."
    sudo docker volume create portainer_data
    sudo docker run -d \
        --name portainer \
        --restart=always \
        -p 8000:8000 \
        -p "${PORTAINER_PORT}":9000 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce

    sudo docker restart portainer
    echo "Portainer instalado y accesible en: http://$(hostname -I | awk '{print $1}'):${PORTAINER_PORT}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Instalación de n8n (si no está instalado)
# ─────────────────────────────────────────────────────────────────────────────
if docker container inspect n8n >/dev/null 2>&1; then
    echo "n8n ya está instalado y configurado."
else
    echo "Instalando n8n..."
    sudo docker volume create n8n_data
    sudo docker run -d \
        --name n8n \
        --restart=always \
        -p "${N8N_PORT}":5678 \
        -v n8n_data:/home/node/.n8n \
        -e GENERIC_TIMEZONE="${N8N_TIME_ZONE}" \
        n8nio/n8n:latest

    echo "n8n instalado y accesible en: http://$(hostname -I | awk '{print $1}'):${N8N_PORT}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Mensaje final
# ─────────────────────────────────────────────────────────────────────────────
echo "¡Instalación completada! Comprueba con: docker --version, docker compose version, \
accede a Portainer en el puerto ${PORTAINER_PORT} y n8n en el puerto ${N8N_PORT}."

# Refrescar grupos para la sesión actual
newgrp docker
