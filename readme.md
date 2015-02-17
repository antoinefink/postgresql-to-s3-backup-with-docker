# Easily backup Postgresql to S3 using Docker

As with every database, Postgresql needs to be backed up. To make it way more easier to maintain and install, **the entire script is running inside a docker container and will backup your Postgresql database to a S3 bucket**. It will work perfectly only with a few arguments. The only requirement is to have docker installed.

## Usage

If needed [install Docker](https://docs.docker.com/installation/). Then run the script with the following environment variables :

```
docker run --rm \
  -e AWS_SECRET_KEY='AWS Secret Key' \
  -e AWS_ENCRYPTION_PASSWORD='AWS Encryption Password' \
  -e AWS_ACCESS_KEY='AWS Access Key' \
  -e DATABASE_IP='203.62.178.62' \
  -e DATABASE_PORT='5432' \
  -e DATABASE_NAME='myapp_production' \
  -e DATABASE_USERNAME='myapp' \
  -e DATABASE_PASSWORD='P455wOr0' \
  -e DESTINATION=mybucket/postgresql \
  antoinefinkelstein/postgresql-to-s3-backup
```

**And that's it ! Your backup is done. :-)**

## Contributing

This script can get a lot better. Pull requests welcome !