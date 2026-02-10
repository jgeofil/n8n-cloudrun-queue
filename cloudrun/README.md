# n8n on Cloud Run (Queue Mode)

This deployment follows the n8n queue mode architecture: a single **orchestrator** service handles the UI, webhooks, and scheduling, while **worker** services process jobs and scale to zero. The worker image installs Python to support Python-based automations and custom tooling.

## Architecture overview

- **n8n-orchestrator**: Public Cloud Run service. Runs the main n8n process and enqueues executions in Redis.
- **n8n-worker**: Internal Cloud Run service. Runs `n8n worker` and scales to zero when idle.
- **Redis**: Queue backend (use Memorystore for Redis or a managed Redis provider).
- **Postgres (Neon)**: Primary n8n database. Connection settings are in `neon.env`.

## Prerequisites

- GCP project with Cloud Run enabled.
- Redis instance reachable from Cloud Run.
- Neon database credentials stored in `neon.env`.

## Build images

```bash
export PROJECT_ID=your-gcp-project

gcloud builds submit \
  --tag gcr.io/${PROJECT_ID}/n8n-orchestrator:latest \
  --file deploy/cloudrun/Dockerfile.orchestrator .

gcloud builds submit \
  --tag gcr.io/${PROJECT_ID}/n8n-worker:latest \
  --file deploy/cloudrun/Dockerfile.worker .
```

## Configure environment variables

Start from the provided Neon settings and add Redis + URL settings.

```bash
cp deploy/cloudrun/neon.env deploy/cloudrun/cloudrun.env

echo "REDIS_HOST=your-redis-host" >> deploy/cloudrun/cloudrun.env
echo "REDIS_PORT=6379" >> deploy/cloudrun/cloudrun.env
echo "REDIS_PASSWORD=your-redis-password" >> deploy/cloudrun/cloudrun.env

echo "N8N_EDITOR_BASE_URL=https://n8n-orchestrator-<hash>-uc.a.run.app" >> deploy/cloudrun/cloudrun.env
echo "WEBHOOK_URL=https://n8n-orchestrator-<hash>-uc.a.run.app" >> deploy/cloudrun/cloudrun.env
```

## Deploy the orchestrator

```bash
gcloud run services replace deploy/cloudrun/main-service.yaml \
  --project ${PROJECT_ID} \
  --region us-central1 \
  --env-vars-file deploy/cloudrun/cloudrun.env
```

## Deploy the workers (scale to zero)

```bash
gcloud run services replace deploy/cloudrun/worker-service.yaml \
  --project ${PROJECT_ID} \
  --region us-central1 \
  --env-vars-file deploy/cloudrun/cloudrun.env
```

## Notes

- Ensure the Redis instance is reachable from Cloud Run. For Memorystore, use a Serverless VPC connector.
- The worker service is internal-only and can scale to zero.
- Queue mode requires the orchestrator and worker services to share the same Redis and Postgres configuration.

Refer to the n8n hosting documentation for deeper configuration details: https://docs.n8n.io/hosting
