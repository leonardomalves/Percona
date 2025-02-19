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
S3_BUCKET="$S3_BUCKET"
S3_FOLDER="$S3_FOLDER"
SCHEMA="$SCHEMA"
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

# Solicitar informações do S3 se não estiverem configuradas
echo -n "Digite o nome do bucket S3 [${S3_BUCKET:-não definido}]: "
read -r input
if [[ -n "$input" ]]; then
    S3_BUCKET="$input"
fi

echo -n "Digite a pasta no S3 [${S3_FOLDER:-não definido}]: "
read -r input
if [[ -n "$input" ]]; then
    S3_FOLDER="$input"
fi

echo -n "Digite o esquema do backup [${SCHEMA:-não definido}]: "
read -r input
if [[ -n "$input" ]]; then
    SCHEMA="$input"
fi

# Salvar configurações atualizadas
save_config

# Função para logging
echo_log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Criando usuário de backup no MySQL
echo_log "Configurando usuário de backup no MySQL..."
mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

# Criando diretório de backup
echo_log "Criando diretório de backup..."
mkdir -p "$BACKUP_DIR"
./install.sh

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

RETRY=5
for ((i=1; i<=RETRY; i++)); do
    echo "Tentativa $i de envio para S3..."
    aws s3 cp "$TAR_FILE" s3://$S3_BUCKET/$S3_FOLDER/$SCHEMA/ --sse AES256 && break
    sleep 10
    if [ $i -eq $RETRY ]; then
        echo "Erro ao enviar backup para o S3"
        exit 1
    fi
done