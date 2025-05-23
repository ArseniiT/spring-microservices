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

#### CRDs pour Prometheus

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
./apply-apps.sh
./sync-local.sh api-gateway-app api-gateway
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

```bash
cd ~/stage/spring-petclinic-helm-charts
argocd repo add https://prometheus-community.github.io/helm-charts --type helm --name prometheus-community
kubectl create namespace monitoring
```

#### Installation des CRDs Prometheus (manuellement, avec `create` pour éviter les erreurs d’annotation trop longues)

```bash
cd monitoring
kubectl create -f crds/crd-prometheuses.yaml
kubectl create -f crds/crd-servicemonitors.yaml
kubectl create -f crds/crd-podmonitors.yaml
kubectl create -f crds/crd-prometheusagents.yaml || true  # peut échouer à cause de l'annotation trop longue
```

#### Appliquer les applications ArgoCD

```bash
argocd app create -f monitoring/prometheus-app.yaml
argocd app create -f monitoring/grafana-app.yaml
argocd app sync prometheus --force
argocd app sync grafana --force
```

#### Si l’objet Prometheus n’est pas créé automatiquement (erreur "no matches for kind Prometheus") :

```bash
kubectl delete crd prometheuses.monitoring.coreos.com
kubectl create -f crds/crd-prometheuses.yaml
kubectl apply -f monitoring/prometheus.yaml
```

---

### Accéder à Prometheus

```bash
kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090
# Interface Web : http://localhost:9090
```

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