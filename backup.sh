#!/bin/bash

DATE=$(date +%F)

BACKUP_FILE="gitea-backup-$DATE.tar.gz"

sudo tar -czvf $BACKUP_FILE /data/assignment3/gitea

aws s3 cp $BACKUP_FILE s3://gitea-backup-assignment3/

echo "Backup uploaded to S3"