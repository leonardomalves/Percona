#!/bin/bash

set -e  # Para interromper o script em caso de erro
set -u  # Para evitar variáveis não definidas

LOG_FILE="/var/log/percona_xtrabackup_setup.log"

# Definir usuário do sistema automaticamente
SYSTEM_USER=$(whoami)
BACKUP_DIR="/home/$SYSTEM_USER/percona/backups/full"

# Solicitar usuário e senha do MySQL
echo -n "Digite o usuário do MySQL para backup: "
read -r MYSQL_USER
echo -n "Digite a senha do MySQL para backup: "
stty -echo
read -r MYSQL_PASSWORD
stty echo
echo ""

echo -n "Digite o usuário do MySQL root (ou equivalente): "
read -r MYSQL_ROOT_USER
echo -n "Digite a senha do MySQL root (ou equivalente): "
stty -echo
read -r MYSQL_ROOT_PASSWORD
stty echo
echo ""

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
wget https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb
sudo dpkg -i percona-release_latest.$(lsb_release -sc)_all.deb

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

echo_log "Backup concluído com sucesso!"
