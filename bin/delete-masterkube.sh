#!/bin/bash
CURDIR=$(dirname $0)
FORCE=NO
TRACE=NO
OVERRIDE_PLATEFORMDEFS=
OVERRIDE_AWS_PROFILE=
OVERRIDE_AWS_REGION=
OVERRIDE_NODEGROUP_NAME=
OVERRIDE_CONFIGURATION_LOCATION=

pushd ${CURDIR}/../ &>/dev/null

TEMP=$(getopt -o ftg:p:r: --long trace,configuration-location:,defs:,force,node-group:,profile:,region:,plateform: -n "$0" -- "$@")

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

	TARGET_CONFIG_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/config
	TARGET_DEPLOY_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/deployment
	TARGET_CLUSTER_LOCATION=${CONFIGURATION_LOCATION}/cluster/${NODEGROUP_NAME}
fi

if [ -n "${OVERRIDE_PLATEFORMDEFS}" ]; then
	PLATEFORMDEFS=${OVERRIDE_PLATEFORMDEFS}

	source ${PLATEFORMDEFS}
fi

echo_blue_bold "Delete masterkube ${MASTERKUBE} previous instance"

if [ -f ${TARGET_CONFIG_LOCATION}/buildenv ]; then
	source ${TARGET_CONFIG_LOCATION}/buildenv
fi

if [ "${FORCE}" = "YES" ]; then
	TOTALNODES=$((WORKERNODES + ${CONTROLNODES}))

	for NODEINDEX in $(seq 0 ${TOTALNODES})
	do
		if [ ${NODEINDEX} = 0 ]; then
			MASTERKUBE_NODE="${MASTERKUBE}"
		elif [[ ${NODEINDEX} > ${CONTROLNODES} ]]; then
			NODEINDEX=$((NODEINDEX - ${CONTROLNODES}))
			MASTERKUBE_NODE="${NODEGROUP_NAME}-worker-0${NODEINDEX}"
		else
			MASTERKUBE_NODE="${NODEGROUP_NAME}-master-0${NODEINDEX}"
		fi

		delete_vm_by_name ${MASTERKUBE_NODE}
	done

elif [ -f ${TARGET_CLUSTER_LOCATION}/config ]; then
	WORKERNODES=$(kubectl get node -o json --kubeconfig ${TARGET_CLUSTER_LOCATION}/config | jq -r '.items |reverse | .[] | select(.metadata.labels["node-role.kubernetes.io/worker"]) | .metadata.name')

	for NODE in ${WORKERNODES}
	do
		delete_vm_by_name ${NODE}
	done
	delete_vm_by_name ${MASTERKUBE}
fi

unregister_dns
wait_jobs_finish

./bin/kubeconfig-delete.sh ${MASTERKUBE} ${NODEGROUP_NAME} &> /dev/null || true

if [ -f ${TARGET_CONFIG_LOCATION}/autoscaler.pid ]; then
	kill ${TARGET_CONFIG_LOCATION}/autoscaler.pid
fi

delete_host "${MASTERKUBE}"
delete_host "masterkube-${PLATEFORM}"

echo TARGET_CLUSTER_LOCATION=$TARGET_CLUSTER_LOCATION
exit
rm -rf ${TARGET_CLUSTER_LOCATION}/*
rm -rf ${TARGET_CONFIG_LOCATION}/*
rm -rf ${TARGET_DEPLOY_LOCATION}/*

popd &>/dev/null
