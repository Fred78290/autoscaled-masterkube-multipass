#!/bin/bash

# This script create every thing to deploy a simple kubernetes autoscaled cluster with ${PLATEFORM}.
# It will generate:
# Custom image with every thing for kubernetes
# Config file to deploy the cluster autoscaler.
# kubectl run busybox --rm -ti --image=busybox -n kube-public /bin/sh

set -eu

CLUSTER_NODES=
ETCD_ENDPOINT=

function usage() {
	common_usage
	cat <<EOF
### Flags ${PLATEFORM} plateform specific
  # Flags to set the template vm
--target-image=<value>                         # Override the prefix template VM image used for created VM, default ${ROOT_IMG_NAME}
--seed-image=<value>                           # Override the seed image name used to create template, default ${SEED_IMAGE}
--kubernetes-user=<value>                      # Override the seed user in template, default ${KUBERNETES_USER}
--kubernetes-password | -p=<value>             # Override the password to ssh the cluster VM, default random word

  # Flags in ha mode only
--use-keepalived | -u                          # Use keepalived as load balancer else NGINX is used  # Flags to configure nfs client provisionner

  # Flags to configure network in ${PLATEFORM}
--public-address=<value>                       # The public address to expose kubernetes endpoint[ipv4/cidr, DHCP, NONE], default ${PUBLIC_IP}
--no-dhcp-autoscaled-node                      # Autoscaled node don't use DHCP, default ${SCALEDNODES_DHCP}
--vm-private-network=<value>                   # Override the name of the private network in ${PLATEFORM}, default ${VC_NETWORK_PRIVATE}
--vm-public-network=<value>                    # Override the name of the public network in ${PLATEFORM}, empty for none second interface, default ${VC_NETWORK_PUBLIC}
--net-address=<value>                          # Override the IP of the kubernetes control plane node, default ${NET_IP}
--net-gateway=<value>                          # Override the IP gateway, default ${NET_GATEWAY}
--net-dns=<value>                              # Override the IP DNS, default ${NET_DNS}
--net-domain=<value>                           # Override the domain name, default ${NET_DOMAIN}
--metallb-ip-range                             # Override the metalb ip range, default ${METALLB_IP_RANGE}
--dont-use-dhcp-routes-private                 # Tell if we don't use DHCP routes in private network, default ${USE_DHCP_ROUTES_PRIVATE}
--dont-use-dhcp-routes-public                  # Tell if we don't use DHCP routes in public network, default ${USE_DHCP_ROUTES_PUBLIC}
--add-route-private                            # Add route to private network syntax is --add-route-private=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-private=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default ${NETWORK_PRIVATE_ROUTES[@]}
--add-route-public                             # Add route to public network syntax is --add-route-public=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-public=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default ${NETWORK_PUBLIC_ROUTES[@]}

  # Flags to configure nfs client provisionner
--nfs-server-adress                            # The NFS server address, default ${NFS_SERVER_ADDRESS}
--nfs-server-mount                             # The NFS server mount path, default ${NFS_SERVER_PATH}
--nfs-storage-class                            # The storage class name to use, default ${NFS_STORAGE_CLASS}
EOF
}

FOLDER_OPTIONS=

OPTIONS+=(
	"nfs-server-adress:"
	"nfs-server-mount:"
	"nfs-storage-class:"
	"vm-private-network:"
	"vm-public-network:"
	"dont-use-dhcp-routes-private"
	"dont-use-dhcp-routes-public"
	"add-route-private:"
	"add-route-public:"
	"net-address:"
	"net-gateway:"
	"net-dns:"
	"net-domain:"
	"no-dhcp-autoscaled-node"
	"public-address:"
	"metallb-ip-range:"
	"use-keepalived"
)

