FROM postgres:15

RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-15 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . /app/

RUN make clean && make && make install
