#!/bin/bash
CURDIR=$(dirname $0)

source "${CURDIR}/echo.sh"

echo_blue_bold "Deploy kubernetes dashboard"

# This file is intent to deploy dashboard inside the masterkube
CURDIR=$(dirname $0)

pushd ${CURDIR}/../ &>/dev/null

export NAMESPACE=kubernetes-dashboard
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/dashboard
export KUBERNETES_TEMPLATE=./templates/dashboard
export SUBPATH_POD_NAME='$(POD_NAME)'
export REWRITE_TARGET='/$1'

mkdir -p ${ETC_DIR}

cat > ${ETC_DIR}/values.yaml <<EOF
app:
  tolerations:
    - key: node-role.kubernetes.io/master
      effect: NoSchedule
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
  ingress:
    enabled: true
    hosts:
      - ${DASHBOARD_HOSTNAME}.${DOMAIN_NAME}
    ingressClassName: nginx
    tls:
      enabled: true
      secretName: kubernetes-dashboard-server-ingress-tls
    issuer:
      name: cert-issuer-prod
      scope: cluster
    annotations:
      external-dns.alpha.kubernetes.io/register: 'true'
      external-dns.alpha.kubernetes.io/ttl: '600'
      external-dns.alpha.kubernetes.io/target: ${EXTERNAL_DNS_TARGET}
      external-dns.alpha.kubernetes.io/hostname: ${DASHBOARD_HOSTNAME}.${DOMAIN_NAME}
metrics-server:
  enabled: true
EOF

helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/

# Deploy a Helm Release named "kubernetes-dashboard" using the kubernetes-dashboard chart
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--create-namespace \
	--namespace ${NAMESPACE} \
	--values ${ETC_DIR}/values.yaml

# Create the service account in the namespace 
kubectl create serviceaccount my-dashboard-sa -n ${NAMESPACE} --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

# Give that service account root on the cluster
kubectl create clusterrolebinding my-dashboard-sa \
	--clusterrole=cluster-admin \
	--serviceaccount=${NAMESPACE}:my-dashboard-sa \
	--dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

# Find the secret that was created to hold the token for the SA
kubectl get secrets -n ${NAMESPACE} --kubeconfig=${TARGET_CLUSTER_LOCATION}/config

DASHBOARD_TOKEN=$(kubectl create token my-dashboard-sa --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -n ${NAMESPACE} --duration 86400h)

echo_blue_bold "Dashboard token:${DASHBOARD_TOKEN}"

echo ${DASHBOARD_TOKEN} > ${TARGET_CLUSTER_LOCATION}/dashboard-token