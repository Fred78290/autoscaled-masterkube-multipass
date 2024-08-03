#!/bin/bash

CURDIR=$(dirname $0)

pushd ${CURDIR}/../ &>/dev/null


export NAMESPACE=ingress-nginx
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/ingress
export KUBERNETES_TEMPLATE=

case ${PLATEFORM} in
	aws|openstack|cloudstack)
		KUBERNETES_TEMPLATE=./templates/ingress/nodeport
		;;
	*)
		if [ "${USE_NLB}" == "none" ]; then
			KUBERNETES_TEMPLATE=./templates/ingress/loadbalancer
		else
			KUBERNETES_TEMPLATE=./templates/ingress/nodeport
		fi
		;;
esac

mkdir -p ${ETC_DIR}

sed -e "s/__K8NAMESPACE__/${NAMESPACE}/g" -e "s/__EXTERNAL_DNS_TARGET__/${EXTERNAL_DNS_TARGET}/g" ${KUBERNETES_TEMPLATE}/deploy.yaml > ${ETC_DIR}/deploy.yaml

kubectl apply -f ${ETC_DIR}/deploy.yaml --kubeconfig=${TARGET_CLUSTER_LOCATION}/config

echo -n "Wait for ingress controller availability"

while [ -z "$(kubectl --kubeconfig=${TARGET_CLUSTER_LOCATION}/config get po -n ${NAMESPACE} 2>/dev/null | grep 'ingress-nginx-controller')" ];
do
	sleep 1
	echo -n "."
done

echo

kubectl wait --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--namespace ${NAMESPACE} \
	--for=condition=ready pod \
	--selector=app.kubernetes.io/component=controller --timeout=240s
