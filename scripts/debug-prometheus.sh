#!/bin/bash

# Script de débogage approfondi pour Prometheus et Spring Boot
# Auteur: Arsenii TOLMACHEV
# Date: 12 mai 2025

echo "=== Débogage approfondi de Prometheus avec Spring Boot ==="

# Récupération du pod Admin Server
ADMIN_POD=$(kubectl get pods -l app=admin-server -o jsonpath="{.items[0].metadata.name}")
echo "Pod Admin Server: $ADMIN_POD"

# Vérification des détails du pod
echo -e "\n=== Détails du pod ==="
kubectl describe pod $ADMIN_POD | grep -A10 "Containers:"

# Vérification des logs pour les messages d'application
echo -e "\n=== Logs de l'application ==="
kubectl logs $ADMIN_POD | grep -E "Actuator|Prometheus|métriques|endpoint|Application démarrée|exposés|micrometer"

# Vérification des variables d'environnement dans le pod
echo -e "\n=== Variables d'environnement du pod ==="
kubectl exec $ADMIN_POD -- env | grep -E "MANAGEMENT|ACTUATOR|PROMETHEUS|METRICS|SPRING"

# Vérification du ServiceMonitor
echo -e "\n=== ServiceMonitor pour Admin Server ==="
kubectl get servicemonitor admin-server-admin-server -o yaml | grep -A10 "endpoints:"

# Vérification des services
echo -e "\n=== Service Admin Server ==="
kubectl get svc -l app=admin-server -o yaml | grep -A10 "ports:"

# Test de connectivité interne
echo -e "\n=== Test de connectivité interne ==="
kubectl exec $ADMIN_POD -- wget -O- -q localhost:8080/actuator || echo "Erreur d'accès à l'endpoint Actuator en interne"

# Vérification des endpoints disponibles avec port-forward
echo -e "\n=== Test des endpoints Actuator avec port-forward ==="
kubectl port-forward $ADMIN_POD 8080:8080 &
PF_PID=$!
sleep 3

# Liste des endpoints disponibles
echo "Liste des endpoints disponibles:"
curl -s http://localhost:8080/actuator

# Vérification des dépendances JARs
echo -e "\n=== Vérification des dépendances JAR dans le pod ==="
kubectl exec $ADMIN_POD -- sh -c "find /app -name '*.jar' -exec sh -c 'echo {} && unzip -l {} | grep -E \"prometheus|micrometer|actuator\"' \;"

# Vérification spécifique de Prometheus
echo -e "\nTentative d'accès direct à Prometheus:"
curl -v http://localhost:8080/actuator/prometheus

# Nettoyage
kill $PF_PID 2>/dev/null
wait $PF_PID 2>/dev/null

echo -e "\n=== Débogage terminé ==="
