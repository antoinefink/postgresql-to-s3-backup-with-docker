# Easily backup Postgresql to S3 using Docker

[![Docker Repository on Quay](https://quay.io/repository/antoinefinkelstein/postgresql-to-s3-backup/status "Docker Repository on Quay")](https://quay.io/repository/antoinefinkelstein/postgresql-to-s3-backup)

As with every database, Postgresql needs to be backed up. To make it way more easier to maintain and install, **the entire script is running inside a docker container and will backup your Postgresql database to a S3 bucket**. It will work perfectly only with a few arguments. The only requirement is to have docker installed.

## Usage

If needed [install Docker](https://docs.docker.com/installation/). Then run the script with the following environment variables :

```
docker run --rm \
  -e AWS_SECRET_KEY='AWS Secret Key' \
  -e AWS_ACCESS_KEY='AWS Access Key' \
  -e DATABASE_IP='203.62.178.62' \
  -e DATABASE_PORT='5432' \
  -e DATABASE_NAME='myapp_production' \
  -e DATABASE_USERNAME='myapp' \
  -e DATABASE_PASSWORD='P455wOr0' \
  -e DESTINATION=mybucket/postgresql \
  quay.io/antoinefinkelstein/postgresql-to-s3-backup:9.4
```

**And that's it ! Your backup is done. :-)**

It's also possible to use the `S3_ENDPOINT` environment variable to upload the backup to DigitalOcean's spaces.

## Contributing

This script can get a lot better. Pull requests welcome !

To build the containers for different Postgresql versions, use build-arg:
```
docker build -t quay.io/antoinefinkelstein/postgresql-to-s3-backup:9.6 --build-arg VERSION=9.6 .
```
