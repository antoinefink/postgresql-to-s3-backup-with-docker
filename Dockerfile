FROM ubuntu:24.04

# Define the postgresql version first so it can be used in the RUN command
ARG VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  wget \
  curl \
  gnupg \
  lsb-release \
  unzip \
  cron \
  # Install AWS CLI v2
  && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
  && unzip awscliv2.zip \
  && ./aws/install \
  && rm -rf aws awscliv2.zip \
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
