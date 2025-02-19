#!/bin/bash

SYSTEM_USER=${SUDO_USER:-$USER}
INSTALL_FILE="/home/$SYSTEM_USER/.percona_install_config"
LOG_FILE="/home/$SYSTEM_USER/percona_backup_install.log"

echo_log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

save_install() {
    echo "INSTALLED=1" > "$INSTALL_FILE"
}

load_install() {
    if [[ -f "$INSTALL_FILE" ]]; then
        source "$INSTALL_FILE"
    else
        INSTALLED=0
    fi
}

# Verificando se o script já foi executado
load_install

if [[ "$INSTALLED" -eq 1 ]]; then
    echo_log "A instalação já foi concluída anteriormente. Saindo..."
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
   echo "Este script deve ser executado como root ou com sudo!"
   exit 1
fi

echo_log "Atualizando pacotes..."
sudo apt update -y

# Instalando dependências
echo_log "Instalando dependências..."
sudo apt install -y unzip gnupg2 wget

# Instalação do AWS CLI
if ! command -v aws &> /dev/null; then
    echo_log "Instalando AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip || echo_log "Falha ao remover arquivos temporários"
else
    echo_log "AWS CLI já está instalado."
fi

# Adicionando repositório Percona
echo_log "Adicionando repositório Percona..."
wget -O percona-release_latest.deb https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb
sudo dpkg -i percona-release_latest.deb
rm -f percona-release_latest.deb

# Configurando repositório e instalando Percona XtraBackup
echo_log "Configurando repositório e instalando Percona XtraBackup..."
sudo percona-release setup ps80
sudo apt update -y
sudo apt install percona-xtrabackup-80 -y

echo_log "Instalação concluída com sucesso!"
save_install
