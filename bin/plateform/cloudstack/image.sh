#!/bin/bash

set -e

# This script will create a VM used as template
# This step is done by importing https://cloud-images.ubuntu.com/${DISTRO}/current/${DISTRO}-server-cloudimg-amd64.img
# This VM will be used to create the kubernetes template VM 

PRIMARY_NETWORK_NAME="default"
TARGET_IMAGE=
FLAVOR_IMAGE=tiny
SECURITY_GROUP=default
CLOUDSTACK_TEMPLATE_TYPE=user

OPTIONS=(
	"arch:"
	"cni-version:"
	"container-runtime:"
	"custom-image:"
	"distribution:"
	"flavor:"
	"kube-engine:"
	"kube-version:"
	"password:"
	"primary-adapter:"
	"primary-network:"
	"second-network:"
	"security-group:"
	"seed:"
	"ssh-key:"
	"ssh-priv-key:"
	"user:"
	"cloudstack-zone-id:"
	"cloudstack-pod-id:"
	"cloudstack-cluster-id:"
	"cloudstack-host-id:"
	"cloudstack-hypervisor:"
	"cloudstack-project-id:"
	"cloudstack-network-id:"
	"cloudstack-vpc-id:"
	"cloudstack-api-url:"
	"cloudstack-api-key:"
	"cloudstack-api-secret:"
	"cloudstack-keypair:"
	"cloudstack-template-type:"
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
		-v|--kube-version) KUBERNETES_VERSION=$2 ; shift 2;;
		--primary-network) PRIMARY_NETWORK_NAME=$2 ; shift 2;;
		--flavor) FLAVOR_IMAGE=$2 ; shift 2;;
		--security-group) SECURITY_GROUP=$2 ; shift 2;;
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

		--cloudstack-api-url)
			CLOUDSTACK_API_URL=$2
			shift 2;;

		--cloudstack-api-key)
			CLOUDSTACK_API_KEY=$2
			shift 2;;

		--cloudstack-api-secret)
			CLOUDSTACK_SECRET_KEY=$2
			shift 2;;

		--cloudstack-zone-id)
			CLOUDSTACK_ZONE_ID=$2
			shift 2;;

		--cloudstack-pod-id)
			CLOUDSTACK_POD_ID=$2
			shift 2;;

		--cloudstack-cluster-id)
			CLOUDSTACK_CLUSTER_ID=$2
			shift 2;;

		--cloudstack-host-id)
			LOUDSTACK_HOST_ID=$2
			shift 2;;

		--cloudstack-hypervisor)
			CLOUDSTACK_HYPERVISOR=$2
			shift 2;;

		--cloudstack-project-id)
			CLOUDSTACK_PROJECT_ID=$2
			shift 2;;

		--cloudstack-network-id)
			CLOUDSTACK_NETWORK_ID=$2
			shift 2;;

		--cloudstack-vpc-id)
			CLOUDSTACK_VPC_ID=$2
			shift 2;;

		--cloudstack-keypair)
			SSH_KEYNAME=$2
			shift 2;;

		--cloudstack-template-type)
			CLOUDSTACK_TEMPLATE_TYPE=$2
			shift 2;;

		--) shift ; break ;;
		*) echo_red_bold "$1 - Internal error!" ; exit 1 ;;
	esac
done

#===========================================================================================================================================
#
#===========================================================================================================================================
function cloudmonkey() {
	local ARGS=()
	local ARG=
	local VALUE=
	local OUTPUT=

	# Drop empty argument
	for ARG in $@
	do
		if [[ ${ARG} =~ "=" ]]; then
			IFS== read ARG VALUE <<<"${ARG}"

			if [ -n "${VALUE}" ]; then
				ARGS+=(${ARG}="'${VALUE}'")
			fi
		else
			ARGS+=(${ARG})
		fi
	done

	OUTPUT=$(eval "cmk -o json ${ARGS[@]} || echo '{}'")

	if [ -z "${OUTPUT}" ]; then
		OUTPUT='{}'
	fi

	if [ "${VERBOSE}" == "YES" ]; then
		echo_blue_bold "cmk -o json ${ARGS[@]}" > /dev/stderr
		jq -r . <<<"${OUTPUT}" > /dev/stderr
	fi

	echo -n "${OUTPUT}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================

if [ ${KUBERNETES_VERSION:0:1} != "v" ]; then
	KUBERNETES_VERSION="v${KUBERNETES_VERSION}"
fi

if [ -z "${TARGET_IMAGE}" ]; then
	TARGET_IMAGE=${DISTRO}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}
fi

TARGET_IMAGE_ID=$(cloudmonkey list templates \
	name=${TARGET_IMAGE} \
	templatefilter=self \
	templatetype=${CLOUDSTACK_TEMPLATE_TYPE} \
	projectid=${CLOUDSTACK_PROJECT_ID} \
	hypervisor=${CLOUDSTACK_HYPERVISOR} | jq -r '.template[0].id//""')

if [ -n "${TARGET_IMAGE_ID}" ]; then
	echo_blue_bold "${TARGET_IMAGE} already exists!"
	exit 0
fi

echo_blue_bold "Ubuntu password:${KUBERNETES_PASSWORD}"

