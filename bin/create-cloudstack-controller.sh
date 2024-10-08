#!/bin/bash
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/cloud-provider-cloudstack

mkdir -p ${ETC_DIR}

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | awk -F. '{ print $2 }')

cat > ${ETC_DIR}/cloud-config <<EOF
[Global]
api-url = ${CLOUDSTACK_API_URL}
api-key = ${CLOUDSTACK_API_KEY}
secret-key = ${CLOUDSTACK_SECRET_KEY}
project-id = ${CLOUDSTACK_PROJECT_ID}
zone = ${CLOUDSTACK_ZONE_NAME}
ssl-no-verify = true
EOF

kubectl create secret generic cloudstack-secret \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	-n kube-system \
	--dry-run=client -o yaml \
	--from-file=${ETC_DIR}/cloud-config \
	| tee ${ETC_DIR}/cloudstack-secret.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

curl -sL https://github.com/apache/cloudstack-kubernetes-provider/releases/download/v1.1.0/deployment.yaml \
	| tee ${ETC_DIR}/deployment.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
