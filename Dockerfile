FROM ubuntu:14.04

MAINTAINER Antoine Finkelstein <antoine@finkelstein.fr>

RUN apt-get update
RUN apt-get install -y wget

RUN wget -O- -q http://s3tools.org/repo/deb-all/stable/s3tools.key | sudo apt-key add -
RUN wget -O/etc/apt/sources.list.d/s3tools.list http://s3tools.org/repo/deb-all/stable/s3tools.list
RUN apt-get update
RUN apt-get install -y s3cmd

RUN apt-get install -y postgresql 
RUN apt-get install -y postgresql-contrib

# Define default command.
ADD startup.sh /startup.sh
RUN chmod +x /startup.sh

CMD ["/startup.sh"]
