#!/bin/bash

# === Script amélioré pour détruire complètement l'infrastructure EKS et tous les composants AWS ===

AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
ECR_REPO_PREFIX="spring-petclinic"
RDS_STACK_NAME="petclinic-rds"
SERVICES=("admin-server" "api-gateway" "config-server" "discovery-server" "customers-service" "vets-service" "visits-service")

# Récupérer l'ID de compte AWS
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "ATTENTION : Ce script va supprimer COMPLÈTEMENT toute l'infrastructure AWS liée au projet Petclinic"
echo "- Cluster EKS: $CLUSTER_NAME"
echo "- Tous les dépôts ECR avec le préfixe: $ECR_REPO_PREFIX"
echo "- Stack RDS: $RDS_STACK_NAME"
echo "- Load Balancers, Target Groups, NAT Gateways, Internet Gateways"
echo "- Security Groups et VPC non-default"
echo "- Tous les stacks CloudFormation liés"
echo ""
read -p "Es-tu absolument sûr de vouloir continuer ? (tapez 'SUPPRIMER' pour confirmer) : " CONFIRM

if [[ "$CONFIRM" != "SUPPRIMER" ]]; then
  echo "Opération annulée."
  exit 0
fi

# Fonction pour attendre la suppression d'un stack CloudFormation
wait_for_stack_deletion() {
    local stack_name=$1
    echo "Attente de la suppression du stack $stack_name..."
    aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region $AWS_REGION 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Stack $stack_name supprimé avec succès"
    else
        echo "Timeout ou erreur lors de la suppression du stack $stack_name"
    fi
}

# === 1. Suppression forcée du cluster EKS ===
echo "=== Étape 1: Suppression du cluster EKS ==="
if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &>/dev/null; then
    echo "Cluster EKS trouvé, suppression en cours..."
    eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION --wait --force
    
    # Attendre un peu pour que les ressources soient libérées
    echo "Attente de 30 secondes pour la libération des ressources..."
    sleep 30
else
    echo "Cluster EKS $CLUSTER_NAME non trouvé, passage à l'étape suivante"
fi

# Suppression des contextes kubectl
echo "Nettoyage des contextes kubectl locaux..."
kubectl config get-contexts -o name | grep -E "(eks|$CLUSTER_NAME)" | xargs -r kubectl config delete-context 2>/dev/null
kubectl config get-clusters | grep -E "(eks|$CLUSTER_NAME)" | xargs -r kubectl config delete-cluster 2>/dev/null

# === 2. Suppression des Load Balancers et Target Groups ===
echo "=== Étape 2: Suppression des Load Balancers ==="
for lb_arn in $(aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null); do
    if [ ! -z "$lb_arn" ]; then
        echo "Suppression du Load Balancer: $lb_arn"
        aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region $AWS_REGION
    fi
done

echo "Suppression des Target Groups..."
for tg_arn in $(aws elbv2 describe-target-groups --region $AWS_REGION --query 'TargetGroups[].TargetGroupArn' --output text 2>/dev/null); do
    if [ ! -z "$tg_arn" ]; then
        echo "Suppression du Target Group: $tg_arn"
        aws elbv2 delete-target-group --target-group-arn "$tg_arn" --region $AWS_REGION 2>/dev/null
    fi
done

# === 3. Suppression des stacks CloudFormation ===
echo "=== Étape 3: Suppression des stacks CloudFormation ==="

# Lister tous les stacks non supprimés
EXISTING_STACKS=$(aws cloudformation list-stacks --region $AWS_REGION --query 'StackSummaries[?StackStatus != `DELETE_COMPLETE`].StackName' --output text)

