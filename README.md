# PostgresSql Replication for Docker

We’ll start by creating the Master instance. This is what goes into the Dockerfile.

```FROM timescale/timescaledb-postgis:latest-pg13
	RUN  apk  add  --update  htop
	COPY  ./setup-master.sh  /docker-entrypoint-initdb.d/setup-master.sh
	RUN  chmod  0666  /docker-entrypoint-initdb.d/setup-master.sh
```

You’ll notice that there is a setup-master.sh file which needs to be copied to that image which makes the Postgres ready for being a master in the replication process.

```
#!/bin/bash

#allow connection with md5 encryption password

echo  "host replication all 0.0.0.0/0 md5"  >>  "$PGDATA/pg_hba.conf"

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"  <<-EOSQL

CREATE USER $PG_REP_USER REPLICATION LOGIN CONNECTION LIMIT 100 ENCRYPTED PASSWORD '$PG_REP_PASSWORD';

EOSQL

cat >>  ${PGDATA}/postgresql.conf <<EOF

listen_addresses = '*'

wal_level = replica

max_worker_processes = 23

max_locks_per_transaction = 1000

max_wal_senders = 8

max_replication_slots = 1

synchronous_commit = off

EOF
```

Now we need a Dockerfile for slave instances as well.

```
FROM  timescale/timescaledb-postgis:latest-pg13

ENV  GOSU_VERSION  1.10

ADD  ./gosu  /usr/bin/

RUN  chmod  +x  /usr/bin/gosu

RUN  apk  add  --update  iputils

RUN  apk  add  --update  htop

COPY  ./docker-entrypoint.sh  /docker-entrypoint.sh

RUN  chmod  +x  /docker-entrypoint.sh

ENTRYPOINT  ["/docker-entrypoint.sh"]

CMD  ["gosu",  "postgres",  "postgres"]
```

**\***We need the gosu binary to execute the postgres as root**\***

**We also need the `iputils` package to be able to ping the master. You’ll see in a bit.**

The next step is to prepare the slave images to actually be slaves. We use a `docker-entrypoin.sh` file which will be the first thing that docker execute upon creating the container.

```
#!/bin/bash

if  [  !  -s  "$PGDATA/PG_VERSION"  ];  then

echo  "*:*:*:$PG_REP_USER:$PG_REP_PASSWORD"  >  ~/.pgpass

chmod 0600 ~/.pgpass

until ping -c 1 -W 1 ${PG_MASTER_HOST:?missing environment variable. PG_MASTER_HOST must be set}

do

echo  "Waiting for master to ping..."

sleep 1s

done

until pg_basebackup -h ${PG_MASTER_HOST} -D ${PGDATA} -U ${PG_REP_USER} -vP -W

do

echo  "Waiting for master to connect..."

sleep 1s

done

echo -n >  "$PGDATA/standby.signal"

echo  "host replication all 0.0.0.0/0 md5"  >>  "$PGDATA/pg_hba.conf"

set -e

cat >  ${PGDATA}/postgresql.conf <<EOF

hot_standby = on

primary_conninfo = 'host=$PG_MASTER_HOST port=${PG_MASTER_PORT:-5432} user=$PG_REP_USER password=$PG_REP_PASSWORD'

max_worker_processes = 23

max_locks_per_transaction = 1000

wal_level = replica

max_wal_senders = 8

max_replication_slots = 2

synchronous_commit = off

EOF

chown postgres. ${PGDATA} -R

chmod 700 ${PGDATA} -R

fi

sed -i 's/wal_level = hot_standby/wal_level = replica/g'  ${PGDATA}/postgresql.conf

exec  "$@"
```

1. On the first line we check that this instance has already been set up or not by checking the `PG_VERSION` file in the `PG_DATA` path so as not to do it on every startup of the container.

2. We put the replication user and password in the `.pgpass` so postgres can access it.

3. We start pinging the Master to make sure that it’s already up and running.

4. And we put in the necessary configuration in place for the slave servers.

Ok, it’s almost done.

Now we need only to create a `docker-compose.yml` file to start our database containers.

```
version:  "3"

services:

pgAdmin:

restart:  always

image:  dpage/pgadmin4

ports:

-  "8000:80"

-  "443:443"

environment:

PGADMIN_DEFAULT_EMAIL:  ${PGADMIN_DEFAULT_EMAIL}

PGADMIN_DEFAULT_PASSWORD:  ${PGADMIN_DEFAULT_PASSWORD}

pg_master:

build:  ./master

volumes:

-  pg_data:/var/lib/postgresql/data

hostname:  pg_master

# ports:

# - "5432:5432"

environment:

POSTGRES_USER:  ${POSTGRES_USER}

POSTGRES_PASSWORD:  ${POSTGRES_PASSWORD}

POSTGRES_DB:  ${POSTGRES_DB}

PG_REP_USER:  ${PG_REP_USER}

PG_REP_PASSWORD:  ${PG_REP_PASSWORD}

networks:

default:

aliases:

-  pg_cluster

pg_slave:

build:  ./slave

hostname:  pg_slave

# ports:

# - "5433:5432"

environment:

POSTGRES_USER:  ${POSTGRES_USER}

POSTGRES_PASSWORD:  ${POSTGRES_PASSWORD}

POSTGRES_DB:  ${POSTGRES_DB}

PG_REP_USER:  ${PG_REP_USER}

PG_REP_PASSWORD:  ${PG_REP_PASSWORD}

PG_MASTER_HOST:  ${PG_MASTER_HOST}

networks:

default:

aliases:

-  pg_cluster

volumes:

pg_data:
```

Keep in mind that we have put the Dockerfile and `setup-master.sh` file the `master` directory and the slave’s Dockerfile and `docker-entrypoint.sh` and the `gosu` binary inside the `slave` directory.

We now have to run the this setup using docker compose:

`docker-compose up`

**Bonus:** If you have noticed we have set 2 network aliases `pg_master` and `pg_cluster` . In your application you can do the write operations on `pg_master` and the read operations on `pg_cluster` and docker will automatically route your requests to the correct container instance.
