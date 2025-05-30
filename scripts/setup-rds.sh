#!/bin/bash

# === Configuration RDS pour Spring Petclinic avec Security Groups automatiques ===
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

# Fonction pour récupérer TOUS les Security Groups EKS
get_all_eks_security_groups() {
    echo "Récupération de tous les Security Groups EKS..."
    
    # Récupérer tous les SG avec le tag EKS
    EKS_SG_IDS=$(aws ec2 describe-security-groups \
        --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
        --query 'SecurityGroups[*].GroupId' \
        --output text \
        --region $AWS_REGION)
    
    # Ajouter les SG des nodegroups
    NODEGROUP_SG_IDS=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=eksctl-${CLUSTER_NAME}-nodegroup-*" \
        --query 'SecurityGroups[*].GroupId' \
        --output text \
        --region $AWS_REGION)
    
    # Combiner tous les SG IDs
    ALL_SG_IDS="$EKS_SG_IDS $NODEGROUP_SG_IDS"
    
    # Nettoyer les espaces et doublons
    ALL_SG_IDS=$(echo $ALL_SG_IDS | tr ' ' '\n' | sort -u | tr '\n' ' ')
    
    echo "Security Groups EKS trouvés: $ALL_SG_IDS"
    
    # Prendre le premier SG pour le paramètre CloudFormation (compatibilité)
    SG_ID=$(echo $ALL_SG_IDS | awk '{print $1}')
    
    if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
        echo "Erreur: Impossible de trouver les Security Groups EKS"
        exit 1
    fi
    
    echo "Security Group principal pour CloudFormation: $SG_ID"
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

# Configuration automatique des Security Groups
configure_rds_security_groups() {
    echo "=== Configuration automatique des Security Groups RDS ==="
    
    # Récupérer l'ID du Security Group RDS créé par CloudFormation
    RDS_SG_ID=$(aws cloudformation describe-stack-resources \
        --stack-name $STACK_NAME \
        --region $AWS_REGION \
        --query 'StackResources[?LogicalResourceId==`PetclinicDBSecurityGroup`].PhysicalResourceId' \
        --output text)
    
    if [ -z "$RDS_SG_ID" ] || [ "$RDS_SG_ID" == "None" ]; then
        echo "Erreur: Impossible de récupérer l'ID du Security Group RDS"
        exit 1
    fi
    
    echo "Security Group RDS: $RDS_SG_ID"
    
    # Configurer l'accès pour chaque Security Group EKS
    for EKS_SG in $ALL_SG_IDS; do
        if [ ! -z "$EKS_SG" ] && [ "$EKS_SG" != "None" ]; then
            echo "Configuration de l'accès depuis $EKS_SG vers RDS..."
            aws ec2 authorize-security-group-ingress \
                --group-id "$RDS_SG_ID" \
                --protocol tcp \
                --port 3306 \
                --source-group "$EKS_SG" \
                --region $AWS_REGION 2>/dev/null && echo "  ✓ Règle ajoutée pour $EKS_SG" || echo "  ℹ Règle déjà existante pour $EKS_SG"
        fi
    done
    
    # Ajouter une règle CIDR pour tout le VPC (sécurité supplémentaire)
    VPC_CIDR=$(aws ec2 describe-vpcs \
        --vpc-ids $VPC_ID \
        --region $AWS_REGION \
        --query 'Vpcs[0].CidrBlock' \
        --output text)
    
    echo "Configuration de l'accès depuis le VPC CIDR: $VPC_CIDR"
    aws ec2 authorize-security-group-ingress \
        --group-id "$RDS_SG_ID" \
        --protocol tcp \
        --port 3306 \
        --cidr "$VPC_CIDR" \
        --region $AWS_REGION 2>/dev/null && echo "  ✓ Règle CIDR ajoutée" || echo "  ℹ Règle CIDR déjà existante"
    
    # Vérification finale des règles
    echo "Règles configurées pour le Security Group RDS:"
    aws ec2 describe-security-groups \
        --group-ids "$RDS_SG_ID" \
        --region $AWS_REGION \
        --query 'SecurityGroups[0].IpPermissions[*].[FromPort,ToPort,IpProtocol,UserIdGroupPairs[0].GroupId,IpRanges[0].CidrIp]' \
        --output table
}

# Test de connectivité
test_rds_connectivity() {
    echo "=== Test de connectivité RDS ==="
    
    DB_HOST=$(echo $SECRET_JSON | jq -r '.db_host')
    DB_USER=$(echo $SECRET_JSON | jq -r '.db_user')
    DB_PASSWORD=$(echo $SECRET_JSON | jq -r '.db_password')
    
    echo "Test de connectivité vers: $DB_HOST"
    
    # Créer un pod de test temporaire
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: rds-connectivity-test
spec:
  containers:
  - name: mysql
    image: mysql:8.0
    command: ['sleep', '300']
    env:
    - name: MYSQL_ROOT_PASSWORD
      value: "test"
  restartPolicy: Never
EOF
    
    # Attendre que le pod soit prêt
    kubectl wait --for=condition=Ready pod/rds-connectivity-test --timeout=60s
    
    # Tester la connectivité
    if kubectl exec rds-connectivity-test -- mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" -P3306 -e "SELECT 1 as connectivity_test;" >/dev/null 2>&1; then
        echo " Test de connectivité RDS réussi!"
    else
        echo " Échec du test de connectivité RDS"
        echo "Vérification des logs du test..."
        kubectl exec rds-connectivity-test -- mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" -P3306 -e "SELECT 1;" 2>&1 || true
    fi
    
    # Nettoyer le pod de test
    kubectl delete pod rds-connectivity-test --force --grace-period=0 >/dev/null 2>&1 || true
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
    
    echo "Secret AWS mis à jour avec l'endpoint RDS"
    
    # Mettre à jour le SECRET_JSON avec les nouvelles valeurs
    SECRET_JSON=$(aws secretsmanager get-secret-value \
        --secret-id $SECRET_NAME \
        --query SecretString \
        --output text \
        --region $AWS_REGION)
}

create_k8s_secret() {
    echo "Création/mise à jour du secret Kubernetes dockerhub-credentials..."

    DB_HOST=$(echo $SECRET_JSON | jq -r '.db_host')
    DB_PORT=$(echo $SECRET_JSON | jq -r '.db_port')
    DB_USER=$(echo $SECRET_JSON | jq -r '.db_user')
    DB_PASSWORD=$(echo $SECRET_JSON | jq -r '.db_password')
    DB_NAME=$(echo $SECRET_JSON | jq -r '.db_name')
    DOCKER_USERNAME=$(echo $SECRET_JSON | jq -r '.username')
    DOCKER_PASSWORD=$(echo $SECRET_JSON | jq -r '.password')
    CERTIFICATE_ARN=$(echo $SECRET_JSON | jq -r '.certificateArn')
    DOMAIN_NAME=$(echo $SECRET_JSON | jq -r '.domainName')

    # Supprimer le secret existant s'il existe
    kubectl delete secret dockerhub-credentials --ignore-not-found

    # Créer le secret mis à jour
    kubectl create secret generic dockerhub-credentials \
      --from-literal=username="$DOCKER_USERNAME" \
      --from-literal=password="$DOCKER_PASSWORD" \
      --from-literal=db_host="$DB_HOST" \
      --from-literal=db_port="$DB_PORT" \
      --from-literal=db_user="$DB_USER" \
      --from-literal=db_password="$DB_PASSWORD" \
      --from-literal=db_name="$DB_NAME" \
      --from-literal=certificateArn="$CERTIFICATE_ARN" \
      --from-literal=domainName="$DOMAIN_NAME"

    echo "Secret Kubernetes dockerhub-credentials créé/mis à jour avec succès"
}

main() {
    echo "=== Configuration RDS pour Spring Petclinic ==="
    
    get_eks_cluster_info
    get_all_eks_security_groups
    get_subnets
    get_db_credentials
    deploy_rds
    configure_rds_security_groups
    update_secret_with_endpoint
    # create_k8s_secret
    test_rds_connectivity
    
    echo ""
    echo "=== Déploiement RDS terminé avec succès ==="
    echo "Endpoint RDS: $DB_ENDPOINT"
    echo "Base de données: petclinic"
    echo "Port: 3306"
    echo "Security Groups configurés automatiquement"
    echo "Le secret '$SECRET_NAME' a été mis à jour dans AWS Secrets Manager et dans Kubernetes"
    echo "Le secret dans Kubernetes sera synchronisé automatiquement par ExternalSecret dans les prochaines 1-2 minutes"
    echo ""
    echo "Les microservices peuvent maintenant utiliser ces variables d'environnement:"
    echo "- DB_HOST: $DB_ENDPOINT"
    echo "- DB_PORT: 3306"
    echo "- DB_NAME: petclinic"
    echo "- DB_USER: (depuis le secret)"
    echo "- DB_PASSWORD: (depuis le secret)"
}

main