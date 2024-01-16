#!/bin/bash
CURDIR=$(dirname $0)
SCHEME="desktop"
NODEGROUP_NAME="${SCHEME}-ca-k8s"
MASTERKUBE=${NODEGROUP_NAME}-masterkube
CONTROLNODES=3
WORKERNODES=3
FORCE=NO
SCHEMEDEFS=${CURDIR}/vars.defs

source ${SCHEMEDEFS}
source $CURDIR/common.sh

pushd ${CURDIR}/../ &>/dev/null

CONFIGURATION_LOCATION=${PWD}

TEMP=$(getopt -o ftg:p:r: --long trace,configuration-location:,defs:,force,node-group:,profile:,region: -n "$0" -- "$@")

eval set -- "${TEMP}"

while true; do
    case "$1" in
        --defs)
            SCHEMEDEFS=$2
            if [ ! -f ${SCHEMEDEFS} ]; then
                echo_red "Multipass definitions: ${SCHEMEDEFS} not found"
                exit 1
            fi
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
            AWS_PROFILE="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -g|--node-group)
            NODEGROUP_NAME=$2
            shift 2
            ;;
        --configuration-location)
            CONFIGURATION_LOCATION=$2
            if [ ! -d ${CONFIGURATION_LOCATION} ]; then
                echo_red_bold "kubernetes output : ${CONFIGURATION_LOCATION} not found"
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

TARGET_CONFIG_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/config
TARGET_DEPLOY_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/deployment
TARGET_CLUSTER_LOCATION=${CONFIGURATION_LOCATION}/cluster/${NODEGROUP_NAME}

echo_blue_bold "Delete masterkube ${MASTERKUBE} previous instance"

function delete_vm_by_name() {
	local VMNAME=$1

    if [ "$(multipass info ${VMNAME} 2>/dev/null)" ]; then
        echo_blue_bold "Delete VM: $VMNAME"
        multipass delete $VMNAME -p
	fi

    delete_host "${VMNAME}"
}

if [ -f ${TARGET_CONFIG_LOCATION}/buildenv ]; then
    source ${TARGET_CONFIG_LOCATION}/buildenv
fi

if [ "$FORCE" = "YES" ]; then
    TOTALNODES=$((WORKERNODES + $CONTROLNODES))

    for NODEINDEX in $(seq 0 $TOTALNODES)
    do
        if [ $NODEINDEX = 0 ]; then
            MASTERKUBE_NODE="${MASTERKUBE}"
        elif [[ $NODEINDEX > $CONTROLNODES ]]; then
            NODEINDEX=$((NODEINDEX - $CONTROLNODES))
            MASTERKUBE_NODE="${NODEGROUP_NAME}-worker-0${NODEINDEX}"
        else
            MASTERKUBE_NODE="${NODEGROUP_NAME}-master-0${NODEINDEX}"
        fi

		delete_vm_by_name ${MASTERKUBE_NODE}
    done

elif [ -f ${TARGET_CLUSTER_LOCATION}/config ]; then
    WORKERNODES=$(kubectl get node -o json --kubeconfig ${TARGET_CLUSTER_LOCATION}/config | jq -r '.items |reverse | .[] | select(.metadata.labels["node-role.kubernetes.io/worker"]) | .metadata.name')

    for NODE in $WORKERNODES
    do
        IPADDR=$(kubectl get node $NODE -o json --kubeconfig ${TARGET_CLUSTER_LOCATION}/config | jq -r '.status.addresses[]|select(.type == "InternalIP")|.address')

        kubectl --kubeconfig ${TARGET_CLUSTER_LOCATION}/config --ignore-daemonsets --delete-emptydir-data drain "${NODE}" 
        kubectl --kubeconfig ${TARGET_CLUSTER_LOCATION}/config delete no "${NODE}"

        if [ "${KUBERNETES_DISTRO}" = "k3s" ]; then
            ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo k3s-killall.sh
        fi

		delete_vm_by_name ${NODE}
    done
	delete_vm_by_name ${MASTERKUBE}
fi

./bin/kubeconfig-delete.sh $MASTERKUBE $NODEGROUP_NAME &> /dev/null

if [ -f ${TARGET_CONFIG_LOCATION}/autoscaler.pid ]; then
    kill ${TARGET_CONFIG_LOCATION}/autoscaler.pid
fi

rm -rf ${TARGET_CLUSTER_LOCATION}
rm -rf ${TARGET_CONFIG_LOCATION}
rm -rf ${TARGET_DEPLOY_LOCATION}

delete_host "${MASTERKUBE}"
delete_host "masterkube-local"

popd &>/dev/null
