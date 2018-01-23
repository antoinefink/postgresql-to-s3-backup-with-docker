FROM ubuntu:14.04

MAINTAINER Antoine Finkelstein <antoine@finkelstein.fr>

ENV S3_ENDPOINT s3.amazonaws.com

RUN apt-get update
RUN apt-get install -y wget curl

RUN apt-get install -y python-setuptools
RUN wget -qO- https://github.com/antoinefinkelstein/s3cmd-binary/raw/master/s3cmd-1.6.1.tar.gz | tar xvz
RUN cd s3cmd-1.6.1 && python setup.py install

RUN sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" >> /etc/apt/sources.list.d/pgdg.list'
RUN wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add -
RUN apt-get update

ADD startup.sh /startup.sh
RUN chmod +x /startup.sh
CMD ["/startup.sh"]

# Define the postgresql version
ARG VERSION
RUN apt-get install -y postgresql-$VERSION postgresql-contrib-$VERSION
