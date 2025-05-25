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
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

### 3. Installer le AWS Load Balancer Controller

```bash
./setup-cluster-with-alb.sh
```

---

### 4. Installer les CRDs nécessaires

#### Installation des CRDs Prometheus (manuellement, avec `create` pour éviter les erreurs d’annotation trop longues)

```bash
cd ~/stage/spring-petclinic-helm-charts/monitoring
kubectl create -f crds/crd-prometheuses.yaml
kubectl create -f crds/crd-prometheusagents.yaml
kubectl create -f crds/crd-servicemonitors.yaml
kubectl create -f crds/crd-podmonitors.yaml
```

---

### 5. Connexion à ArgoCD localement

```bash
# 1. Ouvrir le port local dans le nouveau terminal
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

```bash
# 2. Récupérer le mot de passe admin et se connecter dans le terminal où vous aler utiliser argocd
argocd login localhost:8080   --username admin   --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)   --insecure
```

---

### 6. Appliquer les applications ArgoCD localement

```bash
cd ~/stage/spring-petclinic-helm-charts
./scripts/apply-apps.sh
./scripts/sync-local.sh api-gateway-app api-gateway
```

---

### 7. Vérifier le LoadBalancer (ALB)

```bash
kubectl get ingress -A
```

---

### 8. Mettre à jour le DNS via Route 53

```bash
cd ../projetpetclinicinitial/scripts
./update-route53-record.sh
```

---

### 9. Accéder à l’application via HTTPS

```bash
curl https://greta25.click
```

---

### 10. Déployer Prometheus et Grafana

## Prérequis

- Cluster EKS opérationnel
- ArgoCD installé et accessible
- AWS CLI et kubectl configurés

## Étapes d'installation du monitoring

### 1 Créer les CRDs manuellement (important pour éviter l'erreur "Too long annotations")

```bash
kubectl create -f monitoring/kube-prometheus-stack/charts/crds/crds/
```

### 2 Déployer Prometheus et Grafana via ArgoCD

Créer l'application ArgoCD `prometheus` :

```bash
kubectl apply -f monitoring/prometheus-app.yaml
```

Synchroniser l'application :

```bash
argocd app sync prometheus --force
```

Si l'erreur "another operation is already in progress" apparaît, exécuter :

```bash
argocd app terminate-op prometheus
argocd app sync prometheus --force
```

### 3 Vérifier le déploiement

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

#### 4 Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Accéder à Prometheus via http://localhost:9090

#### Grafana

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Accéder à Grafana via http://localhost:3000

Login par défaut : `admin`
Mot de passe : récupérer avec :

```bash
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

## Bonnes pratiques

- Ne jamais modifier manuellement les CRDs déjà installés
- Pour les valeurs personnalisées, utiliser le fichier `monitoring/prometheus/values.yaml` et le référencer dans `prometheus-app.yaml`
- Si des erreurs CRD persistent, supprimer tous les CRDs et refaire l'étape 3

## Nettoyage

```bash
kubectl delete -f monitoring/prometheus-app.yaml
kubectl delete namespace monitoring
```

---

### 11. Synchroniser tous les services en une seule commande

```bash
./scripts/sync-all-services.sh
```

---

### Accéder à Grafana

```bash
kubectl port-forward svc/grafana -n monitoring 3000:80
# Interface Web : http://localhost:3000, login: admin / admin
```

---

## Remarques de sécurité

- **NE PAS publier `values.secret.yaml` dans Git**
- Créer `values.example.yaml` avec des valeurs fictives

---

## Exemple de `values.secret.yaml`

```yaml
global:
  certificateArn: "arn:aws:acm:eu-west-3:xxxxxxx"
  domainName: "greta25.click"
image:
  repository: "123456789.dkr.ecr.eu-west-3.amazonaws.com/spring-petclinic/api-gateway"
  tag: "latest"
```