#!/bin/bash

# === Configuration ===
AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# On teste uniquement le service admin-server
SERVICES=("admin-server")
ECR_REPO_PREFIX="spring-petclinic"
LOCAL_PROJECT_PATH="$ROOT_DIR"

# Récupérer automatiquement l'identifiant du compte AWS
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Connexion à ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

for SERVICE in "${SERVICES[@]}"; do
  echo "Traitement du service : $SERVICE"
  SERVICE_PATH="${LOCAL_PROJECT_PATH}/spring-petclinic-${SERVICE}"
  IMAGE_NAME="${SERVICE}"
  ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/${IMAGE_NAME}"

  echo "Vérification ou création du dépôt ECR : $IMAGE_NAME"
  aws ecr describe-repositories --repository-names "${ECR_REPO_PREFIX}/${IMAGE_NAME}" --region $AWS_REGION > /dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${ECR_REPO_PREFIX}/${IMAGE_NAME}" --region $AWS_REGION

  cd "$SERVICE_PATH"
  mvn clean package
  docker build -t "$IMAGE_NAME" .
  docker tag "$IMAGE_NAME:latest" "$ECR_REPO:latest"
  docker push "$ECR_REPO:latest"
done
