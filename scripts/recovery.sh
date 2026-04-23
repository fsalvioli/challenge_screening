#!/bin/bash
# Restauración de la base
chmod +x scripts/backup.sh scripts/recovery.sh
FILE=$1
cat $FILE | docker exec -i screening_db psql -U admin -d screening_system
echo "Restauración finalizada desde $FILE"