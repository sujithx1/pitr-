FROM postgres:18

# Update package lists and install pgBackRest
RUN apt-get update && \
    apt-get install -y pgbackrest && \
    rm -rf /var/lib/apt/lists/*
