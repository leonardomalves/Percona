#!/bin/bash

set -e  # Para interromper o script em caso de erro
set -u  # Para evitar variáveis não definidas

SYSTEM_USER=${SUDO_USER:-$USER}
LOG_FILE="/var/log/percona_xtrabackup_restore.log"
RESTORE_DIR="/home/$SYSTEM_USER/percona/restore"

# Função para logging
echo_log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

./install.sh

# Solicitar a URI completa do backup no S3
echo -n "Digite a URI completa do backup no S3 (ex: s3://exemplo/bucket/backup_20250214_135620.tar.gz): "
read -r S3_URI

echo_log "Backup selecionado: $S3_URI"

# Criar diretório de restauração
echo_log "Criando diretório de restauração..."
mkdir -p "$RESTORE_DIR"

# Baixar backup
echo_log "Baixando backup do S3..."
aws s3 cp "$S3_URI" "$RESTORE_DIR/$(basename "$S3_URI")"

echo_log "Extraindo backup..."
tar -xzf "$RESTORE_DIR/$(basename "$S3_URI")" -C "$RESTORE_DIR"

# Parar MySQL antes de restaurar
echo_log "Parando serviço MySQL..."
sudo systemctl stop mysql

# Se o diretório /var/lib/mysql existir, renomear
if [ -d "/var/lib/mysql" ]; then
  echo_log "Diretório /var/lib/mysql já existe, renomeando..."
  sudo mv /var/lib/mysql /var/lib/mysql_old_$(date +'%Y%m%d_%H%M%S')
fi

# Criar novamente o /var/lib/mysql vazio
sudo mkdir /var/lib/mysql
sudo chown mysql:mysql /var/lib/mysql

# Preparar e mover o backup
echo_log "Preparando backup com Percona XtraBackup..."
sudo xtrabackup --prepare --target-dir="$RESTORE_DIR"

echo_log "Movendo dados para /var/lib/mysql..."
sudo xtrabackup --move-back --target-dir="$RESTORE_DIR" --datadir=/var/lib/mysql
sudo chown -R mysql:mysql /var/lib/mysql

echo_log "Iniciando serviço MySQL..."
sudo systemctl start mysql

echo_log "Restauração concluída com sucesso!"
