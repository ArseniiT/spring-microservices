#!/bin/bash

# === Configuration RDS pour Spring Petclinic ===
AWS_REGION="eu-west-3"
CLUSTER_NAME="petclinic-cluster"
STACK_NAME="petclinic-rds"
SECRET_NAME="dockerhub-credentials"

echo "=== Démarrage du déploiement RDS pour Petclinic ==="

# Fonction pour récupérer les informations du cluster EKS
get_eks_cluster_info() {
    echo "Récupération des informations du cluster EKS..."
    
    aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Erreur: Le cluster EKS '$CLUSTER_NAME' n'existe pas dans la région $AWS_REGION"
        exit 1
    fi
    
    VPC_ID=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --query 'cluster.resourcesVpcConfig.vpcId' \
        --output text \
        --region $AWS_REGION)
    
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
        echo "Erreur: Impossible de récupérer le VPC ID du cluster EKS"
        exit 1
    fi
    
    echo "VPC ID du cluster EKS: $VPC_ID"
}

# Fonction pour récupérer le Security Group des worker nodes
get_node_security_group() {
    echo "Recherche du Security Group des worker nodes..."
    
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
                  "Name=group-name,Values=*nodegroup*" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region $AWS_REGION)
    
    if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
        echo "Recherche avec le pattern eksctl..."
        SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=eksctl-${CLUSTER_NAME}-nodegroup-*" \
            --query 'SecurityGroups[0].GroupId' \
            --output text \
            --region $AWS_REGION)
    fi
    
    if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
        echo "Recherche dans tous les Security Groups du VPC..."
        SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=$VPC_ID" \
                      "Name=description,Values=*EKS*node*" \
            --query 'SecurityGroups[0].GroupId' \
            --output text \
            --region $AWS_REGION)
    fi
    
    if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
        echo "Erreur: Impossible de trouver le Security Group des worker nodes EKS"
        exit 1
    fi
    
    echo "Security Group ID trouvé: $SG_ID"
}

# Fonction pour récupérer les sous-réseaux dans différentes AZ
get_subnets() {
    echo "Récupération des sous-réseaux du VPC..."

    # Récupérer tous les subnets disponibles dans le VPC, avec leur AZ
    MAP_SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
        --output text \
        --region $AWS_REGION)

    if [ -z "$MAP_SUBNETS" ]; then
        echo "Erreur: Aucun sous-réseau trouvé dans le VPC"
        exit 1
    fi

    # Choisir 2 subnets dans des AZ différentes
    SUBNET1=""
    SUBNET2=""
    AZ1=""
    AZ2=""

    while read SUBNET_ID AZ; do
        if [ -z "$SUBNET1" ]; then
            SUBNET1=$SUBNET_ID
            AZ1=$AZ
        elif [ "$AZ" != "$AZ1" ]; then
            SUBNET2=$SUBNET_ID
            AZ2=$AZ
            break
        fi
    done <<< "$MAP_SUBNETS"

    if [ -z "$SUBNET1" ] || [ -z "$SUBNET2" ]; then
        echo "Erreur: Impossible de trouver deux sous-réseaux dans des AZ différentes"
        exit 1
    fi

    SUBNET_IDS_CSV="$SUBNET1,$SUBNET2"
    echo "Sous-réseaux trouvés: $SUBNET_IDS_CSV"
}

get_db_credentials() {
    echo "Récupération des identifiants de base de données..."
    
    SECRET_JSON=$(aws secretsmanager get-secret-value \
        --secret-id $SECRET_NAME \
        --query SecretString \
        --output text \
        --region $AWS_REGION)
    
    if [ -z "$SECRET_JSON" ]; then
        echo "Erreur: Impossible de récupérer le secret '$SECRET_NAME'"
        exit 1
    fi
    
    DB_USER=$(echo $SECRET_JSON | jq -r '.db_user // empty')
    DB_PASSWORD=$(echo $SECRET_JSON | jq -r '.db_password // empty')
    
    if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
        echo "Erreur: db_user ou db_password introuvables dans le secret"
        echo "Contenu du secret: $(echo $SECRET_JSON | jq 'keys')"
        exit 1
    fi
    
    echo "Identifiants DB récupérés avec succès"
}

deploy_rds() {
    echo "Déploiement de l'instance RDS MySQL..."
    
    aws cloudformation deploy \
        --stack-name $STACK_NAME \
        --template-file ../infra/rds/rds-mysql.yaml \
        --region $AWS_REGION \
        --parameter-overrides \
            VPCSecurityGroupId=$SG_ID \
            VPCId=$VPC_ID \
            DBSubnetIds=$SUBNET_IDS_CSV \
            DBMasterUsername=$DB_USER \
            DBMasterUserPassword=$DB_PASSWORD \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-fail-on-empty-changeset
    
    if [ $? -ne 0 ]; then
        echo "Erreur lors du déploiement CloudFormation"
        exit 1
    fi
    
    echo "Stack CloudFormation déployée avec succès"
}

update_secret_with_endpoint() {
    echo "Récupération de l'endpoint RDS..."
    
    DB_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $AWS_REGION \
        --query "Stacks[0].Outputs[?OutputKey=='RDSInstanceEndpoint'].OutputValue" \
        --output text)
    
    if [ -z "$DB_ENDPOINT" ]; then
        echo "Erreur: Impossible de récupérer l'endpoint RDS"
        exit 1
    fi
    
    echo "Endpoint RDS: $DB_ENDPOINT"
    
    echo "Mise à jour du secret avec l'endpoint RDS..."
    
    TEMP_FILE=$(mktemp)
    
    echo $SECRET_JSON | jq \
        --arg endpoint "$DB_ENDPOINT" \
        --arg dbname "petclinic" \
        '. + {"db_host": $endpoint, "db_name": $dbname}' > $TEMP_FILE
    
    aws secretsmanager update-secret \
        --secret-id $SECRET_NAME \
        --secret-string file://$TEMP_FILE \
        --region $AWS_REGION
    
    rm $TEMP_FILE
    
    echo "Secret mis à jour avec l'endpoint RDS et le nom de la base de données"
}

main() {
    echo "=== Configuration RDS pour Spring Petclinic ==="
    
    get_eks_cluster_info
    get_node_security_group
    get_subnets
    get_db_credentials
    deploy_rds
    update_secret_with_endpoint
    
    echo ""
    echo "=== Déploiement RDS terminé avec succès ==="
    echo "Endpoint RDS: $DB_ENDPOINT"
    echo "Base de données: petclinic"
    echo "Port: 3306"
    echo "Le secret '$SECRET_NAME' a été mis à jour avec les informations de connexion"
    echo ""
    echo "Les microservices peuvent maintenant utiliser ces variables d'environnement:"
    echo "- DB_HOST: $DB_ENDPOINT"
    echo "- DB_PORT: 3306"
    echo "- DB_NAME: petclinic"
    echo "- DB_USER: (depuis le secret)"
    echo "- DB_PASSWORD: (depuis le secret)"
}

main
