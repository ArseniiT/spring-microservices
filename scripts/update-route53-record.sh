#!/bin/bash

set -e

# === configuration initiale ===
NOM_DOMAINE="greta25.click"
REGION="eu-west-3"
ALB_ZONE_ID="Z3Q77PNBQS71R4"  # identifiant HostedZone régional pour ALB dans eu-west-3

# === récupérer le nom du load balancer contenant "petclinic" ===
echo "récupération du nom du Load Balancer..."
ALB_NAME=$(aws elbv2 describe-load-balancers \
  --region $REGION \
  --query 'LoadBalancers[?contains(LoadBalancerName, `petclinic`)].LoadBalancerName' \
  --output text)

# === récupérer le nom DNS du load balancer ===
echo "récupération de l'adresse DNS du Load Balancer..."
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names $ALB_NAME \
  --region $REGION \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# === récupérer l'identifiant de la zone hébergée Route 53 ===
echo "récupération de l'identifiant de la zone Route 53..."
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name $NOM_DOMAINE \
  --query 'HostedZones[0].Id' \
  --output text | cut -d'/' -f3)

# === préparer le fichier JSON pour la mise à jour DNS ===
cat > change-record.json <<EOF
{
  "Comment": "mise à jour de l'enregistrement A pour pointer vers ALB",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$NOM_DOMAINE",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "$ALB_ZONE_ID",
        "DNSName": "dualstack.$ALB_DNS",
        "EvaluateTargetHealth": true
      }
    }
  }]
}
EOF

# === appliquer la modification à Route 53 ===
echo "mise à jour de l'enregistrement DNS A dans Route 53..."
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch file://change-record.json

echo "mise à jour terminée : $NOM_DOMAINE pointe maintenant vers $ALB_DNS"
