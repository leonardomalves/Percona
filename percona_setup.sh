#!/bin/bash

set -e  # Para interromper o script em caso de erro
set -u  # Para evitar variáveis não definidas

# Definir usuário do sistema automaticamente
SYSTEM_USER=${SUDO_USER:-$USER}

LOG_FILE="/var/log/percona_xtrabackup_setup.log"
CONFIG_FILE="/home/$SYSTEM_USER/.percona_backup_config"
BACKUP_DIR="/home/$SYSTEM_USER/percona/backups/full"
TAR_FILE="/home/$SYSTEM_USER/percona/archives/backup_$(date +'%Y%m%d_%H%M%S').tar.gz"

# Função para carregar configurações anteriores
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Função para salvar configurações
save_config() {
    cat <<EOF > "$CONFIG_FILE"
MYSQL_USER="$MYSQL_USER"
MYSQL_PASSWORD="$MYSQL_PASSWORD"
MYSQL_ROOT_USER="$MYSQL_ROOT_USER"
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
EOF
}

# Função para ofuscar senhas
mask_password() {
    echo "******"
}

# Carregar configurações salvas
load_config

# Solicitar usuário e senha do MySQL (com opção de manter os valores anteriores)
echo -n "Digite o usuário do MySQL para backup [${MYSQL_USER:-não definido}]: "
read -r input
if [[ -n "$input" ]]; then
    MYSQL_USER="$input"
fi

echo -n "Digite a senha do MySQL para backup [$(mask_password)]: "
stty -echo
read -r input
stty echo
echo ""
if [[ -n "$input" ]]; then
    MYSQL_PASSWORD="$input"
fi

echo -n "Digite o usuário do MySQL root [${MYSQL_ROOT_USER:-não definido}]: "
read -r input
if [[ -n "$input" ]]; then
    MYSQL_ROOT_USER="$input"
fi

echo -n "Digite a senha do MySQL root [$(mask_password)]: "
stty -echo
read -r input
stty echo
echo ""
if [[ -n "$input" ]]; then
    MYSQL_ROOT_PASSWORD="$input"
fi

# Salvar configurações atualizadas
save_config

# Função para logging
echo_log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

echo_log "Atualizando pacotes..."
sudo apt update -y

# Instalando dependências
echo_log "Instalando dependências..."
sudo apt install gnupg2 wget -y

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

# Criando usuário de backup no MySQL
echo_log "Configurando usuário de backup no MySQL..."
mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT, SUPER, CREATE TABLESPACE, BACKUP_ADMIN, SELECT ON *.* TO '$MYSQL_USER'@'localhost';"
mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "GRANT SELECT ON performance_schema.replication_group_members TO '$MYSQL_USER'@'localhost';"
mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "GRANT SELECT ON performance_schema.keyring_component_status TO '$MYSQL_USER'@'localhost';"
mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

# Criando diretório de backup
echo_log "Criando diretório de backup..."
mkdir -p "$BACKUP_DIR"

# Executando backup
echo_log "Executando backup com Percona XtraBackup..."
sudo xtrabackup --backup --target-dir="$BACKUP_DIR" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD"

echo_log "Criando diretório para armazenar o TAR..."
mkdir -p "/home/$SYSTEM_USER/percona/archives"

echo_log "Compactando backup para restauração..."
tar -czf "$TAR_FILE" -C "$BACKUP_DIR" .

echo_log "Removendo conteúdo do diretório de backup..."
rm -rf "$BACKUP_DIR"/*

echo_log "Backup concluído com sucesso! Arquivo salvo em: $TAR_FILE"
