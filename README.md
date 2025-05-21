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

---

### 2. Installer ArgoCD

Si vous n'avez pas encore installé l'utilitaire en ligne de commande :

```bash
# Installer le CLI ArgoCD
VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | jq -r .tag_name)
curl -sLO https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64
chmod +x argocd-linux-amd64
sudo mv argocd-linux-amd64 /usr/local/bin/argocd
```

Ensuite, déployez ArgoCD dans votre cluster EKS :

```bash
# Installer ArgoCD dans le namespace argocd
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
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

### 4. Connexion à ArgoCD localement (obligatoire pour les tests `--local`)

ArgoCD ne publie pas d’interface par défaut. Il faut ouvrir un port local et s’y connecter :

```bash
# 1. Ouvrir le port local dans le nouveau terminal
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

```bash
# 2. Récupérer le mot de passe admin et se connecter dans le terminal où vous aler utiliser argocd
argocd login localhost:8080   --username admin   --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)   --insecure
```

💡 Important : cette étape est nécessaire pour toute commande `argocd app sync --local`. Sans elle, vous obtiendrez `PermissionDenied`.

---

### 5. Supprimer la synchronisation automatique dans ArgoCD  (optionnel pour tests locaux)

```bash
argocd app set api-gateway --sync-policy none
```

---

### 6. Appliquer une application localement (pour tester avec `values.secret.yaml`)

```bash
cd spring-petclinic-helm-charts
./apply-apps.sh
./sync-local.sh api-gateway-app api-gateway
```

> Cela utilise le contenu local du dossier `api-gateway`, y compris `values.yaml` et `values.secret.yaml`.

---

### 7. Vérifier que le ALB a été créé

```bash
kubectl get ingress -A
```

---

### 8. Mettre à jour le DNS avec Route 53

```bash
cd ../projetpetclinicinitial/scripts
./update-route53-record.sh
```

> Le script détecte automatiquement le DNS du ALB et met à jour l'enregistrement `A` de Route 53.

---

### 9. Accéder à l’application via HTTPS

```bash
curl https://greta25.click
```

---

### 10. Activer le monitoring avec Prometheus et Grafana

Assurez-vous que vous avez le répertoire `spring-petclinic-helm-charts`

Déployer les applications de monitoring via ArgoCD :

```bash
cd spring-petclinic-helm-charts/monitoring

kubectl create namespace monitoring  # une seule fois

argocd repo add https://prometheus-community.github.io/helm-charts --type helm --name prometheus-community

argocd app create -f prometheus-app.yaml
argocd app create -f grafana-app.yaml

argocd app sync prometheus --force
argocd app sync grafana --force
```

Une fois tous les pods prêts :

```bash
kubectl get pods -n monitoring
```

Accéder à Grafana :

```bash
kubectl port-forward svc/grafana -n monitoring 3000:80
```

Naviguez vers [http://localhost:3000](http://localhost:3000)  
Login : `admin`  
Mot de passe : `admin`


### 10bis. Redéploiement Prometheus sur AWS EKS (problème de CRD)

Si Prometheus ne se déploie pas correctement à cause de conflits ou erreurs de CRD (par exemple, erreur `metadata.annotations: Too long`), suivre les étapes suivantes :

```bash
cd spring-petclinic-helm-charts/monitoring

# Supprimer les anciennes applications si elles sont en échec
argocd app delete prometheus --yes

# Appliquer manuellement les CRDs nécessaires
kubectl create -f crds/crd-prometheuses.yaml
kubectl create -f crds/crd-prometheusagents.yaml

# (optionnel) Vérifier que les CRDs sont bien installés
kubectl get crd | grep prometheus

# Recréer l'application Prometheus dans ArgoCD
kubectl apply -f prometheus-app.yaml

# Synchroniser manuellement via ArgoCD
argocd app sync prometheus
```

Lorsque tous les pods sont prêts, accéder à Prometheus en local via port forwarding :
```bash
kubectl port-forward svc/prometheus-prometheus -n monitoring 9090:9090
```

Ensuite, accéder à l'interface web de Prometheus ici : [http://localhost:9090](http://localhost:9090)

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