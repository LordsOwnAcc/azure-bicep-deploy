#!/usr/bin/env bash
# Two-phase deploy. Usage: ./deploy.sh you@example.com
set -euo pipefail

EMAIL="${1:?usage: ./deploy.sh <alert-email>}"
LOCATION="centralindia"
PREFIX="bicepdemo"
TAG="v$(date +%Y%m%d%H%M%S)"

echo ">> Validate + preview (what-if)"
az bicep build --file infra/main.bicep --stdout >/dev/null
az deployment sub what-if -l "$LOCATION" -f infra/main.bicep \
  -p location="$LOCATION" prefix="$PREFIX" alertEmail="$EMAIL"

echo ">> Phase 1: infra with placeholder image"
az deployment sub create -n "$PREFIX-infra" -l "$LOCATION" -f infra/main.bicep \
  -p location="$LOCATION" prefix="$PREFIX" alertEmail="$EMAIL"

ACR_NAME=$(az deployment sub show -n "$PREFIX-infra" --query properties.outputs.acrName.value -o tsv)
ACR_SERVER=$(az deployment sub show -n "$PREFIX-infra" --query properties.outputs.acrLoginServer.value -o tsv)

echo ">> Build image in ACR (no local Docker needed)"
az acr build -r "$ACR_NAME" -t "api:$TAG" ./app

echo ">> Phase 2: switch app to our image (same template, new params)"
az deployment sub create -n "$PREFIX-app" -l "$LOCATION" -f infra/main.bicep \
  -p location="$LOCATION" prefix="$PREFIX" alertEmail="$EMAIL" \
     image="$ACR_SERVER/api:$TAG" targetPort=8080

URL=$(az deployment sub show -n "$PREFIX-app" --query properties.outputs.appUrl.value -o tsv)
echo ">> Done: $URL"
curl -fsS "$URL/health" && echo
