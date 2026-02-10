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

# Run the Cloud Build configuration to build both images
gcloud builds submit --config cloudrun/cloudbuild.yaml .
```

## Configure environment variables

Start from the provided `cloudrun/neon.env` settings and add Redis + URL settings.

```bash
# If you haven't already, copy neon.env to cloudrun.env (or just edit cloudrun/cloudrun.env directly)
cp cloudrun/neon.env cloudrun/cloudrun.env

# Add Redis configuration (if not already present)
echo "REDIS_HOST=your-redis-host" >> cloudrun/cloudrun.env
echo "REDIS_PORT=6379" >> cloudrun/cloudrun.env
echo "REDIS_PASSWORD=your-redis-password" >> cloudrun/cloudrun.env

# Add N8N URL configuration (Update these after first deployment generates the URL)
echo "N8N_EDITOR_BASE_URL=https://n8n-orchestrator-<hash>-uc.a.run.app" >> cloudrun/cloudrun.env
echo "WEBHOOK_URL=https://n8n-orchestrator-<hash>-uc.a.run.app" >> cloudrun/cloudrun.env
```

## Deploy the orchestrator

```bash
gcloud run services replace cloudrun/main-service.yaml \
  --project ${PROJECT_ID} \
  --region us-central1 \
  --env-vars-file cloudrun/cloudrun.env
```

## Deploy the workers (scale to zero)

```bash
gcloud run services replace cloudrun/worker-service.yaml \
  --project ${PROJECT_ID} \
  --region us-central1 \
  --env-vars-file cloudrun/cloudrun.env
```

## Custom Domain

To use a custom domain (e.g., `n8n.your-domain.com`):

1. Verify domain ownership in [Google Search Console](https://search.google.com/search-console).
2. Edit `cloudrun/deploy.sh` and uncomment/set the `CUSTOM_DOMAIN` variable:

    ```bash
    CUSTOM_DOMAIN="n8n.your-domain.com"
    ```

3. Run `./cloudrun/deploy.sh`. The script will attempt to map the domain and update the n8n configuration.
4. Configure your DNS records as instructed by the script output (usually adding a CNAME or A record).

Alternatively, map it manually:

```bash
gcloud beta run domain-mappings create --service n8n-orchestrator --domain n8n.your-domain.com --region us-central1
```

## Notes

- Ensure the Redis instance is reachable from Cloud Run. For Memorystore, use a Serverless VPC connector.
- The worker service is internal-only and can scale to zero.
- Queue mode requires the orchestrator and worker services to share the same Redis and Postgres configuration.

Refer to the n8n hosting documentation for deeper configuration details: <https://docs.n8n.io/hosting>
