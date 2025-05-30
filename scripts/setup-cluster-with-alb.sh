#!/bin/bash

set -e

AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.identity.oidc.issuer" --output text | awk -F '/' '{print $NF}')
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SERVICE_ACCOUNT_NAMESPACE="kube-system"
SERVICE_ACCOUNT_NAME="aws-load-balancer-controller"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"

# --- Associer le fournisseur OIDC
eksctl utils associate-iam-oidc-provider \
  --region $AWS_REGION \
  --cluster $CLUSTER_NAME \
  --approve

# --- Créer la politique IAM pour ALB Controller
echo "Création de la politique IAM pour ALB controller..."
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy \
  --region $AWS_REGION \
  --policy-name $POLICY_NAME \
  --policy-document file://iam_policy.json || echo "La politique existe déjà."

# --- Créer le service account IAM
echo "Création du service account pour ALB controller..."
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --namespace $SERVICE_ACCOUNT_NAMESPACE \
  --name $SERVICE_ACCOUNT_NAME \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME \
  --approve \
  --override-existing-serviceaccounts

# --- Installer AWS Load Balancer Controller
echo "Installation du contrôleur ALB..."
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"
helm repo add eks https://aws.github.io/eks-charts || true
helm repo update
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set region=$AWS_REGION \
  --set vpcId=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query "cluster.resourcesVpcConfig.vpcId" --output text) \
  --set serviceAccount.create=false \
  --set serviceAccount.name=$SERVICE_ACCOUNT_NAME \
  --set image.repository=602401143452.dkr.ecr.${AWS_REGION}.amazonaws.com/amazon/aws-load-balancer-controller

# --- External Secrets Operator
EXTERNAL_SECRETS_POLICY_NAME="ExternalSecretsAccessPolicy"
EXTERNAL_SECRETS_SA_NAME="external-secrets"

echo "Création de la politique IAM pour External Secrets..."
aws iam create-policy \
  --region $AWS_REGION \
  --policy-name $EXTERNAL_SECRETS_POLICY_NAME \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue"],
        "Resource": "*"
      }
    ]
  }' || echo "La politique existe déjà."

echo "Création du service account pour External Secrets..."
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --region $AWS_REGION \
  --namespace external-secrets \
  --name $EXTERNAL_SECRETS_SA_NAME \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$EXTERNAL_SECRETS_POLICY_NAME \
  --approve \
  --override-existing-serviceaccounts

# --- Installer les CRD pour External Secrets Operator
# echo "Installation des CRD pour External Secrets..."
# kubectl apply -f https://raw.githubusercontent.com/external-secrets/external-secrets/v0.17.0/deploy/crds/bundle.yaml

# --- Installer External Secrets Operator
echo "Installation de l'opérateur External Secrets..."
kubectl create namespace external-secrets || true
helm repo add external-secrets https://charts.external-secrets.io || true
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --set installCRDs=true \
  --set serviceAccount.name=$EXTERNAL_SECRETS_SA_NAME \
  --set serviceAccount.create=false

# --- Attendre que les CRD soient installés
echo "Attente de l'installation des CRD..."
for i in {1..10}; do
  if kubectl get crd clustersecretstores.external-secrets.io &>/dev/null; then
    echo "CRD ClusterSecretStore est prêt."
    break
  else
    echo "En attente... ($i/10)"
    sleep 6
  fi
done

echo "Attente que tous les pods External Secrets soient disponibles..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=external-secrets -n external-secrets --timeout=120s || true

echo "Application des RBAC pour External Secrets..."
kubectl apply -f "$ROOT_DIR/infra/secrets/external-secrets-rbac.yaml"

# --- Attendre que le webhook d'External Secrets soit prêt
echo "Attente que le webhook external-secrets-webhook soit prêt..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=external-secrets-webhook -n external-secrets --timeout=60s

echo "Application des fichiers YAML pour External Secrets..."
kubectl apply -f "$ROOT_DIR/infra/secrets/clustersecretstore.yaml"
kubectl apply -f "$ROOT_DIR/infra/secrets/dockerhub-externalsecret.yaml"

# --- Attente de la création du secret
echo "Attente de la création du secret dockerhub-credentials..."
for i in {1..10}; do
  if kubectl get secret dockerhub-credentials -n default &>/dev/null; then
    echo "Le secret dockerhub-credentials est prêt."
    break
  else
    echo "En attente... ($i/10)"
    sleep 6
  fi
done

# --- Vérification finale
kubectl get secret dockerhub-credentials -n default || echo "Le secret dockerhub-credentials n'est pas encore disponible."

# --- Ajout automatique du rôle CodeBuild dans aws-auth (méthode sûre)
echo "Ajout du rôle CodeBuild dans aws-auth..."
ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/application-codebuild-role"

kubectl get configmap aws-auth -n kube-system -o yaml > /tmp/aws-auth-full.yaml

if grep -q "$ROLE_ARN" /tmp/aws-auth-full.yaml; then
  echo "Le rôle $ROLE_ARN est déjà présent."
else
  echo "Ajout du rôle..."
  awk -v rolearn="$ROLE_ARN" '
    /^  mapRoles: \|/ {
      print
      print "    - rolearn: " rolearn
      print "      username: codebuild"
      print "      groups:"
      print "        - system:masters"
      next
    }
    { print }
  ' /tmp/aws-auth-full.yaml > /tmp/aws-auth-updated.yaml

  kubectl apply -f /tmp/aws-auth-updated.yaml
  echo "Rôle ajouté avec succès à aws-auth."
fi