SEED_IMAGE=${DISTRO}-server-cloudimg-${SEED_ARCH}
SEED_IMAGE_URL="https://cloud-images.ubuntu.com/${DISTRO}/current/${SEED_IMAGE}.img"
SHASUM256=$(curl -sL https://cloud-images.ubuntu.com/releases/${DISTRO}/release/SHA256SUMS | grep server-cloudimg-amd64.img)
UBUNTU_VERSION=$(echo ${SHASUM256} | cut -d '-' -f 2)

SEED_IMAGE_ID=$(cloudmonkey list templates \
	name=${SEED_IMAGE} \
	templatefilter=self \
	templatetype=${CLOUDSTACK_TEMPLATE_TYPE} \
	projectid=${CLOUDSTACK_PROJECT_ID} \
	hypervisor=${CLOUDSTACK_HYPERVISOR} | jq -r '.template[0].id//""')

OSCATEGORYID=$(cloudmonkey list oscategories name=ubuntu | jq -r '.oscategory[0].id//""')
OSTYPEID=$(cloudmonkey list ostypes filter=id,name oscategoryid=${OSCATEGORYID} | jq --arg NAME "Ubuntu ${UBUNTU_VERSION}" -r '.ostype[] | select(.name | startswith($NAME)) | .id//""')

if [ -z "${OSTYPEID}" ]; then
	OSTYPEID=$(cloudmonkey list ostypes filter=id,name oscategoryid=${OSCATEGORYID} | jq --arg NAME "Ubuntu 22.04 LTS" -r '.ostype[] | select(.name | startswith($NAME)) | .id//""')
fi

if [ -z "${SEED_IMAGE_ID}" ]; then
	echo_blue_bold "Import Url ${SEED_IMAGE_URL} to image named: ${SEED_IMAGE}"

	SEED_IMAGE_REGISTED=$(cloudmonkey register template \
		name="${SEED_IMAGE}" \
		displaytext="${SEED_IMAGE}" \
		isextractable=false \
		isfeatured=false \
		ispublic=false \
		passwordenabled=false \
		templatetype=${CLOUDSTACK_TEMPLATE_TYPE} \
		projectid=${CLOUDSTACK_PROJECT_ID} \
		zoneid=${CLOUDSTACK_ZONE_ID} \
		ostypeid=${OSTYPEID} \
		format=QCOW2 \
		hypervisor=${CLOUDSTACK_HYPERVISOR} \
		url="${SEED_IMAGE_URL}")

    SEED_IMAGE_ID=$(jq -r '.template[0].id//""' <<< "${SEED_IMAGE_REGISTED}")

	if [ -z "${SEED_IMAGE_ID}" ]; then
		echo_red_bold "Import failed"
		exit 1
	fi

	echo_blue_dot_title "Wait for template ${TARGET_IMAGE}, id: ${SEED_IMAGE_ID} to be ready"

	while [ "$(jq -r '.template[0].isready' <<< "${SEED_IMAGE_REGISTED}")" == "false" ];
	do
		sleep 5
		echo_blue_dot
		SEED_IMAGE_REGISTED=$(cloudmonkey list templates id=${SEED_IMAGE_ID} templatefilter=self projectid=${CLOUDSTACK_PROJECT_ID})
	done

	echo $(jq -r '.template[0].isready' <<< "${SEED_IMAGE_REGISTED}")
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

CLOUDSTACK_BUILDER=$(cat <<EOF
{
	"type": "cloudstack",
	"api_key": "${CLOUDSTACK_API_KEY}",
	"api_url": "${CLOUDSTACK_API_URL}",
	"secret_key": "${CLOUDSTACK_SECRET_KEY}",
	"network": "${CLOUDSTACK_NETWORK_ID}",
	"source_template": "${SEED_IMAGE_ID}",
	"service_offering": "${FLAVOR_IMAGE}",
	"ssh_username": "packer",
	"ssh_password": "packerpassword",
	"ssh_handshake_attempts": 10,
	"ssl_no_verify": true,
	"template_os": "${OSTYPEID}",
	"zone": "${CLOUDSTACK_ZONE_ID}",
	"expunge": true,
	"communicator": "ssh",
	"ssh_timeout": "20m",
	"disk_size": 10,
	"template_name": "${TARGET_IMAGE}",
	"template_public": false,
	"template_display_text": "${TARGET_IMAGE}",
	"template_featured": false,
	"template_password_enabled": false,
	"hypervisor": "${CLOUDSTACK_HYPERVISOR}",
	"ssh_keypair_name": "${SSH_KEYNAME}",
	"project": "${CLOUDSTACK_PROJECT_ID}",
	"template_requires_hvm": true,
	"use_local_ip_address": true,
	"user_data_file": "${CACHE}/packer/cloud-data/user-data"
}
EOF
)

cat ./templates/packer/template.json | jq --argjson CLOUDSTACK_BUILDER "${CLOUDSTACK_BUILDER}" '.builders[0] = $CLOUDSTACK_BUILDER' > ${CACHE}/packer/template.json

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | tr '.' ' ' | awk '{ print $2 }')
CRIO_VERSION=$(echo -n ${KUBERNETES_VERSION} | tr -d 'v' | tr '.' ' ' | awk '{ print $1"."$2 }')

echo_blue_bold "Prepare ${TARGET_IMAGE} image with cri-o version: ${CRIO_VERSION} and kubernetes: ${KUBERNETES_VERSION}"

INIT_SCRIPT="/usr/local/bin/prepare-image.sh --container-runtime ${CONTAINER_ENGINE} --cni-version ${CNI_VERSION} --cni-plugin ${CNI_PLUGIN} --kube-version ${KUBERNETES_VERSION} --kube-engine ${KUBERNETES_DISTRO} --plateform cloudstack"

pushd ${CACHE}/packer/
export PACKER_LOG=1
packer build -var INIT_SCRIPT="${INIT_SCRIPT}" template.json
popd

echo_blue_bold "Created image ${TARGET_IMAGE} with kubernetes version ${KUBERNETES_VERSION}"

exit 0
