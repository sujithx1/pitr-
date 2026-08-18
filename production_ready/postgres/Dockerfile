FROM postgres:18

# Install pgBackRest backup agent permanently in production image
RUN apt-get update && \
    apt-get install -y pgbackrest && \
    rm -rf /var/lib/apt/lists/*