for stack_name in $EXISTING_STACKS; do
    if [[ "$stack_name" == *"$CLUSTER_NAME"* ]] || [[ "$stack_name" == "$RDS_STACK_NAME" ]] || [[ "$stack_name" == *"petclinic"* ]]; then
        echo "Suppression du stack CloudFormation: $stack_name"
        aws cloudformation delete-stack --stack-name "$stack_name" --region $AWS_REGION
        
        # Pour les stacks EKS, forcer la suppression si nécessaire
        if [[ "$stack_name" == *"eksctl"* ]]; then
            echo "Attente de 60 secondes puis vérification du statut du stack EKS..."
            sleep 60
            
            STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region $AWS_REGION --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
            if [[ "$STACK_STATUS" == "DELETE_FAILED" ]]; then
                echo "Stack en échec, tentative de nettoyage des ressources bloquantes..."
                
                # Supprimer les ressources qui peuvent bloquer
                aws ec2 describe-security-groups --region $AWS_REGION --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" --query 'SecurityGroups[].GroupId' --output text | xargs -r -n1 aws ec2 delete-security-group --group-id --region $AWS_REGION 2>/dev/null
                
                echo "Nouvel essai de suppression du stack..."
                aws cloudformation delete-stack --stack-name "$stack_name" --region $AWS_REGION
            fi
        fi
    fi
done

# === 4. Suppression des dépôts ECR ===
echo "=== Étape 4: Suppression des dépôts ECR ==="
for SERVICE in "${SERVICES[@]}"; do
    REPO_NAME="${ECR_REPO_PREFIX}/${SERVICE}"
    echo "Traitement du dépôt ECR: $REPO_NAME"
    
    # Vérifier si le dépôt existe
    if aws ecr describe-repositories --repository-names "$REPO_NAME" --region $AWS_REGION &>/dev/null; then
        # Lister et supprimer toutes les images
        IMAGE_TAGS=$(aws ecr list-images --repository-name "$REPO_NAME" --region $AWS_REGION --query 'imageIds[*]' --output json 2>/dev/null)
        
        if [[ "$IMAGE_TAGS" != "[]" ]] && [[ "$IMAGE_TAGS" != "null" ]] && [[ ! -z "$IMAGE_TAGS" ]]; then
            echo "  Suppression des images..."
            aws ecr batch-delete-image --repository-name "$REPO_NAME" --image-ids "$IMAGE_TAGS" --region $AWS_REGION
        fi
        
        echo "  Suppression du dépôt..."
        aws ecr delete-repository --repository-name "$REPO_NAME" --region $AWS_REGION --force
    else
        echo "  Dépôt $REPO_NAME non trouvé, passage au suivant"
    fi
done

# === 5. Suppression des NAT Gateways ===
echo "=== Étape 5: Suppression des NAT Gateways ==="
for nat_id in $(aws ec2 describe-nat-gateways --region $AWS_REGION --query 'NatGateways[?State != `deleted`].NatGatewayId' --output text); do
    if [ ! -z "$nat_id" ]; then
        echo "Suppression du NAT Gateway: $nat_id"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region $AWS_REGION
    fi
done

# Attendre la suppression des NAT Gateways
if [ ! -z "$(aws ec2 describe-nat-gateways --region $AWS_REGION --query 'NatGateways[?State == `deleting`].NatGatewayId' --output text)" ]; then
    echo "Attente de la suppression des NAT Gateways (jusqu'à 2 minutes)..."
    for i in {1..8}; do
        sleep 15
        remaining=$(aws ec2 describe-nat-gateways --region $AWS_REGION --query 'NatGateways[?State == `deleting`].NatGatewayId' --output text)
        if [ -z "$remaining" ]; then
            echo "Tous les NAT Gateways supprimés"
            break
        fi
        echo "  NAT Gateways encore en suppression: $remaining"
    done
fi

# === 6. Suppression des Internet Gateways ===
echo "=== Étape 6: Suppression des Internet Gateways ==="
for igw_info in $(aws ec2 describe-internet-gateways --region $AWS_REGION --filters "Name=attachment.state,Values=available" --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId]' --output text); do
    if [ ! -z "$igw_info" ]; then
        igw_id=$(echo $igw_info | cut -d' ' -f1)
        vpc_id=$(echo $igw_info | cut -d' ' -f2)
        
        echo "Détachement de l'Internet Gateway $igw_id du VPC $vpc_id"
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region $AWS_REGION 2>/dev/null
        
        echo "Suppression de l'Internet Gateway $igw_id"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region $AWS_REGION 2>/dev/null
    fi
