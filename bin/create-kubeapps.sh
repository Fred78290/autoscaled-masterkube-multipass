#!/bin/bash
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/external-dns

mkdir -p ${ETC_DIR}

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

kubectl --kubeconfig=${TARGET_CLUSTER_LOCATION}/config --dry-run=client -o yaml create namespace kubeapps \
	| tee ${ETC_DIR}/kubeapps.yaml | kubectl apply -f -

echo "---" >> ${ETC_DIR}/kubeapps.yaml
kubectl --kubeconfig=${TARGET_CLUSTER_LOCATION}/config --dry-run=client -o yaml create clusterrolebinding kubeapps-operator -n kubeapps --clusterrole=cluster-admin --serviceaccount=kubeapps:kubeapps-operator \
	| tee -a ${ETC_DIR}/kubeapps.yaml| kubectl apply -f -

echo "---" >> ${ETC_DIR}/kubeapps.yaml
kubectl --kubeconfig=${TARGET_CLUSTER_LOCATION}/config --dry-run=client -o yaml create serviceaccount kubeapps-operator -n kubeapps \
	| tee -a ${ETC_DIR}/kubeapps.yaml | kubectl apply -f -

cat > ${ETC_DIR}/values.yaml <<EOF
ingress:
  enabled: true
  hostname: ${NODEGROUP_NAME}-kubeapps.${DOMAIN_NAME}
  tls: true
  certManager: true
  annotations:
    cert-manager.io/cluster-issuer: cert-issuer-prod
    external-dns.alpha.kubernetes.io/register: 'true'
    external-dns.alpha.kubernetes.io/ttl: '600'
    external-dns.alpha.kubernetes.io/target: ${EXTERNAL_DNS_TARGET}
    external-dns.alpha.kubernetes.io/hostname: ${NODEGROUP_NAME}-kubeapps.${DOMAIN_NAME}
EOF

helm install kubeapps \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--namespace kubeapps \
	--set useHelm3=true \
	--values ${ETC_DIR}/values.yaml \
	bitnami/kubeapps
