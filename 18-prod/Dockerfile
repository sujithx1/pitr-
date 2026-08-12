FROM postgres:18

# Update package lists and install pgBackRest using Debian's apt-get
# We clean up the apt cache at the end to keep the image size small
RUN apt-get update && \
    apt-get install -y pgbackrest && \
    rm -rf /var/lib/apt/lists/*