done

# === 7. Suppression des Security Groups ===
echo "=== Étape 7: Suppression des Security Groups ==="
# Supprimer les règles de sécurité d'abord pour éviter les dépendances circulaires
for sg_id in $(aws ec2 describe-security-groups --region $AWS_REGION --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    if [ ! -z "$sg_id" ]; then
        echo "Nettoyage des règles du Security Group: $sg_id"
        
        # Supprimer toutes les règles entrantes
        aws ec2 describe-security-groups --group-ids "$sg_id" --region $AWS_REGION --query 'SecurityGroups[0].IpPermissions' --output json > /tmp/sg_rules_$sg_id.json 2>/dev/null
        if [ -s /tmp/sg_rules_$sg_id.json ] && [ "$(cat /tmp/sg_rules_$sg_id.json)" != "[]" ]; then
            aws ec2 revoke-security-group-ingress --group-id "$sg_id" --ip-permissions file:///tmp/sg_rules_$sg_id.json --region $AWS_REGION 2>/dev/null
        fi
        
        # Supprimer toutes les règles sortantes (sauf la règle par défaut)
        aws ec2 describe-security-groups --group-ids "$sg_id" --region $AWS_REGION --query 'SecurityGroups[0].IpPermissionsEgress' --output json > /tmp/sg_egress_$sg_id.json 2>/dev/null
        if [ -s /tmp/sg_egress_$sg_id.json ] && [ "$(cat /tmp/sg_egress_$sg_id.json)" != "[]" ]; then
            aws ec2 revoke-security-group-egress --group-id "$sg_id" --ip-permissions file:///tmp/sg_egress_$sg_id.json --region $AWS_REGION 2>/dev/null
        fi
        
        rm -f /tmp/sg_*rules_$sg_id.json /tmp/sg_egress_$sg_id.json 2>/dev/null
    fi
done

# Maintenant supprimer les Security Groups
for sg_id in $(aws ec2 describe-security-groups --region $AWS_REGION --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text); do
    if [ ! -z "$sg_id" ]; then
        echo "Suppression du Security Group: $sg_id"
        aws ec2 delete-security-group --group-id "$sg_id" --region $AWS_REGION 2>/dev/null
    fi
done

# === 8. Suppression des Subnets et Route Tables ===
echo "=== Étape 8: Suppression des Subnets et Route Tables ==="
for vpc_id in $(aws ec2 describe-vpcs --region $AWS_REGION --filters "Name=is-default,Values=false" --query 'Vpcs[].VpcId' --output text); do
    if [ ! -z "$vpc_id" ]; then
        echo "Nettoyage du VPC: $vpc_id"
        
        # Supprimer les subnets
        for subnet_id in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region $AWS_REGION --query 'Subnets[].SubnetId' --output text); do
            echo "  Suppression du subnet: $subnet_id"
            aws ec2 delete-subnet --subnet-id "$subnet_id" --region $AWS_REGION 2>/dev/null
        done
        
        # Supprimer les route tables (sauf la principale)
        for rt_id in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" "Name=association.main,Values=false" --region $AWS_REGION --query 'RouteTables[].RouteTableId' --output text); do
            echo "  Suppression de la route table: $rt_id"
            aws ec2 delete-route-table --route-table-id "$rt_id" --region $AWS_REGION 2>/dev/null
        done
    fi
done

# === 9. Suppression des VPC ===
echo "=== Étape 9: Suppression des VPC ==="
for vpc_id in $(aws ec2 describe-vpcs --region $AWS_REGION --filters "Name=is-default,Values=false" --query 'Vpcs[].VpcId' --output text); do
    if [ ! -z "$vpc_id" ]; then
        echo "Suppression du VPC: $vpc_id"
        aws ec2 delete-vpc --vpc-id "$vpc_id" --region $AWS_REGION 2>/dev/null
    fi
done

