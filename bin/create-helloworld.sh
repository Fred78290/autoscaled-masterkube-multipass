#!/bin/bash
CURDIR=$(dirname $0)

pushd ${CURDIR}/../ &>/dev/null

export NAMESPACE=kube-public
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/helloworld
export KUBERNETES_TEMPLATE=./templates/helloworld

mkdir -p ${ETC_DIR}

function deploy {
	echo "Create ${ETC_DIR}/$1.json"
echo $(eval "cat <<EOF
$(<${KUBERNETES_TEMPLATE}/$1.json)
EOF") | jq . | tee ${ETC_DIR}/$1.json | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
}

deploy deployment
deploy service
deploy ingress
