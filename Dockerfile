FROM ubuntu:22.04

ENV S3_ENDPOINT s3.amazonaws.com

# Define the postgresql version first so it can be used in the RUN command
ARG VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    gnupg \
    lsb-release \
    s3cmd \
    cron \
    # Configure PostgreSQL APT repository
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    # Update again for the new repository and install postgresql-client
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client-${VERSION} \
    # Clean up
    && rm -rf /var/lib/apt/lists/*

ADD startup.sh /startup.sh
RUN chmod +x /startup.sh

CMD ["/startup.sh"]
