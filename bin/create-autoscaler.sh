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
export CLUSTER_AUTOSCALER_VERSION=v1.29.
export CLOUD_AUTOSCALER_VERSION=v1.29.0
export AUTOSCALER_REGISTRY=${REGISTRY}
export CLOUD_PROVIDER_CONFIG=/etc/cluster/grpc-config.json
export USE_VANILLA_GRPC_ARGS=--no-use-vanilla-grpc
export USE_CONTROLER_MANAGER_ARGS="--use-controller-manager"
export MAX_MEMORY=$(($(echo -n ${MEMORYTOTAL} | cut -d ':' -f 2) * 1024))
export MAX_VCPUS=$(echo -n ${CORESTOTAL} | cut -d ':' -f 2)

if [ "${GRPC_PROVIDER}" = "externalgrpc" ]; then
	USE_VANILLA_GRPC_ARGS=--use-vanilla-grpc
	AUTOSCALER_REGISTRY=registry.k8s.io/autoscaling
	CLOUD_PROVIDER_CONFIG=/etc/cluster/grpc-config.yaml
fi

if [ -z "${CLOUD_PROVIDER}" ]; then
	USE_CONTROLER_MANAGER_ARGS="--no-use-controller-manager"
fi

case ${KUBERNETES_MINOR_RELEASE} in
	29)
		CLUSTER_AUTOSCALER_VERSION=v1.29.0
		CLOUD_AUTOSCALER_VERSION=v1.29.0
		;;
	*)
		echo "Former version aren't supported by cloud autoscaler"
		exit 1
esac

mkdir -p ${ETC_DIR}

function deploy {
	echo "Create ${ETC_DIR}/$1.json"
echo $(eval "cat <<EOF
$(<${KUBERNETES_TEMPLATE}/$1.json)
EOF") | jq . | tee ${ETC_DIR}/$1.json | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
}

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
		--provider=${PLATEFORM} \
		--config=${TARGET_CONFIG_LOCATION}/autoscaler.json \
		--provider-config=${TARGET_CONFIG_LOCATION}/provider.json \
		--save=${TARGET_CONFIG_LOCATION}/autoscaler-state.json \
		--log-level=info 1>>${TARGET_CONFIG_LOCATION}/autoscaler.log 2>&1 &
	pid="$!"

	echo -n "$pid" > ${TARGET_CONFIG_LOCATION}/autoscaler.pid

	deploy autoscaler
else
	deploy deployment
fi

popd &>/dev/null
