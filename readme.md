# Easily backup PostgreSQL to S3 using Docker

Immediate or recurring backups of your Postgresql database to S3-compatible storage.

## Features

*   **Flexible Backup Modes**: Perform backups immediately on container run or schedule them periodically using cron.
*   **S3 Compatibility**: Works with AWS S3 and other S3-compatible services like Cloudflare R2.
*   **Configurable**: Customize backup frequency, S3 endpoint, and more through environment variables.
*   **PostgreSQL Version Support**: Build images for various PostgreSQL client versions (currently 15, 16, 17 via GitHub Actions).
*   **Secure**: Uses standard S3 authentication and PostgreSQL's `.pgpass` for passwordless connections within the container.

## Usage

First, ensure you have [Docker installed](https://docs.docker.com/installation/).

The image is hosted on GitHub Container Registry (GHCR): `ghcr.io/antoinefink/postgresql-to-s3-backup`. I recommand you fork this repository to host it yourself (it should be free on Github).

### Environment Variables

| Variable                  | Description                                                                                                 | Default         | Required |
| ------------------------- | ----------------------------------------------------------------------------------------------------------- | --------------- | -------- |
| `AWS_ACCESS_KEY`          | Your S3 access key.                                                                                         |                 | Yes      |
| `AWS_SECRET_KEY`          | Your S3 secret key.                                                                                         |                 | Yes      |
| `DATABASE_IP`             | IP address or hostname of your PostgreSQL server.                                                           |                 | Yes      |
| `DATABASE_PORT`           | Port number for your PostgreSQL server.                                                                     | `5432`          | Yes      |
| `DATABASE_NAME`           | Name of the database to backup.                                                                             |                 | Yes      |
| `DATABASE_USERNAME`       | Username to connect to the PostgreSQL database.                                                             |                 | Yes      |
| `DATABASE_PASSWORD`       | Password for the PostgreSQL user.                                                                           |                 | Yes      |
| `DESTINATION`             | S3 bucket and path for the backup (e.g., `mybucket/postgresql-backups`).                                     |                 | Yes      |
| `S3_ENDPOINT`             | S3 endpoint URL (e.g., `s3.amazonaws.com` or `nyc3.digitaloceanspaces.com`).                                | `s3.amazonaws.com` | No       |
| `BACKUP_MODE`             | Backup mode: `now` (backup immediately and exit) or `periodic` (run cron for scheduled backups).           | `now`           | No       |
| `BACKUP_CRON_SCHEDULE`    | Cron schedule for periodic backups (e.g., `"0 2 * * *"` for daily at 2 AM). Used if `BACKUP_MODE=periodic`. | `"0 0 * * *"`   | No       |
| `S3_MULTI_CHUNK_SIZE_MB`  | S3 multipart upload chunk size in MB.                                                                       | `100`           | No       |

### Example: Immediate Backup (Default)

This command will run the container, perform a backup immediately, and then the container will exit.
Replace `<PG_VERSION>` with the desired PostgreSQL client version (e.g., `16`).

```bash
docker run --rm \
  -e AWS_ACCESS_KEY='your_aws_access_key' \
  -e AWS_SECRET_KEY='your_aws_secret_key' \
  -e DATABASE_IP='your_db_host_or_ip' \
  -e DATABASE_PORT='5432' \
  -e DATABASE_NAME='your_database_name' \
  -e DATABASE_USERNAME='your_db_user' \
  -e DATABASE_PASSWORD='your_db_password' \
  -e DESTINATION='your_s3_bucket/path' \
  # -e S3_ENDPOINT='s3.region.amazonaws.com' # Optional: if not using default AWS S3 endpoint
  ghcr.io/antoinefink/postgresql-to-s3-backup:<PG_VERSION>
```

The backup file will be named like `your_database_name-YYYY-MM-DD_HH-MM-SS.dump`.

### Example: Periodic Backups (Daily at Midnight)

This command will start the container in periodic mode. It will set up a cron job to perform a backup daily at midnight (default schedule). The container will keep running to execute the cron jobs.

```bash
docker run -d --name postgresql-backup-scheduler \
  -e AWS_ACCESS_KEY='your_aws_access_key' \
  -e AWS_SECRET_KEY='your_aws_secret_key' \
  -e DATABASE_IP='your_db_host_or_ip' \
  -e DATABASE_PORT='5432' \
  -e DATABASE_NAME='your_database_name' \
  -e DATABASE_USERNAME='your_db_user' \
  -e DATABASE_PASSWORD='your_db_password' \
  -e DESTINATION='your_s3_bucket/path' \
  -e BACKUP_MODE='periodic' \
  # -e BACKUP_CRON_SCHEDULE="0 2 * * *" # Optional: to run daily at 2 AM instead of midnight
  # -e S3_ENDPOINT='s3.region.amazonaws.com' # Optional
  ghcr.io/antoinefink/postgresql-to-s3-backup:<PG_VERSION>
```

To view logs from the running container (including cron job output):
```bash
docker logs postgresql-backup-scheduler -f
```

Backup files will be named with a timestamp: `your_database_name-YYYY-MM-DD_HH-MM-SS.dump`.
