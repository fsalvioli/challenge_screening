#!/bin/bash
# Backup de la base de screening
chmod +x scripts/backup.sh scripts/recovery.sh
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
docker exec screening_db pg_dump -U admin -d screening_system > ./backups/backup_$TIMESTAMP.sql
echo "Backup completado: backup_$TIMESTAMP.sql"