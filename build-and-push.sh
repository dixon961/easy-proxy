#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Causes a pipeline to return the exit status of the last command in the pipe
# that returned a non-zero return value.
set -o pipefail

# --- Configuration ---
# Docker Hub username or your private registry's namespace/organization
# If using Docker Hub, this is your Docker Hub username.
# If using a private registry like GCR, ECR, etc., this might be a project ID or org name.
REGISTRY_USER_OR_NAMESPACE="dixon961" # Replace with your Docker Hub username or registry namespace

# Name of your image repository (the part after the username/namespace)
IMAGE_REPO_NAME="easy-proxy"

# Tag for your image
TAG="latest"

# The name of the service in your docker-compose.yml file that you want to build and push
# This service MUST have an 'image:' directive that matches FULL_IMAGE_NAME
# And it MUST have a 'build:' directive.
SERVICE_NAME_IN_COMPOSE="proxy" # This should match the service name in your docker-compose.yml

# Optional: Your private registry host (e.g., "myregistry.example.com", "gcr.io", "youraccount.dkr.ecr.region.amazonaws.com").
# Leave empty or comment out for Docker Hub.
# REGISTRY_HOST="your.private.registry.com"
REGISTRY_HOST="" # For Docker Hub, leave this empty

# --- Construct Full Image Name and Login Target ---
if [ -z "$REGISTRY_HOST" ]; then
  FULL_IMAGE_NAME="${REGISTRY_USER_OR_NAMESPACE}/${IMAGE_REPO_NAME}:${TAG}"
  LOGIN_TARGET="docker.io" # Default for Docker Hub, or can be omitted in docker login
else
  FULL_IMAGE_NAME="${REGISTRY_HOST}/${REGISTRY_USER_OR_NAMESPACE}/${IMAGE_REPO_NAME}:${TAG}"
  LOGIN_TARGET="${REGISTRY_HOST}"
fi

echo "---------------------------------------------------------------------"
echo "Script Configuration:"
echo "Service in docker-compose.yml: ${SERVICE_NAME_IN_COMPOSE}"
echo "Full Image Name to Build & Push: ${FULL_IMAGE_NAME}"
echo "Registry Host for login: ${LOGIN_TARGET}"
echo "---------------------------------------------------------------------"
echo "IMPORTANT: Ensure your docker-compose.yml for the service '${SERVICE_NAME_IN_COMPOSE}'"
echo "has the following line under its definition:"
echo "  image: ${FULL_IMAGE_NAME}"
echo "And that the 'build:' directive is also present for this service."
echo "---------------------------------------------------------------------"
# Optional: Add a confirmation prompt
# read -p "Press [Enter] to continue if the above is configured, or [Ctrl+C] to abort."

# 1. Build the Docker image using docker-compose
# docker-compose build will use the 'image:' tag specified in the docker-compose.yml
# for the service being built.
echo "[*] Building the Docker image for service '${SERVICE_NAME_IN_COMPOSE}' which will be tagged as '${FULL_IMAGE_NAME}'..."
docker compose build "${SERVICE_NAME_IN_COMPOSE}"

# Note: An explicit 'docker tag' command is NOT needed here because:
# 1. You've set the 'image: FULL_IMAGE_NAME' in your docker-compose.yml.
# 2. 'docker-compose build SERVICE_NAME_IN_COMPOSE' will build the image
#    and tag it directly with FULL_IMAGE_NAME.

# 2. Login to Docker Registry
echo "[*] Logging in to Docker registry '${LOGIN_TARGET}'..."
if [ -z "$REGISTRY_HOST" ]; then
    # For Docker Hub, you can just use `docker login` and it will prompt for username if not provided
    # or use the one from config.json. Providing username here is more explicit.
    docker login -u "${REGISTRY_USER_OR_NAMESPACE}" # Prompts for password
else
    # For private registries, 'docker login HOST' is typical. It might prompt or use existing credentials.
    docker login "${LOGIN_TARGET}"
fi
# If your registry login is more complex (e.g., ECR, GCR), you might need
# to replace the above with specific login commands like:
# aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account_id>.dkr.ecr.<region>.amazonaws.com
# gcloud auth configure-docker


# 3. Push the Docker image to the registry
echo "[*] Pushing the Docker image '${FULL_IMAGE_NAME}' to the registry..."
docker push "${FULL_IMAGE_NAME}"

echo "[*] Done!"
echo "[*] Image '${FULL_IMAGE_NAME}' should now be available in your registry."
