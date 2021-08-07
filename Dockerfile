FROM ubuntu:16.04 
MAINTAINER Travis Moran

WORKDIR /root

RUN apt-get -y update && apt-get -y install  mysql-client bash python3 samba-client \
    python python-setuptools python3-dateutil python3-magic python3 \
    wget tar bash supervisor sqlite3 libsqlite3-dev && \
    rm -rf /var/cache/apk/*

COPY supervisord.conf /etc/supervisor/conf.d/myapp.conf
COPY s3cfg /root/.s3cfg
COPY entrypoint.sh /entrypoint.sh


RUN apt-get -y install s3cmd
RUN groupadd -g 999 mysql &&  useradd -u 999 -g 999 mysql 

CMD ["/usr/bin/supervisord", "-n"]
