#!/bin/bash

set -e

# This script will create a VM used as template
# This step is done by importing https://cloud-images.ubuntu.com/${DISTRO}/current/${DISTRO}-server-cloudimg-amd64.img
# This VM will be used to create the kubernetes template VM 

PRIMARY_NETWORK_NAME="private"
TARGET_IMAGE=
FLAVOR_IMAGE=ds2G
SECURITY_GROUP=default

OPTIONS=(
	"distribution:"
	"custom-image:"
	"ssh-key:"
	"ssh-priv-key:"
	"cni-version:"
	"password:"
	"seed:"
	"arch:"
	"user:"
	"kubernetes-version:"
	"primary-network:"
	"second-network:"
	"k8s-distribution:"
	"container-runtime:"
	"primary-adapter:"
	"flavor:"
	"security-group:"
)

PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o d:i:k:n:p:s:a:u:v:o --long "${PARAMS}"  -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true ; do
	#echo "1:$1"
	case "$1" in
		-d|--distribution)
			DISTRO="$2"
			SEED_IMAGE=${DISTRO}-server-cloudimg-seed
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
		-v|--kubernetes-version) KUBERNETES_VERSION=$2 ; shift 2;;
		--primary-network) PRIMARY_NETWORK_NAME=$2 ; shift 2;;
		--flavor) FLAVOR_IMAGE=$2 ; shift 2;;
		--security-group) SECURITY_GROUP=$2 ; shift 2;;
		--k8s-distribution) 
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

if [ ${KUBERNETES_VERSION:0:1} != "v" ]; then
	KUBERNETES_VERSION="v${KUBERNETES_VERSION}"
fi

if [ -z "${TARGET_IMAGE}" ]; then
	TARGET_IMAGE=${DISTRO}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}
fi

TARGET_IMAGE_ID=$(openstack image list --all -f json | jq -r --arg TARGET_IMAGE ${TARGET_IMAGE} '.[]|select(.Name == $TARGET_IMAGE)|.ID')

if [ -n "${TARGET_IMAGE_ID}" ]; then
	echo_blue_bold "${TARGET_IMAGE} already exists!"
	exit 0
fi

echo_blue_bold "Ubuntu password:${KUBERNETES_PASSWORD}"

NETWORK_ID=$(openstack network list --name ${PRIMARY_NETWORK_NAME} -f json | jq -r '.[]|.ID // ""')
SEED_IMAGE=${DISTRO}-server-cloudimg-${SEED_ARCH}
SEED_IMAGE_URL="https://cloud-images.ubuntu.com/${DISTRO}/current/${SEED_IMAGE}.img"
SEED_IMAGE_ID=$(openstack image list --all -f json | jq -r --arg SEED_IMAGE ${SEED_IMAGE} '.[]|select(.Name == $SEED_IMAGE)|.ID')

if [ -z "${NETWORK_ID}" ]; then
	echo_red_bold "Network ${PRIMARY_NETWORK_NAME}, not found"
	exit 1
fi

if [ -z "${SEED_IMAGE_ID}" ]; then
	[ -f ${CACHE}/${SEED_IMAGE}.img ] || curl -Ls ${SEED_IMAGE_URL} -o ${CACHE}/${SEED_IMAGE}.img

	echo_blue_bold "Import file ${CACHE}/${SEED_IMAGE}.img to image named: ${SEED_IMAGE}"

	SEED_IMAGE_ID=$(openstack image create --container-format bare --disk-format qcow2 --private --file ${CACHE}/${SEED_IMAGE}.img -f json ${SEED_IMAGE} | jq -r '.id//""')

	if [ -z "${SEED_IMAGE_ID}" ]; then
		echo_red_bold "Import failed"
		exit 1
	fi
fi


mkdir -p ${CACHE}/packer/cloud-data

cat > ${CACHE}/packer/cloud-data/user-data <<EOF
#cloud-config
timezone: ${TZ}
package_update: false
package_upgrade: false
ssh_pwauth: true
write_files:
- encoding: gzip+base64
  content: $(cat ${CURDIR}/prepare-image.sh | gzip -c9 | base64 -w 0)
  owner: root:adm
  path: /usr/local/bin/prepare-image.sh
  permissions: '0755'
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

# 	"external_source_image_url": "${SEED_IMAGE_URL}",

OPENSTACK_BUILDER=$(cat <<EOF
{
	"type": "openstack",
	"identity_endpoint": "${OS_AUTH_URL}",
	"domain_name": "${OS_USER_DOMAIN_NAME}",
	"tenant_id": "${OS_PROJECT_ID}",
	"tenant_name": "${OS_PROJECT_NAME}",
	"username": "${OS_USERNAME}",
	"password": "${OS_PASSWORD}",
	"region": "${OS_REGION_NAME}",
	"ssh_username": "packer",
	"ssh_password": "packerpassword",
	"ssh_handshake_attempts": 10,
	"image_name": "${TARGET_IMAGE}",
	"source_image": "${SEED_IMAGE_ID}",
	"flavor": "${FLAVOR_IMAGE}",
	"insecure": "true",
	"ssh_private_key_file": "${SSH_PRIVATE_KEY}",
	"floating_ip_network": "${VC_NETWORK_PUBLIC}",
	"image_visibility": "private",
	"external_source_image_format": "qcow2",
	"security_groups": "${SECURITY_GROUP}",
	"networks": [ "${NETWORK_ID}" ],
	"user_data_file": "${CACHE}/packer/cloud-data/user-data"
}
EOF
)

cat ./templates/packer/template.json | jq --argjson OPENSTACK_BUILDER "${OPENSTACK_BUILDER}" '.builders[0] = $OPENSTACK_BUILDER' > ${CACHE}/packer/template.json

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | tr '.' ' ' | awk '{ print $2 }')
CRIO_VERSION=$(echo -n ${KUBERNETES_VERSION} | tr -d 'v' | tr '.' ' ' | awk '{ print $1"."$2 }')

echo_blue_bold "Prepare ${TARGET_IMAGE} image with cri-o version: ${CRIO_VERSION} and kubernetes: ${KUBERNETES_VERSION}"

INIT_SCRIPT="/usr/local/bin/prepare-image.sh --container-runtime ${CONTAINER_ENGINE} --cni-version ${CNI_VERSION} --cni-plugin ${CNI_PLUGIN} --kubernetes-version ${KUBERNETES_VERSION} --k8s-distribution ${KUBERNETES_DISTRO}"

pushd ${CACHE}/packer/
export PACKER_LOG=1
packer build -var INIT_SCRIPT="${INIT_SCRIPT}" template.json
popd

echo_blue_bold "Created image ${TARGET_IMAGE} with kubernetes version ${KUBERNETES_VERSION}"

exit 0
