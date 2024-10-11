#!/bin/bash

set -e

# This script will create a VM used as template
# This step is done by importing https://cloud-images.ubuntu.com/${UBUNTU_DISTRIBUTION}/current/${UBUNTU_DISTRIBUTION}-server-cloudimg-amd64.img
# This VM will be used to create the kubernetes template VM 

PRIMARY_NETWORK_NAME="lxdbr0"
SECOND_NETWORK_NAME="lxdbr1"
TARGET_IMAGE=
VIRTUALMACHINE=false

OPTIONS=(
	"arch:"
	"cni-version:"
	"container-runtime:"
	"custom-image:"
	"distribution:"
	"kube-engine:"
	"kube-version:"
	"lxd-profile:"
	"lxd-project:"
	"lxd-remote:"
	"lxd-container-type:"
	"password:"
	"primary-adapter:"
	"primary-network:"
	"second-adapter:"
	"second-network:"
	"seed:"
	"ssh-key:"
	"ssh-priv-key:"
	"user:"
)

PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o d:i:k:n:p:s:a:u:v:o --long "${PARAMS}"  -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true ; do
	#echo "1:$1"
	case "$1" in
		-d|--distribution)
			UBUNTU_DISTRIBUTION="$2"
			shift 2
			;;
		-i|--custom-image) TARGET_IMAGE="$2" ; shift 2;;
		-k|--ssh-key) SSH_KEY=$2 ; shift 2;;
		--ssh-priv-key) SSH_PRIVATE_KEY=$2 ; shift 2;;
		-n|--cni-version) CNI_VERSION=$2 ; shift 2;;
		-p|--password) KUBERNETES_PASSWORD=$2 ; shift 2;;
		-s|--seed) SEED_IMAGE=$2 ; shift 2;;
		-a|--arch) SEED_ARCH=$2 ; shift 2;;
		-u|--user) KUBERNETES_USER=$2 ; shift 2;;
		-v|--kube-version) KUBERNETES_VERSION=$2 ; shift 2;;
		--primary-network) PRIMARY_NETWORK_NAME=$2 ; shift 2;;
		--second-network) SECOND_NETWORK_NAME=$2 ; shift 2;;

		--lxd-profile) LXD_KUBERNETES_PROFILE="$2" ; shift 2;;
		--lxd-project) LXD_PROJECT="$2" ; shift 2;;
		--lxd-remote) LXD_REMOTE="$2" ; shift 2;;
		--lxd-container-type) LXD_CONTAINER_TYPE="$2" ; shift 2;;

		--kube-engine) 
			case "$2" in
				kubeadm|k3s|rke2|microk8s)
				KUBERNETES_DISTRO=$2
				;;
			*)
				echo "Unsupported kubernetes distribution: $2"
				exit 1
				;;
			esac
			shift 2
			;;
		--container-runtime)
			case "$2" in
				"docker")
					CONTAINER_ENGINE="$2"
					CONTAINER_CTL=docker
					;;
				"cri-o"|"containerd")
					CONTAINER_ENGINE="$2"
					CONTAINER_CTL=crictl
					;;
				*)
					echo_red_bold "Unsupported container runtime: $2"
					exit 1
					;;
			esac
			shift 2;;
		--) shift ; break ;;
		*) echo_red_bold "$1 - Internal error!" ; exit 1 ;;
	esac
done

#===========================================================================================================================================
#
#===========================================================================================================================================
pushd ${CURDIR} > /dev/null
PREPARE_SCRIPT=${PWD}/prepare-image.sh
popd > /dev/null

if [ ${KUBERNETES_VERSION:0:1} != "v" ]; then
	KUBERNETES_VERSION="v${KUBERNETES_VERSION}"
fi

if [ -z "${TARGET_IMAGE}" ]; then
	TARGET_IMAGE=${UBUNTU_DISTRIBUTION}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}
fi

lxc project switch ${LXD_REMOTE}:${LXD_PROJECT}

SEED_IMAGE_ID=$(lxc image alias list ubuntu: --format=json | jq --arg UBUNTU_DISTRIBUTION ${UBUNTU_DISTRIBUTION} --arg CONTAINERTYPE ${LXD_CONTAINER_TYPE} '.[]|select(.name == $UBUNTU_DISTRIBUTION and .type == $CONTAINERTYPE)') 
TARGET_IMAGE_ID=$(lxc image list ${LXD_REMOTE}: name=${TARGET_IMAGE} type=${LXD_CONTAINER_TYPE} --project ${LXD_PROJECT} --format=json | jq -r --arg TARGET_IMAGE "${TARGET_IMAGE}" '.[0].fingerprint//""')

if [ -n "${TARGET_IMAGE_ID}" ]; then
	echo_blue_bold "${TARGET_IMAGE} already exists!"
	exit 0
fi

echo_blue_bold "Ubuntu password:${KUBERNETES_PASSWORD}"

