# Déploiement de Spring Petclinic sur AWS EKS avec ALB, Route 53 et HTTPS

Ce guide explique étape par étape comment déployer les microservices de Spring Petclinic sur un cluster **EKS** avec un **AWS ALB** (Application Load Balancer), un **nom de domaine personnalisé via Route 53**, et **certificat HTTPS via ACM**.

---

## Prérequis

- AWS CLI configuré (`aws configure`)
- `eksctl` installé
- `kubectl` installé
- `helm` installé
- Un domaine enregistré dans Route 53
- Un certificat SSL dans ACM pour ce domaine

---

## Étapes

### 1. Créer le cluster EKS

```bash
cd projetpetclinicinitial/scripts
./deploy-to-aws-eks.sh
```

> Ce script crée le cluster avec `eksctl` et met à jour le contexte `kubectl`.

---

### 2. Installer ArgoCD

```bash
# Toujours dans le même script
# Cela installera ArgoCD dans le namespace argocd
```

---

### 3. Installer le AWS Load Balancer Controller

```bash
./setup-cluster-with-alb.sh
```

> Ce script :
> - Crée le provider IAM OIDC
> - Crée la politique IAM et le service account pour ALB controller
> - Installe le ALB Controller via Helm

---

### 4. Appliquer les applications ArgoCD (Helm charts)

```bash
cd ../../spring-petclinic-helm-charts
./apply-apps.sh
```

> Cela applique tous les fichiers `*-app.yaml` dans ArgoCD. Chaque application pointe sur son dossier Helm respectif.

---

### 5. Vérifier l’Ingress généré

```bash
kubectl get ingress -A
```

Attendre que l'ALB apparaisse avec le nom de domaine (DNS AWS) dans le champ `ADDRESS`.

---

### 6. Mettre à jour le DNS avec Route 53

```bash
cd ../projetpetclinicinitial/scripts
./update-route53-record.sh
```

> Ce script met à jour le record A du domaine (ex: `greta25.click`) pour qu'il pointe vers le DNS du ALB.

---

### 7. Accéder à l'application

Une fois la propagation DNS terminée :

```bash
curl http://votre-domaine
curl https://votre-domaine
```

---

## Remarques

- Le fichier `values.secret.yaml` contient les valeurs sensibles : ARN du certificat, nom de domaine, repository ECR. Il ne doit **pas** être versionné.
- Le fichier `values.example.yaml` est une version publique à titre d'exemple.

---

## Dépannage

### Erreur : `dualstack.none.`

Cela signifie que **l’Ingress n’est pas encore créé**. D'abord lancer `apply-apps.sh`, puis réessayer `update-route53-record.sh`.

---
