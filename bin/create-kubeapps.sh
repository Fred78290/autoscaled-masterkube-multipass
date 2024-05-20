#!/bin/bash
CURDIR=$(dirname $0)
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/kubeapps

source "${CURDIR}/echo.sh"

### Clear AppRepository after delete ns
# kubectl patch AppRepository/bitnami -p '{"metadata":{"finalizers":[]}}' --type=merge

mkdir -p ${ETC_DIR}

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

kubectl --kubeconfig=${TARGET_CLUSTER_LOCATION}/config --dry-run=client -o yaml create namespace kubeapps \
	| tee ${ETC_DIR}/kubeapps.yaml | kubectl apply -f -

echo "---" >> ${ETC_DIR}/kubeapps.yaml
kubectl --kubeconfig=${TARGET_CLUSTER_LOCATION}/config --dry-run=client -o yaml create clusterrolebinding kubeapps-operator -n kubeapps \
  --clusterrole=cluster-admin --serviceaccount=kubeapps:kubeapps-operator \
	| tee -a ${ETC_DIR}/kubeapps.yaml| kubectl apply -f -

echo "---" >> ${ETC_DIR}/kubeapps.yaml
kubectl --kubeconfig=${TARGET_CLUSTER_LOCATION}/config --dry-run=client -o yaml create serviceaccount kubeapps-operator -n kubeapps \
	| tee -a ${ETC_DIR}/kubeapps.yaml | kubectl apply -f -

echo "---" >> ${ETC_DIR}/kubeapps.yaml
cat <<EOF | tee -a ${ETC_DIR}/kubeapps.yaml | kubectl apply -f -
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: kubeapps-operator-token
  namespace: kubeapps
  annotations:
    kubernetes.io/service-account.name: kubeapps-operator
EOF

cat > ${ETC_DIR}/values.yaml <<EOF
ingress:
  ingressClassName: nginx
  enabled: true
  hostname: kubeapps-${NODEGROUP_NAME}.${DOMAIN_NAME}
  tls: true
  certManager: true
  annotations:
    cert-manager.io/cluster-issuer: cert-issuer-prod
    external-dns.alpha.kubernetes.io/register: 'true'
    external-dns.alpha.kubernetes.io/ttl: '600'
    external-dns.alpha.kubernetes.io/target: ${MASTERKUBE}.${DOMAIN_NAME}
    external-dns.alpha.kubernetes.io/hostname: kubeapps-${NODEGROUP_NAME}.${DOMAIN_NAME}
EOF

helm install kubeapps \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--namespace kubeapps \
	--set useHelm3=true \
	--values ${ETC_DIR}/values.yaml \
	bitnami/kubeapps

echo_blue_dot_title "KubeApps token: "

kubectl get --namespace kubeapps secret kubeapps-operator-token --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -o go-template='{{.data.token | base64decode}}'