mkdir -p ${CACHE}/packer/profile

lxc profile delete ${LXD_REMOTE}:${TARGET_IMAGE}-profile 2> /dev/null || :

lxc profile create ${LXD_REMOTE}:${TARGET_IMAGE}-profile

cat > ${CACHE}/packer/profile/config.yaml <<EOF
description: ${TARGET_IMAGE} profile
config:
  limits.cpu: 2
  limits.memory: 2048MiB
  boot.autostart: "true"
  linux.kernel_modules: ip_vs,ip_vs_rr,ip_vs_wrr,ip_vs_sh,ip_tables,ip6_tables,netlink_diag,nf_nat,overlay,br_netfilter
  raw.lxc: |
    lxc.apparmor.profile=unconfined
    lxc.mount.auto=proc:rw sys:rw cgroup:rw
    lxc.cgroup.devices.allow=a
    lxc.cap.drop=
  security.nesting: "true"
  security.privileged: "true"
  cloud-init.user-data: |
    #cloud-config
    timezone: ${TZ}
    package_update: false
    package_upgrade: false
    ssh_pwauth: true
    users:
    - name: ${KUBERNETES_USER}
      groups: users, admin
      lock_passwd: false
      sudo: ALL=(ALL) NOPASSWD:ALL
      shell: /bin/bash
      plain_text_passwd: ${KUBERNETES_PASSWORD}
      ssh_authorized_keys:
      - ${SSH_KEY}
    - name: packer
      sudo: ALL=(ALL) NOPASSWD:ALL
      groups: users, admin
      lock_passwd: false
      plain_text_passwd: packerpassword
      ssh_authorized_keys:
      - ${SSH_KEY}
    apt:
      preserve_sources_list: true
devices:
  eth0:
    type: nic
    network: ${PRIMARY_NETWORK_NAME}
  root:
    path: /
    pool: default
    type: disk
EOF

if [ ${LXD_CONTAINER_TYPE} == "virtual-machine" ]; then
	VIRTUALMACHINE=true
else
	cat >> ${CACHE}/packer/profile/config.yaml <<EOF
  aadisable:
    path: /sys/module/nf_conntrack/parameters/hashsize
    source: /sys/module/nf_conntrack/parameters/hashsize
    type: disk
  aadisable2:
    path: /dev/kmsg
    source: /dev/kmsg
    type: unix-char
  aadisable3:
    path: /sys/fs/bpf
    source: /sys/fs/bpf
    type: disk
  aadisable4:
    path: /proc/sys/net/netfilter/nf_conntrack_max
    source: /proc/sys/net/netfilter/nf_conntrack_max
    type: disk
EOF
fi

lxc profile edit ${LXD_REMOTE}:${TARGET_IMAGE}-profile < ${CACHE}/packer/profile/config.yaml

LXD_BUILDER=$(cat <<EOF
{
	"type": "lxd",
	"image": "ubuntu:${UBUNTU_DISTRIBUTION}",
	"output_image": "${TARGET_IMAGE}-${LXD_CONTAINER_TYPE}",
	"container_name": "${TARGET_IMAGE}",
	"virtual_machine": "${VIRTUALMACHINE}",
	"publish_remote_name": "${LXD_REMOTE%}",
	"profile": "${TARGET_IMAGE}-profile",
	"publish_properties": {
		"name": "${TARGET_IMAGE}",
		"description": "${TARGET_IMAGE}"
	}
}
EOF
)

cat ./templates/packer/template.json | jq --argjson LXD_BUILDER "${LXD_BUILDER}" '.builders[0] = $LXD_BUILDER' > ${CACHE}/packer/template.json

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | tr '.' ' ' | awk '{ print $2 }')
CRIO_VERSION=$(echo -n ${KUBERNETES_VERSION} | tr -d 'v' | tr '.' ' ' | awk '{ print $1"."$2 }')

echo_blue_bold "Prepare ${TARGET_IMAGE} image with cri-o version: ${CRIO_VERSION} and kubernetes: ${KUBERNETES_VERSION}"

INIT_SCRIPT="/usr/local/bin/prepare-image.sh --container-runtime ${CONTAINER_ENGINE} --cni-version ${CNI_VERSION} --cni-plugin ${CNI_PLUGIN} --kube-version ${KUBERNETES_VERSION} --kube-engine ${KUBERNETES_DISTRO} --plateform cloudstack"

pushd ${CACHE}/packer/
export PACKER_LOG=1
packer build -var INIT_SCRIPT="${INIT_SCRIPT}" -var PREPARE_SCRIPT="${PREPARE_SCRIPT}" template.json
popd

echo_blue_bold "Created image ${TARGET_IMAGE} with kubernetes version ${KUBERNETES_VERSION}"

lxc profile delete ${LXD_REMOTE}:${TARGET_IMAGE}-profile

lxc project switch ${LXD_REMOTE}:default

exit 0
