#!/bin/bash

set -e

AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/application-codebuild-role"

echo "Ajout du rôle CodeBuild dans aws-auth..."

# Télécharger la config actuelle
kubectl get configmap aws-auth -n kube-system -o yaml > /tmp/aws-auth-full.yaml

# Vérifier s'il est déjà présent
if grep -q "$ROLE_ARN" /tmp/aws-auth-full.yaml; then
  echo "Le rôle $ROLE_ARN est déjà présent."
  exit 0
fi

# Insérer dans le bon bloc avec indentation correcte
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

# Appliquer le patch
kubectl apply -f /tmp/aws-auth-updated.yaml
echo "Rôle ajouté avec succès à aws-auth."
