#!/bin/bash

# ce script fusionne automatiquement les paramètres communs et spécifiques au service,
# remplace les variables (AWSAccountId, AWSRegion) et déploie le stack CloudFormation

# ./deploy-cicd-with-merge.sh admin-server
# ./deploy-cicd-with-merge.sh api-gateway
# ./deploy-cicd-with-merge.sh config-server
# ./deploy-cicd-with-merge.sh discovery-server
# ./deploy-cicd-with-merge.sh customers-service
# ./deploy-cicd-with-merge.sh vets-service
# ./deploy-cicd-with-merge.sh visits-service

# ./deploy-cicd-with-merge.sh application

SERVICE=$1

if [ -z "$SERVICE" ]; then
  echo "Erreur: veuillez spécifier un nom de service, par exemple: ./deploy-cicd-with-merge.sh admin-server"
  exit 1
fi

# déterminer le chemin absolu vers la racine du projet
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

COMMON_PARAMS="$PROJECT_ROOT/infra/ci-cd/params/common.params.json"
SERVICE_PARAMS="$PROJECT_ROOT/infra/ci-cd/params/${SERVICE}.params.json"
MERGED_PARAMS="/tmp/${SERVICE}-merged-params.json"

# vérifier que jq est installé
if ! command -v jq &> /dev/null; then
  echo "Erreur: jq n’est pas installé. Utilisez 'sudo apt install jq' pour l’installer."
  exit 1
fi

# vérifier si les fichiers existent
if [ ! -f "$COMMON_PARAMS" ]; then
  echo "Erreur: fichier $COMMON_PARAMS non trouvé."
  exit 1
fi

if [ ! -f "$SERVICE_PARAMS" ]; then
  echo "Erreur: fichier $SERVICE_PARAMS non trouvé."
  exit 1
fi

# extraire les valeurs AWSAccountId et AWSRegion
 AWS_ACCOUNT_ID=$(jq -r '.Parameters.AWSAccountId' "$COMMON_PARAMS")
 AWS_REGION=$(jq -r '.Parameters.AWSRegion' "$COMMON_PARAMS")
 
 # fusionner les paramètres + remplacer les placeholders
 jq -s '
   .[0].Parameters * .[1].Parameters
   | to_entries
   | map({
       ParameterKey: .key,
       ParameterValue: (.value
         | tostring
         | gsub("\\$\\{AWSAccountId\\}"; "'"$AWS_ACCOUNT_ID"'")
         | gsub("\\$\\{AWSRegion\\}"; "'"$AWS_REGION"'"))
     })
 ' "$COMMON_PARAMS" "$SERVICE_PARAMS" > "$MERGED_PARAMS"

# déployer
aws cloudformation deploy \
  --template-file "$PROJECT_ROOT/infra/ci-cd/ci-cd-pipeline.yaml" \
  --stack-name "${SERVICE}-ci-cd" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides file://"$MERGED_PARAMS"
