# Déploiement de Spring Petclinic sur AWS EKS avec ALB, Route 53 et HTTPS

Ce guide explique étape par étape comment déployer les microservices de Spring Petclinic sur un cluster **EKS**
avec un **AWS ALB** (Application Load Balancer), un **nom de domaine personnalisé via Route 53**, et
**certificat HTTPS via ACM**. L'intégration se fait via **ArgoCD** et **Helm**, avec support du déploiement **local avec valeurs privées**.

---

## Prérequis

- AWS CLI configuré (`aws configure`)
- `eksctl` installé
- `kubectl` installé
- `helm` installé
- `argocd` CLI installé
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

### 5. Supprimer la synchronisation automatique dans ArgoCD (optionnel pour tests locaux)

```bash
argocd app set <app-name> --sync-policy none
```

---

### 6. Appliquer une application localement avec valeurs secrètes (solution au problème Helm/ArgoCD)

```bash
cd spring-petclinic-helm-charts

argocd app sync api-gateway-app   --local api-gateway   --prune --force
```

> Assurez-vous, avant cela, d’avoir correctement créé :
>
> - `values.yaml` (paramètres standards)
> - `values.secret.yaml` (avec certificateArn, domainName, ECR etc)
>
> **Important** : les deux fichiers doivent être présents dans le dossier de la chart.
>
> Exemple :
>
> ```yaml
> global:
>   certificateArn: "arn:aws:acm:eu-west-3:..."
>   domainName: "greta25.click"
> image:
>   repository: "123456789.dkr.ecr.eu-west-3.amazonaws.com/spring-petclinic/api-gateway"
>   tag: "latest"
> ```

---

### 7. Vérifier l’Ingress généré

```bash
kubectl get ingress -A
```

Attendre que l'ALB apparaisse avec le nom de domaine (DNS AWS) dans le champ `ADDRESS`.

---

### 8. Mettre à jour le DNS avec Route 53

```bash
cd ../projetpetclinicinitial/scripts
./update-route53-record.sh
```

> Ce script met à jour le record A du domaine (ex: `greta25.click`) pour qu'il pointe vers le DNS du ALB.

---

### 9. Accéder à l'application

Une fois la propagation DNS terminée (~1-2 minutes) :

```bash
curl https://greta25.click
```

---

## Résolution des problèmes de `values.secret.yaml`

Le flag `--values` **n’est pas supporté** directement dans `argocd app sync`. Au lieu de cela :
- Définir les fichiers `values.yaml` et `values.secret.yaml` **dans le dossier Helm** de l’application
- S’assurer que la `source` ArgoCD contient les deux fichiers dans le champ `Helm Values`
- Désactiver la sync automatique
- Utiliser `--local` + `--prune --force` pour tester localement

---

## Remarques de sécurité

- **NE PAS publier `values.secret.yaml` dans Git**. Ajouter à `.gitignore`
- Pour illustrer les valeurs, créer `values.example.yaml` avec des valeurs fictives

---

## Exemple de valeurs pour `values.secret.yaml`

```yaml
global:
  certificateArn: "arn:aws:acm:eu-west-3:xxxxxxx"
  domainName: "greta25.click"
image:
  repository: "123456789.dkr.ecr.eu-west-3.amazonaws.com/spring-petclinic/api-gateway"
  tag: "latest"
```

---