PARAMS=$(echo ${OPTIONS[*]} | tr ' ' ',')
TEMP=$(getopt -o hvxrdk:u:p: --long "${PARAMS}"  -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true; do
	case "$1" in
	-h|--help)
		usage
		exit 0
		;;
	--distribution)
		DISTRO=$2
		SEED_IMAGE="${DISTRO}-server-cloudimg-seed"
		ROOT_IMG_NAME=${DISTRO}-kubernetes
		shift 2
		;;
	--upgrade)
		UPGRADE_CLUSTER=YES
		shift
		;;
	-v|--verbose)
		VERBOSE=YES
		shift 1
		;;
	-x|--trace)
		TRACE_ARGS=--trace
		set -x
		shift 1
		;;
	-r|--resume)
		RESUME=YES
		shift 1
		;;
	-d|--delete)
		DELETE_CLUSTER=YES
		shift 1
		;;
	--configuration-location)
		CONFIGURATION_LOCATION=$2
		mkdir -p ${CONFIGURATION_LOCATION}
		if [ ! -d ${CONFIGURATION_LOCATION} ]; then
			echo_red "kubernetes output : ${CONFIGURATION_LOCATION} not found"
			exit 1
		fi
		shift 2
		;;
	--ssl-location)
		SSL_LOCATION=$2
		if [ ! -d ${SSL_LOCATION} ]; then
			echo_red "etc dir: ${SSL_LOCATION} not found"
			exit 1
		fi
		shift 2
		;;
	--cert-email)
		CERT_EMAIL=$2
		shift 2
		;;
	--use-zerossl)
		USE_ZEROSSL=YES
		shift 1
		;;
	--use-self-signed-ca)
		CERT_SELFSIGNED=YES
		shift 1
		;;
	--use-cloud-init)
		USE_CLOUDINIT_TO_CONFIGURE=true
		shift 1
		;;
	--zerossl-eab-kid)
		CERT_ZEROSSL_EAB_KID=$2
		shift 2
		;;
	--zerossl-eab-hmac-secret)
		CERT_ZEROSSL_EAB_HMAC_SECRET=$2
		shift 2
		;;
	--godaddy-key)
		CERT_GODADDY_API_KEY=$2
		shift 2
		;;
	--godaddy-secret)
		CERT_GODADDY_API_SECRET=$2
		shift 2
		;;
	--route53-zone-id)
		AWS_ROUTE53_PUBLIC_ZONE_ID=$2
		shift 2
		;;
	--route53-access-key)
		AWS_ROUTE53_ACCESSKEY=$2
		shift 2
		;;
	--route53-secret-key)
		AWS_ROUTE53_SECRETKEY=$2
		shift 2
		;;
	--dashboard-hostname)
		DASHBOARD_HOSTNAME=$2
		shift 2
		;;
	--public-domain)
		PUBLIC_DOMAIN_NAME=$2
		shift 2
		;;
	--defs)
		PLATEFORMDEFS=$2
		if [ -f ${PLATEFORMDEFS} ]; then
			source ${PLATEFORMDEFS}
		else
			echo_red "${PLATEFORM} definitions: ${PLATEFORMDEFS} not found"
			exit 1
		fi
		shift 2
		;;
	--create-image-only)
		CREATE_IMAGE_ONLY=YES
		shift 1
		;;
	--max-pods)
		MAX_PODS=$2
		shift 2
		;;
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
	--ha-cluster)
		HA_CLUSTER=true
		shift 1
		;;
	--create-external-etcd)
		EXTERNAL_ETCD=true
		shift 1
		;;
	--node-group)
		NODEGROUP_NAME="$2"
		MASTERKUBE="${NODEGROUP_NAME}-masterkube"
		shift 2
		;;
	--container-runtime)
		case "$2" in
			"docker"|"cri-o"|"containerd")
				CONTAINER_ENGINE="$2"
				;;
			*)
				echo_red_bold "Unsupported container runtime: $2"
				exit 1
				;;
		esac
		shift 2;;
	--target-image)
		ROOT_IMG_NAME="$2"
		shift 2
		;;
	--seed-image)
		SEED_IMAGE="$2"
		shift 2
		;;
	--nginx-machine)
		NGINX_MACHINE="$2"
		shift 2
		;;
	--control-plane-machine)
		CONTROL_PLANE_MACHINE="$2"
		shift 2
		;;
	--worker-node-machine)
		WORKER_NODE_MACHINE="$2"
		shift 2
		;;
	--autoscale-machine)
		AUTOSCALE_MACHINE="$2"
		shift 2
		;;
	--ssh-private-key)
		SSH_PRIVATE_KEY=$2
		shift 2
		;;
	--cni-plugin)
		CNI_PLUGIN="$2"
		shift 2
		;;
	--cni-version)
		CNI_VERSION="$2"
		shift 2
		;;
	--transport)
		TRANSPORT="$2"
		shift 2
		;;
	-k|--kubernetes-version)
		KUBERNETES_VERSION="$2"
		shift 2
		;;
	-u|--kubernetes-user)
		KUBERNETES_USER="$2"
		shift 2
		;;
	-p|--kubernetes-password)
		KUBERNETES_PASSWORD="$2"
		shift 2
		;;
	--worker-nodes)
		WORKERNODES=$2
		shift 2
		;;
	# Same argument as cluster-autoscaler
	--cloudprovider)
		GRPC_PROVIDER="$2"
		shift 2
		;;
	--max-nodes-total)
		MAXTOTALNODES="$2"
		shift 2
		;;
	--cores-total)
		CORESTOTAL="$2"
		shift 2
		;;
	--memory-total)
		MEMORYTOTAL="$2"
		shift 2
		;;
	--max-autoprovisioned-node-group-count)
		MAXAUTOPROVISIONNEDNODEGROUPCOUNT="$2"
		shift 2
		;;
	--scale-down-enabled)
		SCALEDOWNENABLED="$2"
		shift 2
		;;
	--scale-down-delay-after-add)
		SCALEDOWNDELAYAFTERADD="$2"
		shift 2
		;;
	--scale-down-delay-after-delete)
		SCALEDOWNDELAYAFTERDELETE="$2"
		shift 2
		;;
	--scale-down-delay-after-failure)
		SCALEDOWNDELAYAFTERFAILURE="$2"
		shift 2
		;;
	--scale-down-utilization-threshold)
		SCALEDOWNUTILIZATIONTHRESHOLD="$2"
		shift 2
		;;
	--scale-down-gpu-utilization-threshold)
		SCALEDOWNGPUUTILIZATIONTHRESHOLD="$2"
		shift 2
		;;
	--scale-down-unneeded-time)
		SCALEDOWNUNEEDEDTIME="$2"
		shift 2
		;;
	--scale-down-unready-time)
		SCALEDOWNUNREADYTIME="$2"
		shift 2
		;;
	--max-node-provision-time)
		MAXNODEPROVISIONTIME="$2"
		shift 2
		;;
	--unremovable-node-recheck-timeout)
		UNREMOVABLENODERECHECKTIMEOUT="$2"
		shift 2
		;;
### Plateform specific
	--nfs-server-adress)
		NFS_SERVER_ADDRESS="$2"
		shift 2
		;;
	--nfs-server-mount)
		NFS_SERVER_PATH="$2"
		shift 2
		;;
	--nfs-storage-class)
		NFS_STORAGE_CLASS="$2"
		shift 2
		;;
	--vm-private-network)
		VC_NETWORK_PRIVATE="$2"
		shift 2
		;;
	--vm-public-network)
		VC_NETWORK_PUBLIC="$2"
		shift 2
		;;
	--dont-use-dhcp-routes-private)
		USE_DHCP_ROUTES_PRIVATE=false
		shift 1
		;;
	--dont-use-dhcp-routes-public)
		USE_DHCP_ROUTES_PUBLIC=false
		shift 2
		;;
	--add-route-private)
		NETWORK_PRIVATE_ROUTES+=($2)
		shift 2
		;;
	--add-route-public)
		NETWORK_PUBLIC_ROUTES+=($2)
		shift 2
		;;
	--net-address)
		NET_IP="$2"
		shift 2
		;;
	--net-gateway)
		NET_GATEWAY="$2"
		shift 2
		;;
	--net-dns)
		NET_DNS="$2"
		shift 2
		;;
	--net-domain)
		NET_DOMAIN="$2"
		shift 2
		;;
	--no-dhcp-autoscaled-node)
		SCALEDNODES_DHCP=false
		shift 1
		;;
	--public-address)
		PUBLIC_IP="$2"
		shift 2
		;;
	--metallb-ip-range)
		METALLB_IP_RANGE="$2"
		shift 2
		;;
	--use-keepalived)
		USE_KEEPALIVED=YES
		shift 1
		;;
	--)
		shift
		break
		;;
	*)
		echo_red "$1 - Internal error!"
		exit 1
		;;
	esac
