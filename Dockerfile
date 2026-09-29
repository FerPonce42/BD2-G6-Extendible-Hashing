FROM postgres:18

RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-18 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . /app/

RUN make clean && make && make install