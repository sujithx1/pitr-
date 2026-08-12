# Production Database Image Build Guide

Since containers are ephemeral and can be deleted/recreated at any time by your company's systems, manually installing software inside a running container is dangerous (it gets erased on restart). 

The correct DevOps approach is to build your own custom Docker image that has `pgbackrest` permanently baked into it!

### Step 1: Build the Image
Open your terminal, navigate to this `18-prod` folder, and run this command:
```bash
docker build -t my-company-postgres-pitr:latest .
```
*(This downloads the standard `postgres:18` image your company uses, installs pgBackRest, and saves it on your computer as a brand new image named `my-company-postgres-pitr:latest`)*.

### Step 2: Update Your Company's `docker-compose.yml`
Now, go to your company's existing `docker-compose.yml` file. 
Find the database service, and change the `image:` line to point to your new image:

```yaml
services:
  db:
    # Remove this line:
    # image: postgres:18
    
    # Add this line instead:
    image: my-company-postgres-pitr:latest
    
    volumes:
      # Then just copy-paste the volume configurations from the lab here!
      - ./postgres/postgresql.conf:/etc/postgresql/postgresql.conf
      # ... etc
```

When your company runs `docker compose up`, it will boot using your custom image with the backup software permanently installed!
