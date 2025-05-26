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
    
    # Vérifier que le cluster existe
    aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Erreur: Le cluster EKS '$CLUSTER_NAME' n'existe pas dans la région $AWS_REGION"
        exit 1
    fi
    
    # Récupérer le VPC ID via le cluster EKS
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
    
    # Méthode 1: Via les tags du cluster
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
                  "Name=group-name,Values=*nodegroup*" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region $AWS_REGION)
    
    # Méthode 2: Si la première méthode échoue, chercher avec eksctl pattern
    if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
        echo "Recherche avec le pattern eksctl..."
        SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=eksctl-${CLUSTER_NAME}-nodegroup-*" \
            --query 'SecurityGroups[0].GroupId' \
            --output text \
            --region $AWS_REGION)
    fi
    
    # Méthode 3: Rechercher tous les SG du VPC avec les tags EKS
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
        echo "Vérifiez que le cluster EKS est correctement configuré avec des worker nodes"
        exit 1
    fi
    
    echo "Security Group ID trouvé: $SG_ID"
}

# Fonction pour récupérer les sous-réseaux
get_subnets() {
    echo "Récupération des sous-réseaux du VPC..."
    
    # Récupérer les sous-réseaux privés (recommandé pour RDS)
    PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
                  "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
                  "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
        --query 'Subnets[*].SubnetId' \
        --output text \
        --region $AWS_REGION)
    
    # Si pas de sous-réseaux privés tagués, prendre tous les sous-réseaux du VPC
    if [ -z "$PRIVATE_SUBNETS" ]; then
        echo "Aucun sous-réseau privé tagué trouvé, utilisation de tous les sous-réseaux du VPC"
        SUBNET_IDS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'Subnets[*].SubnetId' \
            --output text \
            --region $AWS_REGION)
    else
        SUBNET_IDS=$PRIVATE_SUBNETS
    fi
    
    if [ -z "$SUBNET_IDS" ]; then
        echo "Erreur: Aucun sous-réseau trouvé dans le VPC"
        exit 1
    fi
    
    # Convertir en format CSV pour CloudFormation
    SUBNET_IDS_CSV=$(echo $SUBNET_IDS | tr ' ' ',')
    echo "Sous-réseaux trouvés: $SUBNET_IDS_CSV"
}

# Fonction pour récupérer les credentials DB depuis Secrets Manager
get_db_credentials() {
    echo "Récupération des identifiants de base de données..."
    
    # Récupérer le secret complet
    SECRET_JSON=$(aws secretsmanager get-secret-value \
        --secret-id $SECRET_NAME \
        --query SecretString \
        --output text \
        --region $AWS_REGION)
    
    if [ -z "$SECRET_JSON" ]; then
        echo "Erreur: Impossible de récupérer le secret '$SECRET_NAME'"
        exit 1
    fi
    
    # Extraire les valeurs
    DB_USER=$(echo $SECRET_JSON | jq -r '.db_user // empty')
    DB_PASSWORD=$(echo $SECRET_JSON | jq -r '.db_password // empty')
    
    if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
        echo "Erreur: db_user ou db_password introuvables dans le secret"
        echo "Contenu du secret: $(echo $SECRET_JSON | jq 'keys')"
        exit 1
    fi
    
    echo "Identifiants DB récupérés avec succès"
}

# Fonction pour déployer RDS via CloudFormation
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

# Fonction pour récupérer l'endpoint RDS et mettre à jour le secret
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
    
    # Mettre à jour le secret avec l'endpoint et le nom de DB
    echo "Mise à jour du secret avec l'endpoint RDS..."
    
    TEMP_FILE=$(mktemp)
    
    # Récupérer le secret actuel et ajouter db_host et db_name
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

# Fonction principale
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

# Exécution du script principal
main