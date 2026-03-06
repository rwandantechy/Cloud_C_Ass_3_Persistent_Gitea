# Cloud Computing Assignment 3 — Persistent Gitea on EC2 (Docker + EBS + S3)

## What I Built

For this assignment, I deployed Gitea (a self-hosted Git service) on AWS using three main components:

1. **Docker Container** (the actual Gitea application) - the disposable part
2. **EBS Volume** (attached storage at `/data`) - where all the data lives permanently 
3. **S3 Bucket** - where daily backups are stored

The whole assignment was about proving that I understand how to separate the application from the data. If something goes wrong with the app, the data is still safe. Below is what I did.

---

## How I Did It

---

## Setup Requirements

Before starting, I had:
- Active AWS account with EC2 and S3 access
- EC2 instance running Ubuntu (t3.micro)
- Docker installed on the instance  
- AWS CLI configured
- Security group opened for ports 22 (SSH), 3000 (Gitea web), and 2222 (Git SSH)

---

## Part A: Setting Up Persistent Storage

The goal was to create an EBS volume that would hold all the Gitea data permanently, separate from the Docker container.

### A1 & A2: Created EC2 and EBS Volume

I created an Ubuntu EC2 instance (t3.micro) and a 30GB EBS volume in the same availability zone which us-east-b2 , Ohio, then attached it to the instance.

### A3 & A4: Formatted and Mounted

I SSH'd into the instance and formatted the volume, mounted it at `/data`, and made the mount permanent in `/etc/fstab`:

```bash
# See what disks are available
lsblk

# Format it (/dev/nvme1n1 on newer instances)
sudo mkfs -t ext4 /dev/nvme1n1

# Create a folder to mount it to
sudo mkdir -p /data

# Actually mount it
sudo mount /dev/nvme1n1 /data

# Get the UUID for fstab
sudo blkid /dev/nvme1n1

# Edit fstab and add this line (replace UUID with yours):
#  UUID="27c6b14a-f3d9-4b0d-af9e-3d131d14b10b" BLOCK_SIZE="4096" TYPE="ext4"

# Test that it works
sudo mount -a
df -h /data  # Should show the EBS volume mounted

---

## Part B: Running Gitea in Docker

The goal was to run Gitea in a Docker container with a bind mount to the EBS volume at `/data`, proving that data persists even if the container is deleted.

### B1: Installed Docker

I installed Docker and docker-compose on the EC2 instance:

```bash
sudo apt-get update && sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker
```

### B2 & B3: Created Docker Compose Config and Started Container

I created `docker-compose.yml`:

```yaml
services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: always
    ports:
      - "3000:3000"    # Web interface
      - "2222:22"      # Git over SSH  
    volumes:
      - /data/assignment3/gitea:/data  # Bind mount to EBS volume
```

Then started it:

```bash
sudo mkdir -p /data/assignment3/gitea
docker-compose up -d
```

### B4: Tested Data Persistence

This was the key test - I checked if data survives container deletion:

```bash
# Verify container is running
docker ps

# Delete the container completely
docker stop gitea && docker rm gitea

# Data is still there on the EBS volume
ls -la /data/assignment3/gitea/

# Start a new container
docker-compose up -d

# New container sees all the old data
docker exec gitea ls -la /data/
```

**Result**: All data persisted. Container is replaceable, data is permanent.

---

## Part C: Backing Up to S3

The final requirement was to create automated backups to S3 for disaster recovery.

### C1. Create an S3 Bucket

I created an S3 bucket to store my daily backups:

```bash
# Create a bucket (names have to be unique across ALL of AWS)
aws s3 mb s3://gitea-backup-assignment3 --region us-east-2
```

Then in the AWS console I:
- Turned ON versioning (keeps multiple versions)
- Turned ON encryption
- Made sure public access was blocked (security!)

### C2. The Backup Script

I created `backup.sh` that automates everything:

```bash
#!/bin/bash

DATE=$(date +%F)
BACKUP_FILE="gitea-backup-$DATE.tar.gz"

# Compress all the Gitea data
sudo tar -czvf $BACKUP_FILE /data/assignment3/gitea

# Upload to S3
aws s3 cp $BACKUP_FILE s3://gitea-backup-assignment3/

echo "Backup uploaded to S3"
```

Running it:
```bash
chmod +x backup.sh
./backup.sh  # Takes about 2-3 minutes
```

This compresses everything and uploads it automatically.

### C3. Verify It Worked

```bash
# List all my backups
aws s3 ls s3://gitea-backup-assignment3/

# Check one in detail
aws s3api head-object \
  --bucket gitea-backup-assignment3 \
  --key gitea-backup-2026-03-05.tar.gz
```

### C4. How to Restore (The Safety Net)

If everything broke, I could get it all back like this:

```bash
# 1. Download the backup from S3
aws s3 cp s3://gitea-backup-assignment3/gitea-backup-2026-03-05.tar.gz .

# 2. Stop the broken container
docker stop gitea

# 3. Extract the backup
sudo tar -xzvf gitea-backup-2026-03-05.tar.gz -C / --strip-components=3

# 4. Start a new container
docker start gitea

# 5. Everything is back!
```

I actually tested this - deliberately deleted data, restored it, and everything worked perfectly.

---

## What I Learned (And What This All Means)



1. **The app is disposable** - Docker container can break, can be replaced, no problem
2. **The data is eternal** - EBS volume keeps working no matter what
3. **Backups are essential** - S3 saves me from catastrophic failure

If my container crashes tomorrow, I can just:
- Spin up a new EC2 instance
- Attach the EBS volume 
- Start a new container
- Everything is exactly where I left it

### Before This Assignment

I thought Docker was the whole solution. But really Docker is just the app - the data needs its own home separate from the container.

