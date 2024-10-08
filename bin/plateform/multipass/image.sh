#!/bin/bash

set -e

# This script will create a VM used as template
# This step is done by importing https://cloud-images.ubuntu.com/${UBUNTU_DISTRIBUTION}/current/${UBUNTU_DISTRIBUTION}-server-cloudimg-amd64.img
# This VM will be used to create the kubernetes template VM 

PRIMARY_NETWORK_NAME="mpbr0"
SECOND_NETWORK_NAME="lxdbr0"
TARGET_IMAGE=

OPTIONS=(
	"arch:"
	"cni-version:"
	"container-runtime:"
	"custom-image:"
	"distribution:"
	"kube-engine:"
	"kube-version:"
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
			SEED_IMAGE=${UBUNTU_DISTRIBUTION}-server-cloudimg-seed
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
	TARGET_IMAGE=${CURDIR}/../images/${UBUNTU_DISTRIBUTION}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}.img
fi

if [ -f "${TARGET_IMAGE}" ]; then
	echo_blue_bold "${TARGET_IMAGE} already exists!"
	exit 0
fi

echo_blue_bold "Ubuntu password:${KUBERNETES_PASSWORD}"

mkdir -p ${CACHE}/packer/cloud-data

cat > ${CACHE}/packer/cloud-data/meta-data <<EOF
instance-id: $(uuidgen)/packer
EOF

cat > ${CACHE}/packer/cloud-data/user-data <<EOF
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
EOF

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | tr '.' ' ' | awk '{ print $2 }')
CRIO_VERSION=$(echo -n ${KUBERNETES_VERSION} | tr -d 'v' | tr '.' ' ' | awk '{ print $1"."$2 }')

echo_blue_bold "Prepare ${TARGET_IMAGE} image with cri-o version: ${CRIO_VERSION} and kubernetes: ${KUBERNETES_VERSION}"
read ISO_CHECKSUM ISO_FILE <<< "$(curl -s http://cloud-images.ubuntu.com/${UBUNTU_DISTRIBUTION}/current/SHA256SUMS | grep server-cloudimg-${SEED_ARCH}.img | tr -d '*')" 

ACCEL=kvm
CPU_HOST=host

pushd ${CURDIR}/..

if [ ${SEED_ARCH} == "amd64" ]; then
	cp ./templates/packer/template.json ${CACHE}/packer/template.json

	QEMU_BINARY=qemu-system-x86_64
	MACHINE_TYPE="pc"

	if [ "${OSDISTRO}" == "Darwin" ]; then
		ACCEL=hvf
		CPU_HOST="host"
	fi
else
	QEMU_BINARY=qemu-system-aarch64
	MACHINE_TYPE="virt"

	jq --arg BIOS "${PWD}/templates/packer/qemu-efi-aarch64/QEMU_EFI.fd" '.builders[0].qemuargs += [[ "-bios", $BIOS ], [ "-monitor","stdio" ], [ "-display", "cocoa" ]]' \
		./templates/packer/template.json > ${CACHE}/packer/template.json

	if [ "${OSDISTRO}" == "Darwin" ]; then
		ACCEL=hvf
	fi
fi

popd

INIT_SCRIPT="/usr/local/bin/prepare-image.sh --container-runtime ${CONTAINER_ENGINE} --cni-version ${CNI_VERSION} --cni-plugin ${CNI_PLUGIN} --kube-version ${KUBERNETES_VERSION} --kube-engine ${KUBERNETES_DISTRO} --plateform multipass"

pushd ${CACHE}/packer

mkisofs -output cidata.iso -volid cidata -joliet -rock cloud-data/user-data cloud-data/meta-data

rm -rf output-qemu
export PACKER_LOG=1
packer build \
	-var QEMU_BINARY=${QEMU_BINARY} \
	-var CDROM=${CACHE}/packer/cidata.iso \
	-var CPU_HOST="${CPU_HOST}" \
	-var MACHINE_TYPE="${MACHINE_TYPE}" \
	-var UBUNTU_DISTRIBUTION=${UBUNTU_DISTRIBUTION} \
	-var ACCEL=${ACCEL} \
	-var SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY}" \
	-var ISO_CHECKSUM="sha256:${ISO_CHECKSUM}" \
	-var ISO_FILE="${ISO_FILE}" \
	-var PREPARE_SCRIPT="${PREPARE_SCRIPT}" \
	-var INIT_SCRIPT="${INIT_SCRIPT}" \
	template.json

mv output-qemu/packer-qemu ${TARGET_IMAGE}
popd

echo_blue_bold "Created image ${TARGET_IMAGE} with kubernetes version ${KUBERNETES_VERSION}"

exit 0
