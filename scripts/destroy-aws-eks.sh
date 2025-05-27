#!/bin/bash

# === Script pour détruire l'infrastructure EKS, ArgoCD et tous les composants AWS associés ===

AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
ECR_REPO_PREFIX="spring-petclinic"
RDS_STACK_NAME="petclinic-rds"
SERVICES=("admin-server" "api-gateway" "config-server" "discovery-server" "customers-service" "vets-service" "visits-service")

# Récupérer l'ID de compte AWS
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "ATTENTION : Ce script va supprimer le cluster EKS \"$CLUSTER_NAME\", RDS, les images Docker, les dépôts ECR, les target groups, les NAT gateways, les security groups et les VPC."
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
kubectl config unset current-context 2>/dev/null

# === Suppression des dépôts et images ECR ===
for SERVICE in "${SERVICES[@]}"; do
  REPO_NAME="${ECR_REPO_PREFIX}/${SERVICE}"
  echo "Traitement du dépôt ECR : $REPO_NAME"

  IMAGE_TAGS=$(aws ecr list-images --repository-name "$REPO_NAME" --region $AWS_REGION --query 'imageIds[*]' --output json)

  if [[ "$IMAGE_TAGS" != "[]" ]]; then
    echo "  Suppression des images..."
    aws ecr batch-delete-image --repository-name "$REPO_NAME" --image-ids "$IMAGE_TAGS" --region $AWS_REGION
  else
    echo "  Aucun tag d'image à supprimer."
  fi

  echo "  Suppression du dépôt..."
  aws ecr delete-repository --repository-name "$REPO_NAME" --region $AWS_REGION --force
done

# === Suppression des stacks CloudFormation (RDS) ===
echo "Suppression du stack RDS CloudFormation ($RDS_STACK_NAME)..."
aws cloudformation delete-stack --stack-name $RDS_STACK_NAME --region $AWS_REGION

# === Nettoyage des Target Groups ===
echo "Suppression des Target Groups..."
for TG_ARN in $(aws elbv2 describe-target-groups --region $AWS_REGION --query 'TargetGroups[].TargetGroupArn' --output text); do
  echo "  Suppression du Target Group : $TG_ARN"
  aws elbv2 delete-target-group --target-group-arn $TG_ARN --region $AWS_REGION
done

# === Nettoyage des NAT Gateways ===
echo "Suppression des NAT Gateways..."
for NAT_ID in $(aws ec2 describe-nat-gateways --region $AWS_REGION --query 'NatGateways[].NatGatewayId' --output text); do
  echo "  Suppression du NAT Gateway : $NAT_ID"
  aws ec2 delete-nat-gateway --nat-gateway-id $NAT_ID --region $AWS_REGION
done

# === Nettoyage des Security Groups (hors default) ===
echo "Suppression des Security Groups..."
for SG_ID in $(aws ec2 describe-security-groups --region $AWS_REGION --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
  echo "  Suppression du Security Group : $SG_ID"
  aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION
done

# === Nettoyage des VPC (hors default) ===
echo "Suppression des VPC..."
for VPC_ID in $(aws ec2 describe-vpcs --region $AWS_REGION --query 'Vpcs[].VpcId' --output text); do
  echo "  Tentative de suppression de VPC : $VPC_ID"
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION || echo "  VPC $VPC_ID non supprimé (dépendances restantes)"
done

echo "Vérification finale des ressources restantes..."
echo "CloudFormation stacks encore existants :"
aws cloudformation list-stacks --region $AWS_REGION --query 'StackSummaries[?StackStatus != `DELETE_COMPLETE`].[StackName,StackStatus]' --output table

echo "Target Groups restants :"
aws elbv2 describe-target-groups --region $AWS_REGION --query 'TargetGroups[].TargetGroupArn'

echo "Security Groups restants :"
aws ec2 describe-security-groups --region $AWS_REGION --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]'

echo "NAT Gateways restants :"
aws ec2 describe-nat-gateways --region $AWS_REGION --query 'NatGateways[].NatGatewayId'

echo "VPC restants :"
aws ec2 describe-vpcs --region $AWS_REGION --query 'Vpcs[].VpcId'

echo "Script terminé."
