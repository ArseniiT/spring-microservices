#!/bin/bash

# === Script pour détruire l'infrastructure EKS, ArgoCD et les images Docker sur ECR ===

AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
ECR_REPO_PREFIX="spring-petclinic"
SERVICES=("admin-server" "api-gateway" "config-server" "discovery-server" "customers-service" "vets-service" "visits-service")

# Récupérer l'ID de compte AWS
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo " ATTENTION : Ce script va supprimer le cluster EKS \"$CLUSTER_NAME\", les images Docker et les dépôts ECR associés."
read -p "Es-tu sûr ? (Y/N) : " CONFIRM

if [[ "$CONFIRM" != "Y" ]]; then
  echo "Annulé."
  exit 0
fi

# === Suppression du cluster EKS ===
echo "Suppression du cluster EKS..."
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION

# Suppression du contexte kubectl
echo "Suppression du contexte kubectl local..."
kubectl config delete-cluster arn:aws:eks:$AWS_REGION:*:cluster/$CLUSTER_NAME 2>/dev/null
kubectl config delete-context arn:aws:eks:$AWS_REGION:*:cluster/$CLUSTER_NAME 2>/dev/null

# === Suppression des images Docker et des dépôts ECR ===
for SERVICE in "${SERVICES[@]}"; do
  REPO_NAME="${ECR_REPO_PREFIX}/${SERVICE}"
  echo "Traitement du dépôt ECR : $REPO_NAME"

  # Supprimer toutes les images du dépôt (si existent)
  IMAGE_TAGS=$(aws ecr list-images --repository-name "$REPO_NAME" --region $AWS_REGION --query 'imageIds[*]' --output json)
  
  if [[ "$IMAGE_TAGS" != "[]" ]]; then
    echo "  Suppression des images..."
    aws ecr batch-delete-image \
      --repository-name "$REPO_NAME" \
      --image-ids "$IMAGE_TAGS" \
      --region $AWS_REGION
  else
    echo "  Aucun tag d'image à supprimer."
  fi

  # Supprimer le dépôt ECR
  echo "  Suppression du dépôt..."
  aws ecr delete-repository --repository-name "$REPO_NAME" --region $AWS_REGION --force
done

echo " Tous les dépôts et images ECR ont été supprimés."
