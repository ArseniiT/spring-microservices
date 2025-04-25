#!/bin/bash

# ce script fusionne automatiquement les paramètres communs et spécifiques au service, puis déploie le stack CloudFormation
# ./deploy-cicd-with-merge.sh admin-server
# ./deploy-cicd-with-merge.sh api-gateway
# ./deploy-cicd-with-merge.sh config-server
# ./deploy-cicd-with-merge.sh discovery-server
# ./deploy-cicd-with-merge.sh customers-service
# ./deploy-cicd-with-merge.sh vets-service
# ./deploy-cicd-with-merge.sh visits-service


SERVICE=$1

if [ -z "$SERVICE" ]; then
  echo "Erreur: veuillez spécifier un nom de service, par exemple: ./deploy-with-merge.sh admin-server"
  exit 1
fi

COMMON_PARAMS="infra/ci-cd/params/common.params.json"
SERVICE_PARAMS="infra/ci-cd/params/${SERVICE}.params.json"
MERGED_PARAMS="/tmp/${SERVICE}-merged-params.json"

# vérifier si les fichiers existent
if [ ! -f "$COMMON_PARAMS" ]; then
  echo "Erreur: fichier $COMMON_PARAMS non trouvé."
  exit 1
fi

if [ ! -f "$SERVICE_PARAMS" ]; then
  echo "Erreur: fichier $SERVICE_PARAMS non trouvé."
  exit 1
fi

# fusionner avec jq
jq -s 'add' "$COMMON_PARAMS" "$SERVICE_PARAMS" > "$MERGED_PARAMS"

# déployer
aws cloudformation deploy \
  --template-file infra/ci-cd/ci-cd-pipeline.yaml \
  --stack-name "${SERVICE}-ci-cd" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides file://"$MERGED_PARAMS"