# === 10. Attendre la suppression des stacks CloudFormation critiques ===
echo "=== Étape 10: Attente de la suppression des stacks CloudFormation ==="
for stack_name in $EXISTING_STACKS; do
    if [[ "$stack_name" == *"$CLUSTER_NAME"* ]] || [[ "$stack_name" == "$RDS_STACK_NAME" ]]; then
        wait_for_stack_deletion "$stack_name"
    fi
done

# === Vérification finale complète ===
echo ""
echo "=== VÉRIFICATION FINALE ==="
echo ""

echo "CloudFormation Stacks restants:"
REMAINING_STACKS=$(aws cloudformation list-stacks --region $AWS_REGION --query 'StackSummaries[?StackStatus != `DELETE_COMPLETE`].[StackName,StackStatus]' --output table)
if [ ! -z "$REMAINING_STACKS" ]; then
    echo "$REMAINING_STACKS"
else
    echo "Aucun stack CloudFormation restant ✓"
fi

echo ""
echo "Clusters EKS restants:"
EKS_CLUSTERS=$(aws eks list-clusters --region $AWS_REGION --query 'clusters' --output text)
if [ ! -z "$EKS_CLUSTERS" ]; then
    echo "$EKS_CLUSTERS"
else
    echo "Aucun cluster EKS restant ✓"
fi

echo ""
echo "Load Balancers restants:"
LB_COUNT=$(aws elbv2 describe-load-balancers --region $AWS_REGION --query 'length(LoadBalancers)' --output text 2>/dev/null)
echo "Nombre de Load Balancers: $LB_COUNT"

echo ""
echo "Target Groups restants:"
TG_COUNT=$(aws elbv2 describe-target-groups --region $AWS_REGION --query 'length(TargetGroups)' --output text 2>/dev/null)
echo "Nombre de Target Groups: $TG_COUNT"

echo ""
echo "NAT Gateways restants:"
NAT_REMAINING=$(aws ec2 describe-nat-gateways --region $AWS_REGION --query 'NatGateways[?State != `deleted`].[NatGatewayId,State]' --output table)
if [ ! -z "$NAT_REMAINING" ] && [ "$NAT_REMAINING" != "None" ]; then
    echo "$NAT_REMAINING"
else
    echo "Aucun NAT Gateway restant ✓"
fi

echo ""
echo "Security Groups restants (hors default):"
SG_COUNT=$(aws ec2 describe-security-groups --region $AWS_REGION --query 'length(SecurityGroups[?GroupName!=`default`])' --output text)
echo "Nombre de Security Groups: $SG_COUNT"

echo ""
echo "VPC restants (hors default):"
VPC_COUNT=$(aws ec2 describe-vpcs --region $AWS_REGION --filters "Name=is-default,Values=false" --query 'length(Vpcs)' --output text)
echo "Nombre de VPC: $VPC_COUNT"

echo ""
echo "Dépôts ECR restants avec préfixe '$ECR_REPO_PREFIX':"
ECR_REPOS=$(aws ecr describe-repositories --region $AWS_REGION --query "repositories[?starts_with(repositoryName, '$ECR_REPO_PREFIX')].repositoryName" --output text 2>/dev/null)
if [ ! -z "$ECR_REPOS" ]; then
    echo "$ECR_REPOS"
else
    echo "Aucun dépôt ECR restant avec le préfixe ✓"
fi

echo ""
echo "=== SUPPRESSION TERMINÉE ==="
echo ""

if [ "$LB_COUNT" -eq 0 ] && [ "$TG_COUNT" -eq 0 ] && [ "$SG_COUNT" -eq 0 ] && [ "$VPC_COUNT" -eq 0 ] && [ -z "$EKS_CLUSTERS" ] && [ -z "$ECR_REPOS" ]; then
    echo " SUCCÈS: Toute l'infrastructure a été supprimée avec succès!"
else
    echo "  ATTENTION: Certaines ressources subsistent. Vérifiez la console AWS pour les supprimer manuellement si nécessaire."
fi

echo ""
echo "Note: Les NAT Gateways peuvent prendre jusqu'à 20 minutes pour être complètement supprimés."
echo "Les charges AWS s'arrêteront une fois tous les composants supprimés."