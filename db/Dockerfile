# postgres base is multi-arch, so this runs natively on Apple Silicon
FROM postgres:16
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postgresql-16-postgis-3 \
      postgresql-16-pgrouting \
 && rm -rf /var/lib/apt/lists/*
