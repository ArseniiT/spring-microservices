#!/bin/bash

# === paramètres globaux ===
AWS_REGION="eu-west-3"
ECR_REPO_PREFIX="spring-petclinic"
SERVICES=("admin-server" "api-gateway" "config-server" "discovery-server" "customers-service" "vets-service" "visits-service")

# récupérer l'ID du compte AWS
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# boucle sur chaque microservice
for SERVICE in "${SERVICES[@]}"; do
  echo ""
  echo "=== Nettoyage pour le service : $SERVICE ==="

  STACK_NAME="${SERVICE}-ci-cd"
  BUCKET_NAME="${SERVICE}-pipeline-artifacts"
  REPO_NAME="${ECR_REPO_PREFIX}/${SERVICE}"
  
  # suppression des images ECR
  # echo "- suppression des images dans ECR..."
  # IMAGE_IDS=$(aws ecr list-images \
  #   --region $AWS_REGION \
  #   --repository-name "$REPO_NAME" \
  #   --query 'imageIds[*]' \
  #   --output json)

  # if [[ "$IMAGE_IDS" != "[]" ]]; then
  #   aws ecr batch-delete-image \
  #     --region $AWS_REGION \
  #     --repository-name "$REPO_NAME" \
  #     --image-ids "$IMAGE_IDS" >/dev/null && echo "  images supprimées."
  # else
  #   echo "  aucune image à supprimer."
  # fi

  # suppression des objets S3
  echo "- suppression des objets dans le bucket S3 ($BUCKET_NAME)..."
  aws s3 rm s3://$BUCKET_NAME --recursive >/dev/null 2>&1 && echo "  objets supprimés (si trouvés)."

  # suppression du stack CloudFormation
  echo "- suppression du stack CloudFormation ($STACK_NAME)..."
  aws cloudformation delete-stack --stack-name $STACK_NAME
done

# nettoyage du pipeline global (application)
echo ""
echo "=== Nettoyage du pipeline global : application ==="

APP_STACK_NAME="application-ci-cd"
APP_BUCKET_NAME="application-pipeline-artifacts-${APP_STACK_NAME}"

# suppression du bucket S3 global
echo "- suppression des objets dans le bucket S3 ($APP_BUCKET_NAME)..."
aws s3 rm s3://$APP_BUCKET_NAME --recursive >/dev/null 2>&1 && echo "  objets supprimés (si trouvés)."

# suppression du stack CloudFormation global
echo "- suppression du stack CloudFormation ($APP_STACK_NAME)..."
aws cloudformation delete-stack --stack-name $APP_STACK_NAME

echo ""
echo "Tous les services et le pipeline global ont été nettoyés."