done

SSH_OPTIONS="${SSH_OPTIONS} -i ${SSH_PRIVATE_KEY}"
SCP_OPTIONS="${SCP_OPTIONS} -i ${SSH_PRIVATE_KEY}"

if [ "${VERBOSE}" == "YES" ]; then
	SILENT=
else
	SSH_OPTIONS="${SSH_OPTIONS} -q"
	SCP_OPTIONS="${SCP_OPTIONS} -q"
fi

# Check if ssh private key exists
if [ ! -f ${SSH_PRIVATE_KEY} ]; then
	echo_red "The private ssh key: ${SSH_PRIVATE_KEY} is not found"
	exit -1
fi

# Check if ssh public key exists
if [ ! -f ${SSH_PUBLIC_KEY} ]; then
	echo_red "The private ssh key: ${SSH_PUBLIC_KEY} is not found"
	exit -1
fi

if [ "${UPGRADE_CLUSTER}" == "YES" ] && [ "${DELETE_CLUSTER}" = "YES" ]; then
	echo_red_bold "Can't upgrade deleted cluster, exit"
	exit
fi

if [ "${GRPC_PROVIDER}" != "grpc" ] && [ "${GRPC_PROVIDER}" != "externalgrpc" ]; then
	echo_red_bold "Unsupported cloud provider: ${GRPC_PROVIDER}, only grpc|externalgrpc, exit"
	exit
fi

if [ ${GRPC_PROVIDER} = "grpc" ]; then
	CLOUD_PROVIDER_CONFIG=grpc-config.json
else
	CLOUD_PROVIDER_CONFIG=grpc-config.yaml
fi

if [ "${USE_ZEROSSL}" = "YES" ]; then
	if [ -z "${CERT_ZEROSSL_EAB_KID}" ] || [ -z "${CERT_ZEROSSL_EAB_HMAC_SECRET}" ]; then
		echo_red_bold "CERT_ZEROSSL_EAB_KID or CERT_ZEROSSL_EAB_HMAC_SECRET is empty, exit"
		exit 1
	fi
fi

if [ "${KUBERNETES_DISTRO}" == "microk8s" ]; then
	APISERVER_ADVERTISE_PORT=16443
	# microk8s can't join thru tcp load balancer
	if [ "${HA_CLUSTER}" = "true" ]; then
		USE_KEEPALIVED=YES
	fi
fi

