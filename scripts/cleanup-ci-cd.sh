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

  echo "- suppression des objets dans le bucket S3 ($BUCKET_NAME)..."
  aws s3api list-object-versions --bucket $BUCKET_NAME --output json 2>/dev/null \
    | jq -r '.Versions[]?, .DeleteMarkers[]? | [.Key, .VersionId] | @tsv' \
    | while IFS=$'\t' read -r key version_id; do
        aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" >/dev/null
      done && echo "  objets supprimés (si trouvés)."

  echo "- suppression du stack CloudFormation ($STACK_NAME)..."
  aws cloudformation delete-stack --stack-name $STACK_NAME
done

# nettoyage du pipeline global (application)
echo ""
echo "=== Nettoyage du pipeline global : application ==="

APP_STACK_NAME="application-ci-cd"

# récupération du nom réel du bucket créé dynamiquement
REAL_APP_BUCKET=$(aws cloudformation describe-stack-resources \
  --stack-name $APP_STACK_NAME \
  --region $AWS_REGION \
  --query "StackResources[?LogicalResourceId=='ArtifactStoreBucket'].PhysicalResourceId" \
  --output text)

if [ -n "$REAL_APP_BUCKET" ]; then
  echo "- suppression des objets dans le bucket S3 ($REAL_APP_BUCKET)..."
  aws s3api list-object-versions --bucket $REAL_APP_BUCKET --output json 2>/dev/null \
    | jq -r '.Versions[]?, .DeleteMarkers[]? | [.Key, .VersionId] | @tsv' \
    | while IFS=$'\t' read -r key version_id; do
        aws s3api delete-object --bucket "$REAL_APP_BUCKET" --key "$key" --version-id "$version_id" >/dev/null
      done && echo "  objets supprimés (si trouvés)."
else
  echo "Bucket non trouvé dans le stack CloudFormation $APP_STACK_NAME"
fi

echo "- suppression du stack CloudFormation ($APP_STACK_NAME)..."
aws cloudformation delete-stack --stack-name $APP_STACK_NAME

echo "attente de la suppression complète du stack global..."
aws cloudformation wait stack-delete-complete --stack-name $APP_STACK_NAME && echo "stack supprimé."

echo ""
echo "Tous les services et le pipeline global ont été nettoyés."
