#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$SCRIPT_DIR/cloudrun.env"
REGION="us-central1"
CUSTOM_DOMAIN="n8n.xye.se"


# Export env vars from file
if [ -f "$ENV_FILE" ]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
else
    echo "Error: $ENV_FILE not found. Please create it from neon.env as described in the README."
    exit 1
fi

# Get Project ID
PROJECT_ID=$(gcloud config get-value project)
echo "Using Project ID: $PROJECT_ID"
echo "Region: $REGION"

# OPTIONAL: Set a custom domain (e.g., n8n.example.com)
# If set, the script will use this domain for N8N_EDITOR_BASE_URL and WEBHOOK_URL
# Make sure you have verified domain ownership in Google Search Console first.
# CUSTOM_DOMAIN="n8n.your-domain.com"

# Enable required APIs
echo "Enabling Cloud Build and Cloud Run APIs..."
gcloud services enable cloudbuild.googleapis.com run.googleapis.com

# Build Images
echo "Building container images..."
# Run build from root directory to include all files
cd "$ROOT_DIR"
gcloud builds submit --config "$SCRIPT_DIR/cloudbuild.yaml" .

# Deploy Orchestrator (Initial)
echo "Deploying Orchestrator (Initial pass)..."
# Render YAML with env vars
envsubst < "$SCRIPT_DIR/main-service.yaml" > "$SCRIPT_DIR/main-service.rendered.yaml"

gcloud run services replace "$SCRIPT_DIR/main-service.rendered.yaml" \
  --project "$PROJECT_ID" \
  --region "$REGION"

# Get Service URL
SERVICE_URL=$(gcloud run services describe n8n-orchestrator \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --format 'value(status.url)')

# Determine the base URL to use
if [ -n "$CUSTOM_DOMAIN" ]; then
    BASE_URL="https://$CUSTOM_DOMAIN"
    echo "Using Custom Domain URL: $BASE_URL"

    # Map the custom domain to the Cloud Run service (requires user interaction/verification if not already done)
    # This command maps the domain. It might ask for verification instructions.
    echo "Attempting to map domain $CUSTOM_DOMAIN to n8n-orchestrator..."
    # Note: This command is interactive or fails if domain is not verified.
    # Use || true to prevent script failure if mapping exists or fails validation.
    gcloud beta run domain-mappings create --service n8n-orchestrator --domain "$CUSTOM_DOMAIN" --region "$REGION" || true
else
    BASE_URL="$SERVICE_URL"
    echo "Using Cloud Run Service URL: $BASE_URL"
fi

# Update .env file with URL if not already set correctly
# We use a temporary file to avoid reading and writing to the same file at the same time
if grep -q "N8N_EDITOR_BASE_URL=" "$ENV_FILE"; then
    # Update existing keys
    sed -i "s|N8N_EDITOR_BASE_URL=.*|N8N_EDITOR_BASE_URL=$BASE_URL|g" "$ENV_FILE"
    sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=$BASE_URL|g" "$ENV_FILE"
else
    # Append if not present (though our template allows placeholders, so sed above handles it)
    echo "N8N_EDITOR_BASE_URL=$BASE_URL" >> "$ENV_FILE"
    echo "WEBHOOK_URL=$BASE_URL" >> "$ENV_FILE"
fi

echo "Updated $ENV_FILE with URL: $BASE_URL"

# Redeploy Orchestrator with new URLs
echo "Redeploying Orchestrator with updated configuration..."
# Re-export in case they changed
set -o allexport
source "$ENV_FILE"
set +o allexport

envsubst < "$SCRIPT_DIR/main-service.yaml" > "$SCRIPT_DIR/main-service.rendered.yaml"
gcloud run services replace "$SCRIPT_DIR/main-service.rendered.yaml" \
  --project "$PROJECT_ID" \
  --region "$REGION"

# Deploy Worker
echo "Deploying Worker..."
envsubst < "$SCRIPT_DIR/worker-service.yaml" > "$SCRIPT_DIR/worker-service.rendered.yaml"
gcloud run services replace "$SCRIPT_DIR/worker-service.rendered.yaml" \
  --project "$PROJECT_ID" \
  --region "$REGION"

# Cleanup
rm "$SCRIPT_DIR"/*.rendered.yaml

echo "Deployment complete!"
echo "n8n is running at: $SERVICE_URL"
