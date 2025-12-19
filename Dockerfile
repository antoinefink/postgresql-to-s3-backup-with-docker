FROM ubuntu:24.04

# Define the postgresql version first so it can be used in the RUN command
ARG VERSION
# TARGETARCH is automatically set by Docker Buildx (amd64, arm64, etc.)
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  wget \
  curl \
  gnupg \
  lsb-release \
  unzip \
  cron \
  python3 \
  # Install AWS CLI v2 with signature verification
  # Map Docker arch names to AWS CLI arch names: amd64 -> x86_64, arm64 -> aarch64
  # Fall back to uname -m if TARGETARCH is not set (e.g., building without buildx)
  && ARCH="${TARGETARCH:-$(uname -m)}" \
  && case "$ARCH" in arm64|aarch64) AWS_CLI_ARCH="aarch64" ;; *) AWS_CLI_ARCH="x86_64" ;; esac \
  && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_CLI_ARCH}.zip" -o "awscliv2.zip" \
  && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_CLI_ARCH}.zip.sig" -o "awscliv2.zip.sig" \
  && curl -fsSL "https://d1vvhvl2y92vvt.cloudfront.net/awscli-public-key.gpg" -o "aws-cli-public-key.gpg" \
  && gpg --import aws-cli-public-key.gpg \
  && gpg --verify awscliv2.zip.sig awscliv2.zip \
  && unzip awscliv2.zip \
  && ./aws/install \
  && rm -rf aws awscliv2.zip awscliv2.zip.sig aws-cli-public-key.gpg \
  # Configure PostgreSQL APT repository
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
  # Update again for the new repository and install postgresql-client
  && apt-get update \
  && apt-get install -y --no-install-recommends postgresql-client-${VERSION} \
  # Clean up
  && rm -rf /var/lib/apt/lists/* /root/.gnupg

ADD startup.sh /startup.sh
RUN chmod +x /startup.sh

CMD ["/startup.sh"]
