FROM timescale/timescaledb-postgis:latest-pg13

RUN apk add --update htop

COPY ./setup-master.sh /docker-entrypoint-initdb.d/setup-master.sh

RUN chmod 0666 /docker-entrypoint-initdb.d/setup-master.sh