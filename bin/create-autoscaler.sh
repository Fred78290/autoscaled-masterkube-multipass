#!/bin/bash
LAUNCH_CA=$1

if [ "${LAUNCH_CA}" == "NO" ]; then
	exit
fi

CURDIR=$(dirname $0)

pushd ${CURDIR}/../ &>/dev/null

MASTER_IP=$(cat ${TARGET_CLUSTER_LOCATION}/manager-ip)
TOKEN=$(cat ${TARGET_CLUSTER_LOCATION}/token)
CACERT=$(cat ${TARGET_CLUSTER_LOCATION}/ca.cert)

export NAMESPACE=kube-system
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/autoscaler
export KUBERNETES_TEMPLATE=./templates/autoscaler
export KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | cut -d . -f 2)
export CLUSTER_AUTOSCALER_VERSION=v1.29.0
export CLOUD_AUTOSCALER_VERSION=v1.29.0
export AUTOSCALER_REGISTRY=${REGISTRY}
export AUTOSCALER_CLOUD_PROVIDER_CONFIG=/etc/cluster/grpc-config.json
export MAX_MEMORY=$(($(echo -n ${MEMORYTOTAL} | cut -d ':' -f 2) * 1024))
export MAX_VCPUS=$(echo -n ${CORESTOTAL} | cut -d ':' -f 2)
export MANAGED_NODES_MAX_VCPUS=$((${MAX_VCPUS} / 2))
export MANAGED_NODES_MAX_MEMORY=$((${MAX_MEMORY} / 2))

if [ "${GRPC_PROVIDER}" = "externalgrpc" ]; then
	AUTOSCALER_REGISTRY=registry.k8s.io/autoscaling
	AUTOSCALER_CLOUD_PROVIDER_CONFIG=/etc/cluster/grpc-config.yaml
fi

case ${KUBERNETES_MINOR_RELEASE} in
	28)
		CLUSTER_AUTOSCALER_VERSION=v1.28.4
		CLOUD_AUTOSCALER_VERSION=v1.30.0
		;;
	29)
		CLUSTER_AUTOSCALER_VERSION=v1.29.2
		CLOUD_AUTOSCALER_VERSION=v1.30.0
		;;
	30|31)
		CLUSTER_AUTOSCALER_VERSION=v1.30.0
		CLOUD_AUTOSCALER_VERSION=v1.30.0
		;;
	*)
		echo "Former version aren't supported by cloud autoscaler"
		exit 1
esac

mkdir -p ${ETC_DIR}

if [ "${LAUNCH_CA}" == "DRY" ]; then
	DRY=--dry-run=client
else
	DRY=
fi

function deploy {
	echo "Create ${ETC_DIR}/$1.yaml"
	echo "---" >> ${ETC_DIR}/autoscaler.yaml

echo $(eval "cat <<EOF
$(<${KUBERNETES_TEMPLATE}/$1.json)
EOF") \
	| yq -p=json -P \
	| tee -a ${ETC_DIR}/autoscaler.yaml \
	| kubectl apply ${DRY} --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
}

echo "---" > ${ETC_DIR}/autoscaler.yaml

kubectl create configmap config-cluster-autoscaler -n kube-system --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-file ${TARGET_CONFIG_LOCATION}/${CLOUD_PROVIDER_CONFIG} \
	--from-file ${TARGET_CONFIG_LOCATION}/provider.json \
	--from-file ${TARGET_CONFIG_LOCATION}/machines.json \
	--from-file ${TARGET_CONFIG_LOCATION}/autoscaler.json \
	--from-file ${TARGET_CLUSTER_LOCATION}/rndc.key \
	| tee -a ${ETC_DIR}/autoscaler.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

echo "---" >> ${ETC_DIR}/autoscaler.yaml

kubectl create configmap kubernetes-pki -n kube-system --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-file ${TARGET_CLUSTER_LOCATION}/kubernetes/pki \
	| tee -a ${ETC_DIR}/autoscaler.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

echo "---" >> ${ETC_DIR}/autoscaler.yaml

if [ "${EXTERNAL_ETCD}" = "true" ]; then
	kubectl create secret generic etcd-ssl -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-file ${TARGET_CLUSTER_LOCATION}/etcd/ssl \
		| tee -a ${ETC_DIR}/autoscaler.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
else
	mkdir -p ${TARGET_CLUSTER_LOCATION}/kubernetes/pki/etcd
	kubectl create secret generic etcd-ssl -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-file ${TARGET_CLUSTER_LOCATION}/kubernetes/pki/etcd \
		| tee -a ${ETC_DIR}/autoscaler.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
fi

echo "---" >> ${ETC_DIR}/autoscaler.yaml

if [ ${PLATEFORM} == "multipass" ] || [ ${PLATEFORM} == "desktop" ]; then
	kubectl create secret generic autoscaler-utility-cert -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-file $(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientKey) \
		--from-file $(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientCertificate) \
		--from-file $(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .Certificate) \
		| tee -a ${ETC_DIR}/autoscaler.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
else
	kubectl create secret generic autoscaler-utility-cert -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		| tee -a ${ETC_DIR}/autoscaler.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
fi

if [ "${PLATEFORM}" != "openstack" ]; then
	echo "---" >> ${ETC_DIR}/autoscaler.yaml
	# Empty configmap for autoscaler deployment
	kubectl create configmap openstack-env -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-literal=OS_CLOUD= \
		| tee -a ${ETC_DIR}/autoscaler.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

	echo "---" >> ${ETC_DIR}/autoscaler.yaml
	
	kubectl create configmap openstack-cloud-config -n kube-system --dry-run=client -o yaml\
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-literal=clouds.yaml= \
		--from-literal=cloud.conf= \
		| tee -a ${ETC_DIR}/autoscaler.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
fi

echo "---" >> ${ETC_DIR}/autoscaler.yaml

deploy service-account-autoscaler
deploy cluster-role
deploy role
deploy cluster-role-binding
deploy role-binding

if [ "${LAUNCH_CA}" == YES ]; then
	deploy deployment
elif [ "${LAUNCH_CA}" == "DEBUG" ]; then
	deploy autoscaler
elif [ "${LAUNCH_CA}" == "LOCAL" ]; then
	GOOS=$(go env GOOS)
	GOARCH=$(go env GOARCH)
	nohup ../out/${GOOS}/${GOARCH}/kubernetes-cloud-autoscaler \
		--kubeconfig=${KUBECONFIG} \
		--distribution=${KUBERNETES_DISTRO} \
		--grpc-provider=${GRPC_PROVIDER} \
		--cloud-provider=${CLOUD_PROVIDER} \
		--machines=${TARGET_CONFIG_LOCATION}/machines.json \
		--plateform=${PLATEFORM} \
		--plateform-config=${TARGET_CONFIG_LOCATION}/provider.json \
		--config=${TARGET_CONFIG_LOCATION}/autoscaler.json \
		--save=${TARGET_CONFIG_LOCATION}/state.json \
		--log-level=info 1>>${TARGET_CONFIG_LOCATION}/autoscaler.log 2>&1 &
	pid="$!"

	echo -n "$pid" > ${TARGET_CONFIG_LOCATION}/autoscaler.pid

	deploy autoscaler
else
	deploy deployment
fi

popd &>/dev/null
