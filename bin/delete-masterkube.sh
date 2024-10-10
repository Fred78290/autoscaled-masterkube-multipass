#!/bin/bash
set -eu

CURDIR=$(dirname $0)
FORCE=NO
TRACE=NO
OVERRIDE_PLATEFORMDEFS=
OVERRIDE_AWS_PROFILE=
OVERRIDE_AWS_REGION=
OVERRIDE_NODEGROUP_NAME=
OVERRIDE_CONFIGURATION_LOCATION=
OVERRIDE_KUBERNETES_DISTRO=
PLATEFORM=${PLATEFORM:=multipass}

pushd ${CURDIR}/../ &>/dev/null

OPTIONS=(
	"configuration-location:"
	"defs:"
	"force"
	"kube-engine:"
	"node-group:"
	"plateform:"
	"profile:"
	"region:"
	"trace"
)
PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o ftg:p:r: --long "${PARAMS}" -n "$0" -- "$@")

eval set -- "${TEMP}"

while true; do
	case "$1" in
		--defs)
			OVERRIDE_PLATEFORMDEFS=$2
			if [ ! -f ${OVERRIDE_PLATEFORMDEFS} ]; then
				echo_red "definitions: ${OVERRIDE_PLATEFORMDEFS} not found"
				exit 1
			fi
			shift 2
			;;
		--plateform)
			PLATEFORM="$2"
			shift 2
			;;
		--kube-engine)
			case "$2" in
				kubeadm|k3s|rke2|microk8s)
					OVERRIDE_KUBERNETES_DISTRO=$2
					;;
				*)
					echo "Unsupported kubernetes distribution: $2"
					exit 1
					;;
			esac
			shift 2
			;;
		-f|--force)
			FORCE=YES
			shift 1
			;;
		-t|--trace)
			TRACE=YES
			shift 1
			;;
		-p|--profile)
			OVERRIDE_AWS_PROFILE="$2"
			shift 2
			;;
		-r|--region)
			OVERRIDE_AWS_REGION="$2"
			shift 2
			;;
		-g|--node-group)
			OVERRIDE_NODEGROUP_NAME=$2
			shift 2
			;;
		--configuration-location)
			OVERRIDE_CONFIGURATION_LOCATION=$2
			if [ ! -d ${OVERRIDE_CONFIGURATION_LOCATION} ]; then
				echo_red_bold "kubernetes output : ${OVERRIDE_CONFIGURATION_LOCATION} not found"
				exit 1
			fi
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo_red_bold "$1 - Internal error!"
			exit 1
			;;
	esac
done

if [ "${TRACE}" = "YES" ]; then
	set -x
fi

source "${CURDIR}/common.sh"

if [ -n "${OVERRIDE_KUBERNETES_DISTRO}" ]; then
	KUBERNETES_DISTRO=${OVERRIDE_KUBERNETES_DISTRO}
fi

if [ -n "${OVERRIDE_AWS_PROFILE}" ]; then
	AWS_PROFILE=${OVERRIDE_AWS_PROFILE}
fi

if [ -n "${OVERRIDE_AWS_REGION}" ]; then
	AWS_REGION=${OVERRIDE_AWS_REGION}
fi

if [ -n "${OVERRIDE_NODEGROUP_NAME}" ]; then
	NODEGROUP_NAME=${OVERRIDE_NODEGROUP_NAME}
fi

if [ -n "${OVERRIDE_CONFIGURATION_LOCATION}" ]; then
	CONFIGURATION_LOCATION=${OVERRIDE_CONFIGURATION_LOCATION}
fi

if [ -n "${OVERRIDE_PLATEFORMDEFS}" ]; then
	PLATEFORMDEFS=${OVERRIDE_PLATEFORMDEFS}

	source ${PLATEFORMDEFS}
fi

prepare_environment

echo_blue_bold "Delete masterkube ${MASTERKUBE} previous instance"

#===========================================================================================================================================
#
#===========================================================================================================================================
function all_vm_names() {
	local NAMES=()

	for NODEINDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
	do
		NAMES+=($(get_vm_name ${NODEINDEX}))
	done

	echo ${NAMES[@]}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_all_vms() {
	for NAME in $@
	do
		delete_vm_by_name ${NAME} || true
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function list_nodes() {
	local ALLNODES=$(kubectl get node -o json --kubeconfig ${TARGET_CLUSTER_LOCATION}/config)

	echo ${ALLNODES} | jq -r '.items | .[] | .metadata.annotations["cluster.autoscaler.nodegroup/instance-name"]' | sort -r
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_nodes() {
	local ROLE=

	for ROLE in "node-role.kubernetes.io/worker" "node-role.kubernetes.io/master"
	do
		local ALLNODES=$(kubectl get node -o json --kubeconfig ${TARGET_CLUSTER_LOCATION}/config)
		local NODES=$(echo ${ALLNODES} | jq -r --arg LABEL ${ROLE} '.items | .[] | select(.metadata.labels[$LABEL]) | .metadata.name' | sort -r)

		for NODE in ${NODES}
		do
			kubectl drain --force --ignore-daemonsets --delete-emptydir-data --kubeconfig ${TARGET_CLUSTER_LOCATION}/config ${NODE}
			#kubectl delete no --force --kubeconfig ${TARGET_CLUSTER_LOCATION}/config ${NODE}
		done
	done

	INSTANCENAMES=$(echo ${ALLNODES} | jq -r '.items | .[] | .metadata.annotations["cluster.autoscaler.nodegroup/instance-name"]' | sort -r)

	delete_all_vms ${MASTERKUBE} ${INSTANCENAMES}

	wait_jobs_finish

	rm ${TARGET_CLUSTER_LOCATION}/config
}

#===========================================================================================================================================
#
#===========================================================================================================================================
if [ ! -f ${TARGET_CLUSTER_LOCATION}/config ]; then
	VMNAMES=$(all_vm_names)
	FORCE=YES
else
	VMNAMES=$(list_nodes)

	if [ -f ${TARGET_CONFIG_LOCATION}/buildenv ]; then
		source ${TARGET_CONFIG_LOCATION}/buildenv
	else
		FORCE=YES
	fi
fi

if [ "${FORCE}" = "YES" ]; then
	delete_all_vms ${VMNAMES}
elif [ -f ${TARGET_CLUSTER_LOCATION}/config ]; then
	delete_nodes
fi

wait_jobs_finish

unregister_dns
delete_load_balancers

./bin/kubeconfig-delete.sh ${NODEGROUP_NAME} &> /dev/null || true

if [ -f ${TARGET_CONFIG_LOCATION}/autoscaler.pid ]; then
	kill ${TARGET_CONFIG_LOCATION}/autoscaler.pid
fi

delete_host "${MASTERKUBE}"

popd &>/dev/null

echo_blue_bold "Delete ${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}"

rm -rf "${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}"
