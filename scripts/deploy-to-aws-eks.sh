#!/bin/bash

# === Configuration ===
AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES=("admin-server" "api-gateway" "config-server" "discovery-server" "customers-service" "vets-service" "visits-service")
ECR_REPO_PREFIX="spring-petclinic"
LOCAL_PROJECT_PATH="$ROOT_DIR"

# Récupérer automatiquement l'identifiant du compte AWS
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Erreur: Impossible de récupérer l'identifiant du compte AWS. Vérifie la connexion AWS CLI."
  exit 1
fi

# Connexion à Amazon ECR
echo "Connexion à ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Boucle sur les services pour construire et pousser les images Docker
for SERVICE in "${SERVICES[@]}"; do
  echo "Traitement du service : $SERVICE"
  SERVICE_PATH="$LOCAL_PROJECT_PATH/spring-petclinic-$SERVICE"
  IMAGE_NAME="${SERVICE}"
  ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/${IMAGE_NAME}"

  # Créer le dépôt ECR si nécessaire
  echo "Vérification/création du dépôt ECR : $IMAGE_NAME"
  aws ecr describe-repositories --repository-names "${ECR_REPO_PREFIX}/${IMAGE_NAME}" --region $AWS_REGION > /dev/null 2>&1 || \
  aws ecr create-repository --repository-name "${ECR_REPO_PREFIX}/${IMAGE_NAME}" --region $AWS_REGION

  cd "$SERVICE_PATH"
  mvn clean package -DskipTests
  docker build -t "$IMAGE_NAME" .
  docker tag "$IMAGE_NAME:latest" "$ECR_REPO:latest"
  docker push "$ECR_REPO:latest"
done

# Vérifier si eksctl est installé
EKSCTL_EXISTS=$(which eksctl)
if [ -z "$EKSCTL_EXISTS" ]; then
  echo "eksctl est requis mais non trouvé. Installez-le avant de continuer."
  exit 1
fi

# Création du cluster EKS
echo "Création du cluster EKS..."
eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $AWS_REGION \
  --nodegroup-name linux-nodes \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed

# Configuration de kubectl pour utiliser le cluster
echo "Mise à jour du contexte kubectl..."
aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME

# Installation de ArgoCD
echo "Installation de ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Рécupération du mot de passe administrateur
echo "Attente 30 secondes pour que le secret soit créé..."
sleep 30

# Récupération du mot de passe administrateur
echo "Mot de passe initial pour ArgoCD :"
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo

# Lancer le script de configuration RDS
./setup-rds.sh