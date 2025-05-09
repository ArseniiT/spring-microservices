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
  BUCKET_PREFIX="${SERVICE}-pipeline-artifacts"

  # suppression des objets S3 (par préfixe)
  echo "- recherche et suppression des buckets commençant par $BUCKET_PREFIX..."
  for BUCKET in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
    if [[ "$BUCKET" == $BUCKET_PREFIX* ]]; then
      echo "  suppression du bucket $BUCKET..."
      aws s3 rb s3://$BUCKET --force || echo "  impossible de supprimer $BUCKET"
    fi
  done

  # suppression du stack CloudFormation
  echo "- suppression du stack CloudFormation ($STACK_NAME)..."
  aws cloudformation delete-stack --stack-name $STACK_NAME
done

# nettoyage du pipeline global (application)
echo ""
echo "=== Nettoyage du pipeline global : application ==="

APP_STACK_NAME="application-ci-cd"
APP_BUCKET_PREFIX="application-ci-cd-artifactstorebucket"

# suppression du bucket S3 global par préfixe
echo "- recherche et suppression des buckets commençant par $APP_BUCKET_PREFIX..."
for BUCKET in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
  if [[ "$BUCKET" == $APP_BUCKET_PREFIX* ]]; then
    echo "  suppression du bucket $BUCKET..."
    aws s3 rb s3://$BUCKET --force || echo "  impossible de supprimer $BUCKET"
  fi
done

# suppression du stack CloudFormation global
echo "- suppression du stack CloudFormation ($APP_STACK_NAME)..."
aws cloudformation delete-stack --stack-name $APP_STACK_NAME

echo "attente de la suppression complète du stack global..."
aws cloudformation wait stack-delete-complete --stack-name $APP_STACK_NAME || echo "stack déjà supprimé."

echo ""
echo "Tous les services et le pipeline global ont été nettoyés."