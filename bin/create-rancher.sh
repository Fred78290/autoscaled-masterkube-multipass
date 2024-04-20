#!/bin/bash
CURDIR=$(dirname $0)
KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | awk -F. '{ print $2 }')

source "${CURDIR}/echo.sh"

mkdir -p ${TARGET_DEPLOY_LOCATION}/rancher
pushd ${TARGET_DEPLOY_LOCATION} &>/dev/null

export NAMESPACE=cattle-system

kubectl create ns ${NAMESPACE} --dry-run=client --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -o yaml | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

if [ ${KUBERNETES_MINOR_RELEASE} -lt 27 ]; then
	REPO=rancher-latest/rancher

	helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
	helm repo update
else
	REPO=/tmp/rancher/

	curl -sL https://releases.rancher.com/server-charts/latest/rancher-2.8.0.tgz | tar zxvf - -C /tmp

	sed -i -e '/kubeVersion/d' /tmp/rancher/Chart.yaml
fi

cat > ${TARGET_DEPLOY_LOCATION}/rancher/rancher.yaml <<EOF
hostname: rancher-${PLATEFORM}.${DOMAIN_NAME}
tls: ingress
replicas: 1
global:
  cattle:
    psp:
      enabled: false
ingress:
  ingressClassName: nginx
  tls:
    source: secret
    secretName: tls-rancher-ingress
  extraAnnotations:
    "cert-manager.io/cluster-issuer": cert-issuer-prod
    "external-dns.alpha.kubernetes.io/register": 'true'
    "external-dns.alpha.kubernetes.io/ttl": '600'
    "external-dns.alpha.kubernetes.io/target": "${EXTERNAL_DNS_TARGET}"
    "external-dns.alpha.kubernetes.io/hostname": "rancher-${PLATEFORM}.${DOMAIN_NAME}"
EOF

helm upgrade -i rancher "${REPO}" \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--namespace ${NAMESPACE} \
	--values ${TARGET_DEPLOY_LOCATION}/rancher/rancher.yaml

echo_blue_dot_title "Wait Rancher bootstrap"

COUNT=0

while [ -z ${BOOTSTRAP_SECRET} ] && [ ${COUNT} -lt 120 ];
do
	BOOTSTRAP_SECRET=$(kubectl get secret --namespace ${NAMESPACE} bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}' --kubeconfig=${TARGET_CLUSTER_LOCATION}/config 2>/dev/null)
	sleep 1
	echo_blue_dot
	COUNT=$((COUNT+1))
done

echo

echo_title "Rancher setup URL"
echo_blue_bold "https://rancher-${PLATEFORM}.${DOMAIN_NAME}/dashboard/?setup=${BOOTSTRAP_SECRET}" | tee ${TARGET_DEPLOY_LOCATION}/rancher/rancher.log
echo_line
echo

popd &>/dev/null
