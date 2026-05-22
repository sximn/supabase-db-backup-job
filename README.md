
# Puck

Simple backup UI to trigger database backups made for supabase.

## Why?

- why not use full pg_dump?
  - supabase has some internal schemas and tables (like auth, etc.) and they advise to not use a full db backup for easy restoration

- why not use supabase cli?
  - supabase promotes their `supabase db dump` which unfortunately requires docker (runs pg_dump in a container), which might be cumbersome in CI environments or simple backup cron jobs.

The reason is to not have a DinD setup for just a simple action of backing up the database.
The scripts are actually what `supabase db dump` would run (produced by supplying the --dry-run flag).

Also to have a nice UI with it.

## How to run

It is meant to run this as a docker container (see provided Dockerfile) but you can run it how you want.

### Test locally

Follow these commands to build and run a local docker container.

local build
```
docker build -t supabase-backup-ui:local .
```


run locally
```
docker run -d \
  --name supabase-backup-service \
  --env-file .env.example \
  -p 3000:3000 \
  -v "$(pwd)/local_backups:/backups" \
  supabase-backup-ui:local
```


stream in the container logs
```
docker logs -f supabase-backup-service
```

teardown the running container
```
docker rm -f supabase-backup-service
```