if [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	LOAD_BALANCER_PORT="80,443,${APISERVER_ADVERTISE_PORT},9345"
	EXTERNAL_ETCD=false
elif [ "${KUBERNETES_DISTRO}" == "microk8s" ]; then
	LOAD_BALANCER_PORT="80,443,${APISERVER_ADVERTISE_PORT},25000"
else
	LOAD_BALANCER_PORT="80,443,${APISERVER_ADVERTISE_PORT}"
fi

if [ "${HA_CLUSTER}" = "true" ]; then
	CONTROLNODES=3
else
	CONTROLNODES=1
	EXTERNAL_ETCD=false

	if [ "${USE_NLB}" = "YES" ]; then
		echo_red_bold "NLB usage is not available for single plane cluster"
		exit 1
	fi
fi

if [ "${KUBERNETES_DISTRO}" == "k3s" ] || [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	WANTED_KUBERNETES_VERSION=${KUBERNETES_VERSION}
	IFS=. read K8S_VERSION K8S_MAJOR K8S_MINOR <<< "${KUBERNETES_VERSION}"

	if [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
		RANCHER_CHANNEL=$(curl -s https://update.rke2.io/v1-release/channels)
	else
		RANCHER_CHANNEL=$(curl -s https://update.k3s.io/v1-release/channels)
	fi

	KUBERNETES_VERSION=$(echo -n "${RANCHER_CHANNEL}" | jq -r --arg KUBERNETES_VERSION "${K8S_VERSION}.${K8S_MAJOR}" '.data[]|select(.id == $KUBERNETES_VERSION)|.latest//""')

	if [ -z "${KUBERNETES_VERSION}" ]; then
		KUBERNETES_VERSION=$(echo -n "${RANCHER_CHANNEL}" | jq -r '.data[]|select(.id == "latest")|.latest//""')
		echo_red_bold "${KUBERNETES_DISTRO} ${WANTED_KUBERNETES_VERSION} not available, use latest ${KUBERNETES_VERSION}"
	else
		echo_blue_bold "${KUBERNETES_DISTRO} ${WANTED_KUBERNETES_VERSION} found, use ${KUBERNETES_DISTRO} ${KUBERNETES_VERSION}"
	fi
elif [ "${KUBERNETES_DISTRO}" == "microk8s" ]; then
	WANTED_KUBERNETES_VERSION=${KUBERNETES_VERSION}
	IFS=. read VERSION MAJOR MINOR <<< "${KUBERNETES_VERSION}"
	MICROK8S_CHANNEL="${VERSION:1}.${MAJOR}/stable"

	echo_blue_bold "${KUBERNETES_DISTRO} ${WANTED_KUBERNETES_VERSION} found, use ${KUBERNETES_DISTRO} ${MICROK8S_CHANNEL}"
fi

SSH_KEY_FNAME="$(basename ${SSH_PRIVATE_KEY})"
SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"
SSH_KEY=$(cat "${SSH_PUBLIC_KEY}")

TARGET_CONFIG_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/config
TARGET_DEPLOY_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/deployment
TARGET_CLUSTER_LOCATION=${CONFIGURATION_LOCATION}/cluster/${NODEGROUP_NAME}

if [ "${EXTERNAL_ETCD}" = "true" ]; then
	EXTERNAL_ETCD_ARGS="--use-external-etcd"
	ETCD_DST_DIR="/etc/etcd/ssl"
else
	EXTERNAL_ETCD_ARGS="--no-use-external-etcd"
	ETCD_DST_DIR="/etc/kubernetes/pki/etcd"
fi

# Check variables coherence
if [ "${HA_CLUSTER}" = "true" ]; then
	CONTROLNODES=3
	if [ ${USE_KEEPALIVED} = "YES" ]; then
		FIRSTNODE=1
	fi
else
	CONTROLNODES=1
	USE_KEEPALIVED=NO
	EXTERNAL_ETCD=false
fi

# Check if passord is defined
if [ -z ${KUBERNETES_PASSWORD} ]; then
	if [ -f ~/.kubernetes_pwd ]; then
		KUBERNETES_PASSWORD=$(cat ~/.kubernetes_pwd)
	else
		KUBERNETES_PASSWORD=$(uuidgen)
		echo -n "${KUBERNETES_PASSWORD}" > ~/.kubernetes_pwd
	fi
fi

# GRPC network endpoint
if [ "${LAUNCH_CA}" == "NO" ] || [ "${LAUNCH_CA}" == "DEBUG" ]; then
	SSH_PRIVATE_KEY_LOCAL="${SSH_PRIVATE_KEY}"

	if [ "${TRANSPORT}" == "unix" ]; then
		LISTEN="unix:/var/run/cluster-autoscaler/autoscaler.sock"
		CONNECTTO="unix:/var/run/cluster-autoscaler/autoscaler.sock"
	elif [ "${TRANSPORT}" == "tcp" ]; then
		LISTEN="tcp://${LOCAL_IPADDR}:5200"
		CONNECTTO="${LOCAL_IPADDR}:5200"
	else
		echo_red "Unknown transport: ${TRANSPORT}, should be unix or tcp"
		exit -1
	fi
else
	SSH_PRIVATE_KEY_LOCAL="/etc/ssh/id_rsa"
	TRANSPORT=unix
	LISTEN="unix:/var/run/cluster-autoscaler/autoscaler.sock"
	CONNECTTO="unix:/var/run/cluster-autoscaler/autoscaler.sock"
fi

echo_blue_bold "Transport set to:${TRANSPORT}, listen endpoint at ${LISTEN}"

VC_NETWORK_PRIVATE_TYPE=$(get_net_type ${VC_NETWORK_PRIVATE})

if [ -z "${VC_NETWORK_PRIVATE_TYPE}" ]; then
	echo_red_bold "Unable to find vnet type for vnet: ${VC_NETWORK_PRIVATE}"
	exit 1
fi

if [ -n "${VC_NETWORK_PUBLIC}" ]; then
	VC_NETWORK_PUBLIC_TYPE=$(get_net_type ${VC_NETWORK_PUBLIC})
	
	if [ -z "${VC_NETWORK_PUBLIC_TYPE}" ]; then
		echo_red_bold "Unable to find vnet type for vnet: ${VC_NETWORK_PUBLIC}"
		exit 1
	fi
fi

if [ "${KUBERNETES_DISTRO}" == "kubeadm" ]; then
	TARGET_IMAGE="${ROOT_IMG_NAME}-${CNI_PLUGIN}-${KUBERNETES_VERSION}-${CONTAINER_ENGINE}-${SEED_ARCH}"
else
	TARGET_IMAGE="${ROOT_IMG_NAME}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}"
fi

if [ ${PLATEFORM} == "multipass" ]; then
	TARGET_IMAGE="${PWD}/images/${TARGET_IMAGE}.img"
fi

# Delete previous existing version
if [ "${RESUME}" = "NO" ] && [ "${UPGRADE_CLUSTER}" == "NO" ]; then
	delete-masterkube.sh --plateform=${PLATEFORM} --configuration-location=${CONFIGURATION_LOCATION} --defs=${PLATEFORMDEFS} --node-group=${NODEGROUP_NAME}
	if [ "${DELETE_CLUSTER}" = "YES" ]; then
		exit
	fi
# Check if we can resume the creation process
elif [ ! -f ${TARGET_CONFIG_LOCATION}/buildenv ] && [ "${RESUME}" = "YES" ]; then
	echo_red "Unable to resume, building env is not found"
	exit -1
fi

mkdir -p ${TARGET_CONFIG_LOCATION}
mkdir -p ${TARGET_DEPLOY_LOCATION}
mkdir -p ${TARGET_CLUSTER_LOCATION}

# If CERT doesn't exist, create one autosigned
if [ ! -f ${SSL_LOCATION}/privkey.pem ]; then
	if [ -z "${PUBLIC_DOMAIN_NAME}" ]; then
		echo_red_bold "Public domaine is not defined, unable to create auto signed cert, exit"
		exit 1
	fi

	echo_blue_bold "Create autosigned certificat for domain: ${PUBLIC_DOMAIN_NAME}"
	${CURDIR}/create-cert.sh --domain ${PUBLIC_DOMAIN_NAME} --ssl-location ${SSL_LOCATION} --cert-email ${CERT_EMAIL}
fi

if [ ! -f ${SSL_LOCATION}/cert.pem ]; then
	echo_red "${SSL_LOCATION}/cert.pem not found, exit"
	exit 1
fi

if [ ! -f ${SSL_LOCATION}/fullchain.pem ]; then
	echo_red "${SSL_LOCATION}/fullchain.pem not found, exit"
	exit 1
fi

# If the VM template doesn't exists, build it from scrash
TARGET_IMAGE_UUID=$(get_vmuuid ${TARGET_IMAGE})

if [ -z "${TARGET_IMAGE_UUID}" ] || [ "${TARGET_IMAGE_UUID}" == "ERROR" ]; then
	echo_title "Create ${PLATEFORM} preconfigured image ${TARGET_IMAGE}"

# Never add second network 
# if $(jq --arg SECOND_NETWORK_NAME "${SECOND_NETWORK_NAME}" '.network.interfaces | select(.network = $SECOND_NETWORK_NAME)|.exists' provider.json) == false

	if [ ${PLATEFORM} == "multipass" ]; then
		PRIMARY_NETWORK="${VC_NETWORK_PUBLIC}"
		SECONDARY_NETWORK="${VC_NETWORK_PRIVATE}"
	else
		PRIMARY_NETWORK="${VC_NETWORK_PRIVATE}"
		SECONDARY_NETWORK="${VC_NETWORK_PUBLIC}"
	fi

	./bin/create-image.sh \
		--arch="${SEED_ARCH}" \
		--cni-version="${CNI_VERSION}" \
		--container-runtime=${CONTAINER_ENGINE} \
		--custom-image="${TARGET_IMAGE}" \
		--distribution="${DISTRO}" \
		--k8s-distribution=${KUBERNETES_DISTRO} \
		--kubernetes-version="${KUBERNETES_VERSION}" \
		--password="${KUBERNETES_PASSWORD}" \
		--plateform=${PLATEFORM} \
		--seed="${SEED_IMAGE}-${SEED_ARCH}" \
		--ssh-key="${SSH_KEY}" \
		--ssh-priv-key="${SSH_PRIVATE_KEY}" \
		--user="${KUBERNETES_USER}" \
		--primary-network="${PRIMARY_NETWORK}" \
#		--second-network="${SECONDARY_NETWORK}"

	TARGET_IMAGE_UUID=$(get_vmuuid ${TARGET_IMAGE})
fi

if [ "${CREATE_IMAGE_ONLY}" = "YES" ]; then
	echo_blue_bold "Create image only, done..."
	exit 0
fi

# Extract the domain name from CERT
DOMAIN_NAME=$(openssl x509 -noout -subject -in ${SSL_LOCATION}/cert.pem -nameopt sep_multiline | grep 'CN=' | awk -F= '{print $2}' | sed -e 's/^[\s\t]*//')

if [ "${UPGRADE_CLUSTER}" == "YES" ]; then
	echo_title "Upgrade ${MASTERKUBE} instance with ${TARGET_IMAGE}"
	./bin/upgrade-cluster.sh
	exit
elif [ "${RESUME}" = "NO" ]; then
	echo_title "Launch custom ${MASTERKUBE} instance with ${TARGET_IMAGE}"
	update_build_env
else
	echo_title "Resume custom ${MASTERKUBE} instance with ${TARGET_IMAGE}"
	source ${TARGET_CONFIG_LOCATION}/buildenv
fi

echo "${KUBERNETES_PASSWORD}" >${TARGET_CONFIG_LOCATION}/kubernetes-password.txt

case "${KUBERNETES_DISTRO}" in
	k3s|rke2)
		IMAGE_CREDENTIALS_CONFIG=/var/lib/rancher/credentialprovider/config.yaml
		IMAGE_CREDENTIALS_BIN=/var/lib/rancher/credentialprovider/bin
		;;
	kubeadm)
		IMAGE_CREDENTIALS_CONFIG=/etc/kubernetes/credential.yaml
		IMAGE_CREDENTIALS_BIN=/usr/local/bin
		;;
esac

# Cloud init vendor-data
cat >${TARGET_CONFIG_LOCATION}/vendordata.yaml <<EOF
#cloud-config
package_update: ${UPDATE_PACKAGE}
package_upgrade: ${UPDATE_PACKAGE}
timezone: ${TZ}
ssh_authorized_keys:
  - ${SSH_KEY}
users:
  - default
system_info:
  default_user:
    name: ${KUBERNETES_USER}
EOF

if [ -n "${AWS_ACCESSKEY}" ] && [ -n "${AWS_SECRETKEY}" ]; then
	cat > ${TARGET_CONFIG_LOCATION}/credential.yaml <<EOF
apiVersion: kubelet.config.k8s.io/v1
kind: CredentialProviderConfig
providers:
  - name: ecr-credential-provider
    matchImages:
      - "*.dkr.ecr.*.amazonaws.com"
      - "*.dkr.ecr.*.amazonaws.cn"
      - "*.dkr.ecr-fips.*.amazonaws.com"
      - "*.dkr.ecr.us-iso-east-1.c2s.ic.gov"
      - "*.dkr.ecr.us-isob-east-1.sc2s.sgov.gov"
    defaultCacheDuration: "12h"
    apiVersion: credentialprovider.kubelet.k8s.io/v1
    args:
      - get-credentials
    env:
      - name: AWS_ACCESS_KEY_ID 
        value: ${AWS_ACCESSKEY}
      - name: AWS_SECRET_ACCESS_KEY
        value: ${AWS_SECRETKEY}
EOF

	cat >>${TARGET_CONFIG_LOCATION}/vendordata.yaml <<EOF
write_files:
- encoding: b64
  content: $(cat ${TARGET_CONFIG_LOCATION}/credential.yaml | base64 -w 0)
  owner: root:root
  path: ${IMAGE_CREDENTIALS_CONFIG}
  permissions: '0644'
EOF
fi

gzip -c9 <${TARGET_CONFIG_LOCATION}/vendordata.yaml | base64 -w 0 | tee > ${TARGET_CONFIG_LOCATION}/vendordata.base64

IPADDRS=()
NODE_IP=${NET_IP}
VC_NETWORK_PUBLIC_NIC=eth0 #Multipass setup

if [ -z "${VC_NETWORK_PUBLIC}" ] || [ "${PUBLIC_IP}" == "NONE" ]; then
	PUBLIC_IP=NONE
	PUBLIC_NODE_IP=NONE
	VC_NETWORK_PUBLIC_ENABLED=false
elif [ "${PUBLIC_IP}" == "DHCP" ]; then
	PUBLIC_NODE_IP=${PUBLIC_IP}
else
	IFS=/ read PUBLIC_NODE_IP PUBLIC_MASK_CIDR <<< "${PUBLIC_IP}"
	PUBLIC_NETMASK=$(cidr_to_netmask ${PUBLIC_MASK_CIDR})
	VC_NETWORK_PUBLIC_NIC="eth0:1"
fi

# No external elb, use keep alived
if [[ ${FIRSTNODE} > 0 ]]; then
	delete_host "${MASTERKUBE}"
	add_host ${NODE_IP} ${MASTERKUBE} ${MASTERKUBE}.${DOMAIN_NAME}

	IPADDRS+=(${NODE_IP})
	NODE_IP=$(nextip ${NODE_IP})
	PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
fi

if [ ${HA_CLUSTER} = "true" ]; then
	TOTALNODES=$((WORKERNODES + ${CONTROLNODES}))
else
	CONTROLNODES=0
	TOTALNODES=${WORKERNODES}
fi

if [ ${#NETWORK_PUBLIC_ROUTES[@]} -gt 0 ]; then
	PUBLIC_ROUTES_DEFS=$(build_routes ${NETWORK_PUBLIC_ROUTES[@]})
else
	PUBLIC_ROUTES_DEFS='[]'
fi

if [ ${#NETWORK_PRIVATE_ROUTES[@]} -gt 0 ]; then
	PRIVATE_ROUTES_DEFS=$(build_routes ${NETWORK_PRIVATE_ROUTES[@]})
else
	PRIVATE_ROUTES_DEFS='[]'
fi

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vm_name() {
	local NODEINDEX=$1

	if [ ${NODEINDEX} = 0 ]; then
		MASTERKUBE_NODE="${MASTERKUBE}"
	elif [[ ${NODEINDEX} > ${CONTROLNODES} ]]; then
		NODEINDEX=$((INDEX - ${CONTROLNODES}))
		MASTERKUBE_NODE="${NODEGROUP_NAME}-worker-0${NODEINDEX}"
	else
		MASTERKUBE_NODE="${NODEGROUP_NAME}-master-0${NODEINDEX}"
	fi

	echo -n ${MASTERKUBE_NODE}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_machine_type() {
	local NODEINDEX=$1
	local MACHINE_TYPE=

	if [ ${NODEINDEX} = 0 ] && [ ${HA_CLUSTER} = "true" ]; then
		# node 0 is ELB on HA mode
		MACHINE_TYPE=${NGINX_MACHINE}
	elif [ ${NODEINDEX} -gt ${CONTROLNODES} ]; then
		MACHINE_TYPE=${WORKER_NODE_MACHINE}
	else
		MACHINE_TYPE=${CONTROL_PLANE_MACHINE}
	fi

	echo -n ${MACHINE_TYPE}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
for INDEX in $(seq ${FIRSTNODE} ${TOTALNODES})
do
	if [ "${PLATEFORM}" == "vsphere" ]; then
		create_vm ${INDEX} ${PUBLIC_NODE_IP} ${NODE_IP} &
	else
		create_vm ${INDEX} ${PUBLIC_NODE_IP} ${NODE_IP}
	fi

	IPADDRS+=(${NODE_IP})

	# Reserve 2 ip for potentiel HA cluster
	if [[ "${HA_CLUSTER}" == "false" ]] && [[ ${INDEX} = 0 ]]; then
		NODE_IP=$(nextip ${NODE_IP})
		NODE_IP=$(nextip ${NODE_IP})
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
	fi

	NODE_IP=$(nextip ${NODE_IP})
	PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
done

if [ ${WORKERNODES} -gt 0 ]; then
	FIRST_WORKER_NODE_IP=${IPADDRS[${#IPADDRS[@]} - ${WORKERNODES}]}
else
	FIRST_WORKER_NODE_IP=$(nextip ${IPADDRS[${#IPADDRS[@]} - 1]})
fi

wait_jobs_finish

if [ "${HA_CLUSTER}" = "true" ]; then
	CONTROLNODE_INDEX=1
	for INDEX in $(seq 1 ${CONTROLNODES})
	do
		MASTERKUBE_NODE="${NODEGROUP_NAME}-master-0${INDEX}"
		IPADDR="${IPADDRS[${INDEX}]}"
		NODE_DNS="${MASTERKUBE_NODE}.${DOMAIN_NAME}:${IPADDR}"

		if [ -z "${CLUSTER_NODES}" ]; then
			CLUSTER_NODES="${NODE_DNS}"
		else
			CLUSTER_NODES="${CLUSTER_NODES},${NODE_DNS}"
		fi

		if [ "${EXTERNAL_ETCD}" = "true" ]; then
			if [ -z "${ETCD_ENDPOINT}" ]; then
				ETCD_ENDPOINT="https://${IPADDR}:2379"
			else
				ETCD_ENDPOINT="${ETCD_ENDPOINT},https://${IPADDR}:2379"
			fi
		fi
	done

	echo "export CLUSTER_NODES=${CLUSTER_NODES}" >> ${TARGET_CONFIG_LOCATION}/buildenv

	if [ "${EXTERNAL_ETCD}" = "true" ]; then
		echo_title "Created etcd cluster: ${CLUSTER_NODES}"

		prepare-etcd.sh --node-group=${NODEGROUP_NAME} --cluster-nodes="${CLUSTER_NODES}" --target-location="${TARGET_CLUSTER_LOCATION}" ${SILENT}

		for INDEX in $(seq 1 ${CONTROLNODES})
		do
			if [ ! -f ${TARGET_CONFIG_LOCATION}/etdc-0${INDEX}-prepared ]; then
				IPADDR="${IPADDRS[${INDEX}]}"

				echo_title "Start etcd node: ${IPADDR}"
                eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/etcd ${KUBERNETES_USER}@${IPADDR}:~/etcd ${SILENT}
				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-etcd.sh \
					--user=${KUBERNETES_USER} \
					--cluster-nodes="${CLUSTER_NODES}" \
					--node-index="${INDEX}" ${SILENT}

				touch ${TARGET_CONFIG_LOCATION}/etdc-0${INDEX}-prepared
			fi
		done
	fi

	if [ "${USE_KEEPALIVED}" = "YES" ]; then
		echo_title "Created keepalived cluster: ${CLUSTER_NODES}"

		for INDEX in $(seq 1 ${CONTROLNODES})
		do
			if [ ! -f ${TARGET_CONFIG_LOCATION}/keepalived-0${INDEX}-prepared ]; then
				IPADDR="${IPADDRS[${INDEX}]}"

				echo_title "Start keepalived node: ${IPADDR}"

				case "${INDEX}" in
					1)
						KEEPALIVED_PEER1=${IPADDRS[2]}
						KEEPALIVED_PEER2=${IPADDRS[3]}
						KEEPALIVED_STATUS=MASTER
						;;
					2)
						KEEPALIVED_PEER1=${IPADDRS[1]}
						KEEPALIVED_PEER2=${IPADDRS[3]}
						KEEPALIVED_STATUS=BACKUP
						;;
					3)
						KEEPALIVED_PEER1=${IPADDRS[1]}
						KEEPALIVED_PEER2=${IPADDRS[2]}
						KEEPALIVED_STATUS=BACKUP
						;;
				esac

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-keepalived.sh \
					--bind-address="${IPADDRS[0]}" \
					--bind-port="${APISERVER_ADVERTISE_PORT}" \
					--keep-alive-password="${KUBERNETES_PASSWORD}" \
					--keep-alive-priority="$((80-INDEX))" \
					--keep-alive-multicast=${IPADDRS[${INDEX}]} \
					--keep-alive-peer1=${KEEPALIVED_PEER1} \
					--keep-alive-peer2=${KEEPALIVED_PEER2} \
					--keep-alive-status=${KEEPALIVED_STATUS} ${SILENT}

				touch ${TARGET_CONFIG_LOCATION}/keepalived-0${INDEX}-prepared
			fi
		done
	fi
else
	CONTROLNODE_INDEX=0
	IPADDR="${IPADDRS[0]}"
	IPRESERVED1=$(nextip ${IPADDR})
	IPRESERVED2=$(nextip ${IPRESERVED1})
	CLUSTER_NODES="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDR},${NODEGROUP_NAME}-master-02.${DOMAIN_NAME}:${IPRESERVED1},${NODEGROUP_NAME}-master-03.${DOMAIN_NAME}:${IPRESERVED2}"

	echo "export CLUSTER_NODES=${CLUSTER_NODES}" >> ${TARGET_CONFIG_LOCATION}/buildenv
fi

CERT_SANS=$(collect_cert_sans "${IPADDRS[0]}" "${CLUSTER_NODES}" "${MASTERKUBE}.${DOMAIN_NAME}")

for INDEX in $(seq ${FIRSTNODE} ${TOTALNODES})
do
	MASTERKUBE_NODE=$(get_vm_name ${INDEX})

	if [ -f ${TARGET_CONFIG_LOCATION}/kubeadm-0${INDEX}-prepared ]; then
		echo_title "Already prepared VM ${MASTERKUBE_NODE}"
	else
		IPADDR="${IPADDRS[${INDEX}]}"
		VMUUID=$(get_vmuuid ${MASTERKUBE_NODE})

		echo_title "Prepare VM ${MASTERKUBE_NODE}, UUID=${VMUUID} with IP:${IPADDR}"

		if [ ${INDEX} = 0 ]; then
			if [ "${HA_CLUSTER}" = "true" ]; then
				echo_blue_bold "Start load balancer ${MASTERKUBE_NODE} instance"

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-load-balancer.sh \
					--listen-port=${LOAD_BALANCER_PORT} \
					--cluster-nodes="${CLUSTER_NODES}" \
					--control-plane-endpoint=${MASTERKUBE}.${DOMAIN_NAME} \
					--listen-ip=${NET_IP} ${SILENT}
			else
				echo_blue_bold "Start kubernetes ${MASTERKUBE_NODE} single instance master node, kubernetes version=${KUBERNETES_VERSION}"

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo create-cluster.sh ${TRACE_ARGS} \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--advertise-port=${APISERVER_ADVERTISE_PORT} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--vm-uuid=${VMUUID} \
					--csi-region=${REGION} \
					--csi-zone=${ZONEID} \
					--max-pods=${MAX_PODS} \
					--allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
					--control-plane-endpoint="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDRS[0]}" \
					--container-runtime=${CONTAINER_ENGINE} \
					--tls-san="${CERT_SANS}" \
					--cluster-nodes="${CLUSTER_NODES}" \
					--node-group=${NODEGROUP_NAME} \
					--node-index=${INDEX} \
					--cni-plugin=${CNI_PLUGIN} \
					--net-if=${NET_IF} \
					--kubernetes-version="${KUBERNETES_VERSION}" ${SILENT}

				eval scp ${SCP_OPTIONS} ${KUBERNETES_USER}@${IPADDR}:/etc/cluster/* ${TARGET_CLUSTER_LOCATION}/ ${SILENT}
			fi
		else
			if [ "${HA_CLUSTER}" = "true" ]; then
				NODEINDEX=$((INDEX-1))
			else
				NODEINDEX=${INDEX}
			fi

			if [ ${NODEINDEX} = 0 ]; then
				echo_blue_bold "Start kubernetes ${MASTERKUBE_NODE} instance master node number ${INDEX}, kubernetes version=${KUBERNETES_VERSION}"

				ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo create-cluster.sh ${TRACE_ARGS} \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--advertise-port=${APISERVER_ADVERTISE_PORT} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--vm-uuid=${VMUUID} \
					--csi-region=${REGION} \
					--csi-zone=${ZONEID} \
					--max-pods=${MAX_PODS} \
					--allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
					--container-runtime=${CONTAINER_ENGINE} \
					--use-external-etcd=${EXTERNAL_ETCD} \
					--node-group=${NODEGROUP_NAME} \
					--node-index=${INDEX} \
					--load-balancer-ip=${IPADDRS[0]} \
					--cluster-nodes="${CLUSTER_NODES}" \
					--control-plane-endpoint="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDRS[1]}" \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--tls-san="${CERT_SANS}" \
					--ha-cluster=true \
					--cni-plugin=${CNI_PLUGIN} \
					--net-if=${NET_IF} \
					--kubernetes-version="${KUBERNETES_VERSION}" ${SILENT}

				eval scp ${SCP_OPTIONS} ${KUBERNETES_USER}@${IPADDR}:/etc/cluster/* ${TARGET_CLUSTER_LOCATION}/ ${SILENT}

				echo_blue_dot_title "Wait for ELB start on IP: ${IPADDRS[0]}"

				while :
				do
					echo_blue_dot
					curl -s -k "https://${IPADDRS[0]}:${APISERVER_ADVERTISE_PORT}" &> /dev/null && break
					sleep 1
				done
				echo

				echo -n ${IPADDRS[0]}:${APISERVER_ADVERTISE_PORT} > ${TARGET_CLUSTER_LOCATION}/manager-ip
			elif [[ ${INDEX} > ${CONTROLNODES} ]] || [ "${HA_CLUSTER}" = "false" ]; then
				echo_blue_bold "Join node ${MASTERKUBE_NODE} instance worker node, kubernetes version=${KUBERNETES_VERSION}"

				eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/* ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh ${TRACE_ARGS} \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--kubernetes-version="${KUBERNETES_VERSION}" \
					--container-runtime=${CONTAINER_ENGINE} \
					--cni-plugin=${CNI_PLUGIN} \
					--csi-region=${REGION} \
					--csi-zone=${ZONEID} \
					--max-pods=${MAX_PODS} \
					--vm-uuid=${VMUUID} \
					--use-external-etcd=${EXTERNAL_ETCD} \
					--node-group=${NODEGROUP_NAME} \
					--node-index=${NODEINDEX} \
					--join-master="${IPADDRS[0]}:${APISERVER_ADVERTISE_PORT}" \
					--control-plane-endpoint="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDRS[0]}" \
					--tls-san="${CERT_SANS}" \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--net-if=${NET_IF} \
					--cluster-nodes="${CLUSTER_NODES}" ${SILENT}
			else
				echo_blue_bold "Join node ${MASTERKUBE_NODE} instance master node, kubernetes version=${KUBERNETES_VERSION}"

				eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/* ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh ${TRACE_ARGS} \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--kubernetes-version="${KUBERNETES_VERSION}" \
					--container-runtime=${CONTAINER_ENGINE} \
					--cni-plugin=${CNI_PLUGIN} \
					--csi-region=${REGION} \
					--csi-zone=${ZONEID} \
					--max-pods=${MAX_PODS} \
					--vm-uuid=${VMUUID} \
					--allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
					--use-external-etcd=${EXTERNAL_ETCD} \
					--node-group=${NODEGROUP_NAME} \
					--node-index=${NODEINDEX} \
					--control-plane-endpoint="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDRS[0]}" \
					--tls-san="${CERT_SANS}" \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--cluster-nodes="${CLUSTER_NODES}" \
					--net-if=${NET_IF} \
					--join-master="${IPADDRS[0]}:${APISERVER_ADVERTISE_PORT}" \
					--control-plane=true ${SILENT}
			fi
		fi

		echo ${MASTERKUBE_NODE} > ${TARGET_CONFIG_LOCATION}/kubeadm-0${INDEX}-prepared
	fi

	echo_separator
done

kubeconfig-merge.sh ${MASTERKUBE} ${TARGET_CLUSTER_LOCATION}/config

echo_blue_bold "create cluster done"

MASTER_IP=$(cat ${TARGET_CLUSTER_LOCATION}/manager-ip)
TOKEN=$(cat ${TARGET_CLUSTER_LOCATION}/token)
CACERT=$(cat ${TARGET_CLUSTER_LOCATION}/ca.cert)

kubectl create secret generic autoscaler-ssh-keys -n kube-system --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-file=id_rsa="${SSH_PRIVATE_KEY}" \
	--from-file=id_rsa.pub="${SSH_PUBLIC_KEY}" | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

echo_title "Write ${PLATEFORM} autoscaler provider config"

if [ ${GRPC_PROVIDER} = "grpc" ]; then
	cat > ${TARGET_CONFIG_LOCATION}/${CLOUD_PROVIDER_CONFIG} <<EOF
	{
		"address": "${CONNECTTO}",
		"secret": "${PLATEFORM}",
		"timeout": 300
	}
EOF
else
	echo "address: ${CONNECTTO}" > ${TARGET_CONFIG_LOCATION}/${CLOUD_PROVIDER_CONFIG}
fi

if [ "${KUBERNETES_DISTRO}" == "microk8s" ]; then
	SERVER_ADDRESS="${MASTER_IP%%:*}:25000"
elif [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	SERVER_ADDRESS="${MASTER_IP%%:*}:9345"
else
	SERVER_ADDRESS="${MASTER_IP}"
fi

cp ${PWD}/templates/setup/${PLATEFORM}/machines.json ${TARGET_CONFIG_LOCATION}/machines.json

if [ -n "${AWS_ACCESSKEY}" ] && [ -n "${AWS_SECRETKEY}" ]; then
	echo $(eval "cat <<EOF
$(<${PWD}/templates/setup/image-credential-provider-config.json)
EOF") | jq . > ${TARGET_CONFIG_LOCATION}/image-credential-provider-config.json

	IMAGE_CREDENTIALS=$(cat "${TARGET_CONFIG_LOCATION}/image-credential-provider-config.json")
else
	IMAGE_CREDENTIALS='{}'
fi

echo $(eval "cat <<EOF
$(<${PWD}/templates/setup/${PLATEFORM}/provider.json)
EOF") | jq . > ${TARGET_CONFIG_LOCATION}/provider.json

echo $(eval "cat <<EOF
$(<${PWD}/templates/setup/${PLATEFORM}/autoscaler.json)
EOF") | jq --argjson IMAGE_CREDENTIALS "${IMAGE_CREDENTIALS}" '. += $IMAGE_CREDENTIALS' > ${TARGET_CONFIG_LOCATION}/autoscaler.json

