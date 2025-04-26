#!/bin/bash

# ce script crée les dépôts ECR pour les microservices Spring Petclinic
#
# instructions pour utiliser ce script :
# 1. avant d'exécuter, exportez les variables d'environnement suivantes :
#    export AWS_ACCOUNT_ID=123456789012
#    export AWS_REGION=eu-west-3
# 2. rendez ce script exécutable :
#    chmod +x scripts/create-ecr-repositories.sh
# 3. exécutez-le depuis la racine du projet :
#    ./scripts/create-ecr-repositories.sh

# vérifier que les variables AWS_ACCOUNT_ID et AWS_REGION sont définies
if [ -z "$AWS_ACCOUNT_ID" ] || [ -z "$AWS_REGION" ]; then
  echo "erreur: veuillez définir les variables AWS_ACCOUNT_ID et AWS_REGION avant d'exécuter ce script"
  echo "exemple: export AWS_ACCOUNT_ID=123456789012"
  echo "exemple: export AWS_REGION=eu-west-3"
  exit 1
fi

# liste des microservices
services=(
  admin-server
  api-gateway
  config-server
  discovery-server
  customers-service
  vets-service
  visits-service
)

REPOSITORY_PREFIX="spring-petclinic"

for service in "${services[@]}"; do
  repo_name="${REPOSITORY_PREFIX}/${service}"
  
  echo "création du dépôt : $repo_name"

  # vérifier si le dépôt existe déjà
  if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" > /dev/null 2>&1; then
    aws ecr create-repository --repository-name "$repo_name" --region "$AWS_REGION"
    echo "dépôt $repo_name créé avec succès"
  else
    echo "le dépôt $repo_name existe déjà, aucune action"
  fi
done

echo "tous les dépôts sont prêts"
