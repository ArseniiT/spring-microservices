#!/bin/bash

AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
STACK_NAME="petclinic-rds"
SECRET_NAME="dockerhub-credentials"

echo "Récupération du SecurityGroup ID pour EKS..."
SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=eksctl-${CLUSTER_NAME}-nodegroup-* \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region $AWS_REGION)

if [ -z "$SG_ID" ]; then
  echo "Erreur: Impossible de récupérer le SecurityGroup ID."
  exit 1
fi
echo "SecurityGroup ID: $SG_ID"

echo "Récupération des identifiants DB depuis Secrets Manager..."
DB_USER=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text | jq -r '.db_user')
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text | jq -r '.db_password')

if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Erreur: db_user ou db_password manquant dans le secret $SECRET_NAME."
  exit 1
fi

echo "Déploiement de RDS via CloudFormation..."
aws cloudformation deploy \
  --stack-name $STACK_NAME \
  --template-file infra/rds/rds-mysql.yaml \
  --region $AWS_REGION \
  --parameter-overrides VPCSecurityGroupId=$SG_ID DBMasterUsername=$DB_USER DBMasterUserPassword=$DB_PASSWORD

DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $AWS_REGION \
  --query "Stacks[0].Outputs[?OutputKey=='RDSInstanceEndpoint'].OutputValue" \
  --output text)

if [ -z "$DB_ENDPOINT" ]; then
  echo "Erreur: Impossible de récupérer l'endpoint RDS."
  exit 1
fi

echo "RDS Endpoint: $DB_ENDPOINT"

echo "Mise à jour du secret $SECRET_NAME (ajout db_host)..."
TEMP_FILE=$(mktemp)
aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text | jq '.' > $TEMP_FILE
UPDATED=$(jq --arg endpoint "$DB_ENDPOINT" '. + {"db_host":$endpoint}' $TEMP_FILE)
echo "$UPDATED" > $TEMP_FILE
aws secretsmanager update-secret --secret-id $SECRET_NAME --secret-string file://$TEMP_FILE
rm $TEMP_FILE

echo "RDS endpoint mis à jour dans le secret $SECRET_NAME"
