#!/bin/bash

# This script create every thing to deploy a simple kubernetes autoscaled cluster with multipass.
# It will generate:
# Custom image with every thing for kubernetes
# Config file to deploy the cluster autoscaler.
# kubectl run busybox --rm -ti --image=busybox -n kube-public /bin/sh

set -eu

export AUTOSCALE_MACHINE="medium"
export AUTOSCALER_DESKTOP_UTILITY_ADDR=
export AUTOSCALER_DESKTOP_UTILITY_CACERT=
export AUTOSCALER_DESKTOP_UTILITY_CERT=
export AUTOSCALER_DESKTOP_UTILITY_KEY=
export AUTOSCALER_DESKTOP_UTILITY_TLS=
export AWS_ACCESSKEY=
export AWS_ROUTE53_ACCESSKEY=
export AWS_ROUTE53_PUBLIC_ZONE_ID=
export AWS_ROUTE53_SECRETKEY=
export AWS_SECRETKEY=
export CERT_GODADDY_API_KEY=${GODADDY_API_KEY}
export CERT_GODADDY_API_SECRET=${GODADDY_API_SECRET}
export CERT_ZEROSSL_EAB_HMAC_SECRET=${ZEROSSL_EAB_HMAC_SECRET}
export CERT_ZEROSSL_EAB_KID=${ZEROSSL_EAB_KID}
export CLOUD_PROVIDER_CONFIG=
export CLOUD_PROVIDER=
export CNI_PLUGIN=flannel
export CNI_VERSION="v1.4.0"
export CONFIGURATION_LOCATION=${PWD}
export CONTAINER_ENGINE=containerd
export CONTROL_PLANE_MACHINE="small"
export CONTROLNODES=1
export CORESTOTAL="0:16"
export DELETE_CREDENTIALS_CONFIG=NO
export DISTRO=jammy
export EXTERNAL_ETCD=false
export FIRSTNODE=0
export GRPC_PROVIDER=externalgrpc
export HA_CLUSTER=false
export KUBECONFIG=${HOME}/.kube/config
export KUBERNETES_DISTRO=kubeadm
export KUBERNETES_PASSWORD=
export KUBERNETES_USER=kubernetes
export KUBERNETES_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
export LAUNCH_CA=YES
export LOAD_BALANCER_PORT=6443
export MASTER_NODE_ALLOW_DEPLOYMENT=NO
export MAX_PODS=110
export MAXAUTOPROVISIONNEDNODEGROUPCOUNT="1"
export MAXNODES=9
export MAXTOTALNODES=${MAXNODES}
export MEMORYTOTAL="0:48"
export METALLB_IP_RANGE=10.0.0.100-10.0.0.127
export MINNODES=0
export NET_DNS=10.0.0.1
export NET_DOMAIN=home
export NET_GATEWAY=10.0.0.1
export NET_IF=eth1
export NET_IP=192.168.1.20
export NET_MASK_CIDR=24
export NET_MASK=255.255.255.0
export NETWORK_PRIVATE_ROUTES=()
export NETWORK_PUBLIC_ROUTES=()
export NFS_SERVER_ADDRESS=
export NFS_SERVER_PATH=
export NFS_STORAGE_CLASS=nfs-client
export NGINX_MACHINE="tiny"
export NODEGROUP_NAME=
export OSDISTRO=$(uname -s)
export PUBLIC_DOMAIN_NAME=
export PUBLIC_IP=DHCP
export REGION=home
export REGISTRY=fred78290
export RESUME=NO
export ROOT_IMG_NAME=${DISTRO}-kubernetes
export SCALEDNODES_DHCP=true
export SCALEDOWNDELAYAFTERADD="1m"
export SCALEDOWNDELAYAFTERDELETE="1m"
export SCALEDOWNDELAYAFTERFAILURE="1m"
export SCALEDOWNENABLED="true"
export SCALEDOWNUNEEDEDTIME="1m"
export SCALEDOWNUNREADYTIME="1m"
export SEED_ARCH=$([[ "$(uname -m)" =~ arm64|aarch64 ]] && echo -n arm64 || echo -n amd64)
export SEED_IMAGE="${DISTRO}-server-cloudimg-seed"
export SEED_USER=ubuntu
export SILENT="&> /dev/null"
export SSH_KEY_FNAME=
export SSH_KEY=
export SSH_PRIVATE_KEY="${HOME}/.ssh/id_rsa"
export SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"
export SSL_LOCATION=${CONFIGURATION_LOCATION}/etc/ssl
export TARGET_CLUSTER_LOCATION=
export TARGET_CONFIG_LOCATION=
export TARGET_DEPLOY_LOCATION=
export TARGET_IMAGE="${ROOT_IMG_NAME}-cni-${CNI_PLUGIN}-${KUBERNETES_VERSION}-${SEED_ARCH}-${CONTAINER_ENGINE}"
export TRANSPORT="tcp"
export UNREMOVABLENODERECHECKTIMEOUT="1m"
export UPGRADE_CLUSTER=NO
export USE_DHCP_ROUTES_PRIVATE=true
export USE_DHCP_ROUTES_PUBLIC=true
export USE_KEEPALIVED=NO
export USE_ZEROSSL=YES
export VC_NETWORK_PRIVATE="bridged100"
export VC_NETWORK_PUBLIC="en0"
export WORKER_NODE_MACHINE="medium"
export WORKERNODES=3
export ZONEID=office

export CERT_EMAIL=
export PUBLIC_DOMAIN_NAME=

# Sample machine definition
MACHINE_DEFS=$(cat ${PWD}/templates/setup/${PLATEFORM}/machines.json)

DELETE_CLUSTER=NO

source ${PWD}/bin/common.sh

function usage() {
cat <<EOF
$0 create a kubernetes simple cluster or HA cluster with 3 control planes
Options are:
--help | -h                                    # Display usage
--verbose | -v                                 # Verbose
--trace | -x                                   # Trace execution
--resume | -r                                  # Allow to resume interrupted creation of cluster kubernetes
--delete                                       # Delete cluster and exit
--distribution                                 # Ubuntu distribution to use ${DISTRO}
--create-image-only                            # Create image only
--upgrade                                      # Upgrade existing cluster to upper version of kubernetes

### Flags to set some location informations

--configuration-location                       # Specify where configuration will be stored, default ${CONFIGURATION_LOCATION}
--ssl-location=<path>                          # Specify where the etc/ssl dir is stored, default ${SSL_LOCATION}
--defs=<path>                                  # Specify the ${PLATEFORM} definitions, default ${PLATEFORMDEFS}

### Design domain

--public-domain                                # Specify the public domain to use, default ${PUBLIC_DOMAIN_NAME}
--dashboard-hostname                           # Specify the hostname for kubernetes dashboard, default ${DASHBOARD_HOSTNAME}

### Cert Manager

--cert-email=<value>                           # Specify the mail for lets encrypt, default ${CERT_EMAIL}
--use-zerossl                                  # Specify cert-manager to use zerossl, default ${USE_ZEROSSL}
--dont-use-zerossl                             # Specify cert-manager to use letsencrypt, default ${USE_ZEROSSL}
--zerossl-eab-kid=<value>                      # Specify zerossl eab kid, default ${CERT_ZEROSSL_EAB_KID}
--zerossl-eab-hmac-secret=<value>              # Specify zerossl eab hmac secret, default ${CERT_ZEROSSL_EAB_HMAC_SECRET}
--godaddy-key                                  # Specify godaddy api key
--godaddy-secret                               # Specify godaddy api secret

### Route53

--route53-zone-id                              # Specify the route53 zone id, default ${AWS_ROUTE53_PUBLIC_ZONE_ID}
--route53-access-key                           # Specify the route53 aws access key, default ${AWS_ROUTE53_ACCESSKEY}
--route53-secret-key                           # Specify the route53 aws secret key, default ${AWS_ROUTE53_SECRETKEY}

### Design the kubernetes cluster

--k8s-distribution=<kubeadm|k3s|rke2>          # Which kubernetes distribution to use: kubeadm, k3s, rke2, default ${KUBERNETES_DISTRO}
--ha-cluster | -c                              # Allow to create an HA cluster, default ${HA_CLUSTER}
--worker-nodes=<value>                         # Specify the number of worker node created in HA cluster, default ${WORKERNODES}
--container-runtime=<docker|containerd|cri-o>  # Specify which OCI runtime to use, default ${CONTAINER_ENGINE}
--max-pods                                     # Specify the max pods per created VM, default ${MAX_PODS}
--autoscale-machine | -d=<value>               # Override machine type used for auto scaling, default ${AUTOSCALE_MACHINE}
--nginx-machine                                # Override machine type used for nginx as ELB, default ${NGINX_MACHINE}
--control-plane-machine                        # Override machine type used for control plane, default ${CONTROL_PLANE_MACHINE}
--worker-node-machine                          # Override machine type used for worker node, default ${WORKER_NODE_MACHINE}
--ssh-private-key | -s=<value>                 # Override ssh key is used, default ${SSH_PRIVATE_KEY}
--transport | -t=<value>                       # Override the transport to be used between autoscaler and kubernetes-cloud-autoscaler, default ${TRANSPORT}
--node-group=<value>                           # Override the node group name, default ${NODEGROUP_NAME}
--cni-plugin=<value>                           # Override CNI plugin, default: ${CNI_PLUGIN}
--cni-version | -n=<value>                     # Override CNI plugin version, default: ${CNI_VERSION}
--kubernetes-version | -k=<value>              # Override the kubernetes version, default ${KUBERNETES_VERSION}

### Flags in ha mode only

--create-external-etcd | -e                    # Allow to create an external HA etcd cluster, default ${EXTERNAL_ETCD}
--use-keepalived | -u                          # Allow to use keepalived as load balancer else NGINX is used

### Flags to set the template vm

--target-image=<value>                         # Override the prefix template VM image used for created VM, default ${ROOT_IMG_NAME}
--seed-image=<value>                           # Override the seed image name used to create template, default ${SEED_IMAGE}
--seed-user=<value>                            # Override the seed user in template, default ${SEED_USER}
--password | -p=<value>                        # Override the password to ssh the cluster VM, default random word

### Flags to configure network in ${PLATEFORM}

--public-address=<value>                       # The public address to expose kubernetes endpoint, default ${PUBLIC_IP}
--no-dhcp-autoscaled-node                      # Autoscaled node don't use DHCP, default ${SCALEDNODES_DHCP}
--vm-private-network=<value>                   # Override the name of the private network in ${PLATEFORM}, default ${VC_NETWORK_PRIVATE}
--vm-public-network=<value>                    # Override the name of the public network in ${PLATEFORM}, default ${VC_NETWORK_PUBLIC}
--net-address=<value>                          # Override the IP of the kubernetes control plane node, default ${NET_IP}
--net-gateway=<value>                          # Override the IP gateway, default ${NET_GATEWAY}
--net-dns=<value>                              # Override the IP DNS, default ${NET_DNS}
--net-domain=<value>                           # Override the domain name, default ${NET_DOMAIN}
--metallb-ip-range                             # Override the metalb ip range, default ${METALLB_IP_RANGE}
--dont-use-dhcp-routes-private                 # Tell if we don't use DHCP routes in private network, default ${USE_DHCP_ROUTES_PRIVATE}
--dont-use-dhcp-routes-public                  # Tell if we don't use DHCP routes in public network, default ${USE_DHCP_ROUTES_PUBLIC}
--add-route-private                            # Add route to private network syntax is --add-route-private=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-private=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default ${NETWORK_PRIVATE_ROUTES[@]}
--add-route-public                             # Add route to public network syntax is --add-route-public=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-public=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default ${NETWORK_PUBLIC_ROUTES[@]}

### Flags to configure nfs client provisionner

--nfs-server-adress                            # The NFS server address, default ${NFS_SERVER_ADDRESS}
--nfs-server-mount                             # The NFS server mount path, default ${NFS_SERVER_PATH}
--nfs-storage-class                            # The storage class name to use, default ${NFS_STORAGE_CLASS}

### Flags for autoscaler
--cloudprovider=<value>                        # autoscaler flag <grpc|externalgrpc>, default: ${GRPC_PROVIDER}
--max-nodes-total=<value>                      # autoscaler flag, default: ${MAXTOTALNODES}
--cores-total=<value>                          # autoscaler flag, default: ${CORESTOTAL}
--memory-total=<value>                         # autoscaler flag, default: ${MEMORYTOTAL}
--max-autoprovisioned-node-group-count=<value> # autoscaler flag, default: ${MAXAUTOPROVISIONNEDNODEGROUPCOUNT}
--scale-down-enabled=<value>                   # autoscaler flag, default: ${SCALEDOWNENABLED}
--scale-down-delay-after-add=<value>           # autoscaler flag, default: ${SCALEDOWNDELAYAFTERADD}
--scale-down-delay-after-delete=<value>        # autoscaler flag, default: ${SCALEDOWNDELAYAFTERDELETE}
--scale-down-delay-after-failure=<value>       # autoscaler flag, default: ${SCALEDOWNDELAYAFTERFAILURE}
--scale-down-unneeded-time=<value>             # autoscaler flag, default: ${SCALEDOWNUNEEDEDTIME}
--scale-down-unready-time=<value>              # autoscaler flag, default: ${SCALEDOWNUNREADYTIME}
--unremovable-node-recheck-timeout=<value>     # autoscaler flag, default: ${UNREMOVABLENODERECHECKTIMEOUT}
EOF
}

TEMP=$(getopt -o xvheucrk:n:p:s:t: --long upgrade,autoscale-machine:,distribution:,k8s-distribution:,cloudprovider:,route53-zone-id:,route53-access-key:,route53-secret-key:,use-zerossl,dont-use-zerossl,zerossl-eab-kid:,zerossl-eab-hmac-secret:,godaddy-key:,godaddy-secret:,nfs-server-adress:,nfs-server-mount:,nfs-storage-class:,add-route-private:,add-route-public:,dont-use-dhcp-routes-private,dont-use-dhcp-routes-public,nginx-machine:,control-plane-machine:,worker-node-machine:,delete,configuration-location:,ssl-location:,cert-email:,public-domain:,dashboard-hostname:,create-image-only,no-dhcp-autoscaled-node,metallb-ip-range:,trace,container-runtime:,verbose,help,create-external-etcd,use-keepalived,defs:,worker-nodes:,ha-cluster,public-address:,resume,node-group:,target-image:,seed-image:,seed-user:,vm-public-network:,vm-private-network:,net-address:,net-gateway:,net-dns:,net-domain:,transport:,ssh-private-key:,cni-version:,password:,kubernetes-version:,max-nodes-total:,cores-total:,memory-total:,max-autoprovisioned-node-group-count:,scale-down-enabled:,scale-down-delay-after-add:,scale-down-delay-after-delete:,scale-down-delay-after-failure:,scale-down-unneeded-time:,scale-down-unready-time:,unremovable-node-recheck-timeout: -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true; do
	case "$1" in
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
	-u|--use-keepalived)
		USE_KEEPALIVED=YES
		shift 1
		;;
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
		set -x
		shift 1
		;;
	-r|--resume)
		RESUME=YES
		shift 1
		;;
	--delete)
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
	--dont-use-zerossl)
		USE_ZEROSSL=NO
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
			kubeadm|k3s|rke2)
				KUBERNETES_DISTRO=$2
				;;
			*)
				echo "Unsupported kubernetes distribution: $2"
				exit 1
				;;
		esac
		shift 2
		;;
	-c|--ha-cluster)
		HA_CLUSTER=true
		CONTROLNODES=3
		shift 1
		;;
	-e|--create-external-etcd)
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

	--seed-user)
		SEED_USER="$2"
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
	-s | --ssh-private-key)
		SSH_PRIVATE_KEY=$2
		shift 2
		;;
	--cni-plugin)
		CNI_PLUGIN="$2"
		shift 2
		;;
	-n | --cni-version)
		CNI_VERSION="$2"
		shift 2
		;;
	-t | --transport)
		TRANSPORT="$2"
		shift 2
		;;
	-k | --kubernetes-version)
		KUBERNETES_VERSION="$2"
		shift 2
		;;
	-p | --password)
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
	--scale-down-unneeded-time)
		SCALEDOWNUNEEDEDTIME="$2"
		shift 2
		;;
	--scale-down-unready-time)
		SCALEDOWNUNREADYTIME="$2"
		shift 2
		;;
	--unremovable-node-recheck-timeout)
		UNREMOVABLENODERECHECKTIMEOUT="$2"
		shift 2
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

export VC_NETWORK_PRIVATE_TYPE=$(get_net_type ${VC_NETWORK_PRIVATE})
export VC_NETWORK_PUBLIC_TYPE=$(get_net_type ${VC_NETWORK_PUBLIC})

if [ -z "${VC_NETWORK_PUBLIC_TYPE}" ]; then
	echo_red_bold "Unable to find vnet type for vnet: ${VC_NETWORK_PUBLIC}"
	exit 1
fi

if [ -z "${VC_NETWORK_PRIVATE_TYPE}" ]; then
	echo_red_bold "Unable to find vnet type for vnet: ${VC_NETWORK_PRIVATE}"
	exit 1
fi

if [ "${UPGRADE_CLUSTER}" == "YES" ] && [ "${DELETE_CLUSTER}" = "YES" ]; then
	echo_red_bold "Can't upgrade deleted cluster, exit"
	exit
fi

if [ "${GRPC_PROVIDER}" != "grpc" ] && [ "${GRPC_PROVIDER}" != "externalgrpc" ]; then
	echo_red_bold "Unsupported cloud provider: ${GRPC_PROVIDER}, only grpc|externalgrpc, exit"
	exit
fi

if [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT},9345"
	EXTERNAL_ETCD=false
fi

if [ "${HA_CLUSTER}" = "true" ]; then
	CONTROLNODES=3
else
	CONTROLNODES=1
fi

if [ "${KUBERNETES_DISTRO}" == "k3s" ] || [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	WANTED_KUBERNETES_VERSION=${KUBERNETES_VERSION}
	IFS=. read K8S_VERSION K8S_MAJOR K8S_MINOR <<< "${KUBERNETES_VERSION}"

	if [ ${K8S_MAJOR} -eq 28 ] && [ ${K8S_MINOR} -lt 5 ]; then 
		DELETE_CREDENTIALS_CONFIG=YES
	fi

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
fi

if [ "${VERBOSE}" == "YES" ]; then
	SILENT=
else
	SSH_OPTIONS="${SSH_OPTIONS} -q"
	SCP_OPTIONS="${SCP_OPTIONS} -q"
fi

if [ "${KUBERNETES_DISTRO}" == "k3s" ] || [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	TARGET_IMAGE="${ROOT_IMG_NAME}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}"
else
	TARGET_IMAGE="${ROOT_IMG_NAME}-k8s-${CNI_PLUGIN}-${KUBERNETES_VERSION}-${CONTAINER_ENGINE}-${SEED_ARCH}"
fi

TARGET_IMAGE="${PWD}/images/${TARGET_IMAGE}".img

export SSH_KEY_FNAME="$(basename ${SSH_PRIVATE_KEY})"
export SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"

export TARGET_CONFIG_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/config
export TARGET_DEPLOY_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/deployment
export TARGET_CLUSTER_LOCATION=${CONFIGURATION_LOCATION}/cluster/${NODEGROUP_NAME}

if [ "${EXTERNAL_ETCD}" = "true" ]; then
	export EXTERNAL_ETCD_ARGS="--use-external-etcd"
	ETCD_DST_DIR="/etc/etcd/ssl"
else
	export EXTERNAL_ETCD_ARGS="--no-use-external-etcd"
	ETCD_DST_DIR="/etc/kubernetes/pki/etcd"
fi

# Check if we can resume the creation process
if [ "${DELETE_CLUSTER}" = "YES" ]; then
	delete-masterkube.sh --configuration-location=${CONFIGURATION_LOCATION} --defs=${PLATEFORMDEFS} --node-group=${NODEGROUP_NAME}
	exit
elif [ ! -f ${TARGET_CONFIG_LOCATION}/buildenv ] && [ "${RESUME}" = "YES" ]; then
	echo_red "Unable to resume, building env is not found"
	exit -1
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

export SSH_KEY="$(cat ${SSH_PUBLIC_KEY})"

# GRPC network endpoint
if [ "${LAUNCH_CA}" != "YES" ]; then
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

	./bin/create-image.sh \
		--plateform=${PLATEFORM} \
		--k8s-distribution=${KUBERNETES_DISTRO} \
		--aws-access-key=${AWS_ACCESSKEY} \
		--aws-secret-key=${AWS_SECRETKEY} \
		--password="${KUBERNETES_PASSWORD}" \
		--distribution="${DISTRO}" \
		--cni-version="${CNI_VERSION}" \
		--custom-image="${TARGET_IMAGE}" \
		--kubernetes-version="${KUBERNETES_VERSION}" \
		--container-runtime=${CONTAINER_ENGINE} \
		--arch="${SEED_ARCH}" \
		--seed="${SEED_IMAGE}-${SEED_ARCH}" \
		--user="${SEED_USER}" \
		--ssh-key="${SSH_KEY}" \
		--ssh-priv-key="${SSH_PRIVATE_KEY}" \
		--primary-network="${VC_NETWORK_PUBLIC}" \
		--second-network="${VC_NETWORK_PRIVATE}"

	TARGET_IMAGE_UUID=$(get_vmuuid ${TARGET_IMAGE})
fi

if [ "${CREATE_IMAGE_ONLY}" = "YES" ]; then
	echo_blue_bold "Create image only, done..."
	exit 0
fi

if [ ${GRPC_PROVIDER} = "grpc" ]; then
	export CLOUD_PROVIDER_CONFIG=grpc-config.json
else
	export CLOUD_PROVIDER_CONFIG=grpc-config.yaml
fi

# Extract the domain name from CERT
export DOMAIN_NAME=$(openssl x509 -noout -subject -in ${SSL_LOCATION}/cert.pem -nameopt sep_multiline | grep 'CN=' | awk -F= '{print $2}' | sed -e 's/^[\s\t]*//')

# Delete previous exixting version
if [ "${RESUME}" = "NO" ] && [ "${UPGRADE_CLUSTER}" == "NO" ]; then
	echo_title "Launch custom ${MASTERKUBE} instance with ${TARGET_IMAGE}"
	delete-masterkube.sh --configuration-location=${CONFIGURATION_LOCATION} --defs=${PLATEFORMDEFS} --node-group=${NODEGROUP_NAME}
elif [ "${UPGRADE_CLUSTER}" == "NO" ]; then
	echo_title "Resume custom ${MASTERKUBE} instance with ${TARGET_IMAGE}"
else
	echo_title "Upgrade ${MASTERKUBE} instance with ${TARGET_IMAGE}"
	./bin/upgrade-cluster.sh
	exit
fi

mkdir -p ${TARGET_CONFIG_LOCATION}
mkdir -p ${TARGET_DEPLOY_LOCATION}
mkdir -p ${TARGET_CLUSTER_LOCATION}

if [ "${RESUME}" = "NO" ]; then
	update_build_env
else
	source ${TARGET_CONFIG_LOCATION}/buildenv
fi

echo "${KUBERNETES_PASSWORD}" >${TARGET_CONFIG_LOCATION}/kubernetes-password.txt

# Cloud init vendor-data
cat >${TARGET_CONFIG_LOCATION}/vendordata.yaml <<EOF
#cloud-config
package_update: true
package_upgrade: true
timezone: ${TZ}
ssh_authorized_keys:
  - ${SSH_KEY}
users:
  - default
system_info:
  default_user:
	name: ${KUBERNETES_USER}
EOF

gzip -c9 <${TARGET_CONFIG_LOCATION}/vendordata.yaml | base64 -w 0 | tee > ${TARGET_CONFIG_LOCATION}/vendordata.base64

IPADDRS=()
NODE_IP=${NET_IP}

if [ "${PUBLIC_IP}" != "DHCP" ]; then
	IFS=/ read PUBLIC_NODE_IP PUBLIC_MASK_CIDR <<< "${PUBLIC_IP}"
else
	PUBLIC_NODE_IP=DHCP
fi

# No external elb, use keep alived
if [[ ${FIRSTNODE} > 0 ]]; then
	delete_host "${MASTERKUBE}"
	add_host ${NODE_IP} ${MASTERKUBE} ${MASTERKUBE}.${DOMAIN_NAME}

	IPADDRS+=(${NODE_IP})
	NODE_IP=$(nextip ${NODE_IP})

	if [ "${PUBLIC_IP}" != "DHCP" ]; then
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
	fi
fi

if [ ${HA_CLUSTER} = "true" ]; then
	TOTALNODES=$((WORKERNODES + ${CONTROLNODES}))
else
	CONTROLNODES=0
	TOTALNODES=${WORKERNODES}
fi

PUBLIC_ROUTES_DEFS=$(build_routes ${NETWORK_PUBLIC_ROUTES[@]})
PRIVATE_ROUTES_DEFS=$(build_routes ${NETWORK_PRIVATE_ROUTES[@]})

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_vm() {
	local INDEX=$1
	local PUBLIC_NODE_IP=$2
	local NODE_IP=$3
	local MACHINE_TYPE=${CONTROL_PLANE_MACHINE}
	local NODEINDEX=${INDEX}
	local MASTERKUBE_NODE=
	local MASTERKUBE_NODE_UUID=
	local IPADDR=
	local VMHOST=
	local DISK_SIZE=
	local NUM_VCPUS=
	local MEMSIZE=

	if [ ${NODEINDEX} = 0 ]; then
		# node 0 is ELB on HA mode
		if [ ${HA_CLUSTER} = "true" ]; then
			MACHINE_TYPE=${NGINX_MACHINE}
		fi

		MASTERKUBE_NODE="${MASTERKUBE}"
	elif [[ ${NODEINDEX} > ${CONTROLNODES} ]]; then
		NODEINDEX=$((INDEX - ${CONTROLNODES}))
		MASTERKUBE_NODE="${NODEGROUP_NAME}-worker-0${NODEINDEX}"
		MACHINE_TYPE=${WORKER_NODE_MACHINE}
	else
		MASTERKUBE_NODE="${NODEGROUP_NAME}-master-0${NODEINDEX}"
	fi

	MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})

	if [ -z "${MASTERKUBE_NODE_UUID}" ]; then
		if [ "${PUBLIC_NODE_IP}" = "DHCP" ]; then
			NETWORK_DEFS=$(cat <<EOF
			{
				"network": {
					"version": 2,
					"ethernets": {
						"eth0": {
							"dhcp4": true,
							"gateway4": "${NET_GATEWAY}",
							"addresses": [
								"${NODE_IP}/${NET_MASK_CIDR}": {
									"label": "eth0:1"
								}
							]
						},
						"eth1": {
							"dhcp4": true,
							"dhcp4-overrides": {
								"use-routes": ${USE_DHCP_ROUTES_PUBLIC}
							}
						}
					}
				}
			}
EOF
)
		else
			NETWORK_DEFS=$(cat <<EOF
			{
				"network": {
					"version": 2,
					"ethernets": {
						"eth0": {
							"addresses": [
								"${NODE_IP}/${NET_MASK_CIDR}": {
									"label": "eth0:1"
								}
							]
						},
						"eth1": {
							"gateway4": "${NET_GATEWAY}",
							"addresses": [
								"${PUBLIC_NODE_IP}/${PUBLIC_MASK_CIDR}"
							],
							"nameservers": {
								"addresses": [
									"${NET_DNS}"
								]
							}
						}
					}
				}
			}
EOF
)
		fi

		if [ ${#NETWORK_PUBLIC_ROUTES[@]} -gt 0 ]; then
			NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --argjson ROUTES "${PUBLIC_ROUTES_DEFS}" '.network.ethernets.eth0.routes = $ROUTES')
		fi

		if [ ${#NETWORK_PRIVATE_ROUTES[@]} -gt 0 ]; then
			NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --argjson ROUTES "${PRIVATE_ROUTES_DEFS}" '.network.ethernets.eth1.routes = $ROUTES')
		fi

		echo ${NETWORK_DEFS} | jq . > ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.json

		# Cloud init meta-data
		echo ${NETWORK_DEFS} | yq -P - > ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.yaml
		export NETWORKCONFIG=$(cat ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.yaml | base64 -w 0 | tee ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.base64)

		# Cloud init user-data
		cat > ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.yaml <<EOF
#cloud-config
package_update: true
package_upgrade: true
timezone: ${TZ}
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false
write_files:
- encoding: b64
  content: ${NETWORKCONFIG}
  owner: root:root
  path: /etc/netplan/10-custom.yaml
  permissions: '0644'
runcmd:
- hostnamectl set-hostname ${MASTERKUBE_NODE}
- netplan apply
- echo "Create ${MASTERKUBE_NODE}" > /var/log/masterkube.log
EOF

		read MEMSIZE NUM_VCPUS DISK_SIZE <<<"$(jq -r --arg MACHINE ${MACHINE_TYPE} '.[$MACHINE]|.memsize,.vcpus,.disksize' templates/setup/${PLATEFORM}/machines.json | tr '\n' ' ')"

		if [ -z "${MEMSIZE}" ] || [ -z "${NUM_VCPUS}" ] || [ -z "${DISK_SIZE}" ]; then
			echo_red_bold "MACHINE_TYPE=${MACHINE_TYPE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE} not correctly defined"
			exit 1
		fi

		echo_line
		echo_blue_bold "Clone ${TARGET_IMAGE} to ${MASTERKUBE_NODE} TARGET_IMAGE=${TARGET_IMAGE} MASTERKUBE_NODE=${MASTERKUBE_NODE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE}M"
		echo_line

		# Clone my template
		echo_title "Launch ${MASTERKUBE_NODE}"
		multipass launch \
			-n ${MASTERKUBE_NODE} \
			-c ${NUM_VCPUS} \
			-m "${MEMSIZE}M" \
			-d "${DISK_SIZE}M" \
			--network name=${VC_NETWORK_PUBLIC},mode=manual \
			--cloud-init ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.yaml \
			file://${TARGET_IMAGE}

		IPADDR=$(multipass info "${MASTERKUBE_NODE}" --format json | jq -r --arg NAME ${MASTERKUBE_NODE}  '.info|.[$NAME].ipv4[0]')

		echo_title "Prepare ${MASTERKUBE_NODE} instance with IP:${IPADDR}"
		eval scp ${SCP_OPTIONS} bin ${KUBERNETES_USER}@${IPADDR}:~ ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} mkdir -p /home/${KUBERNETES_USER}/cluster ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo cp /home/${KUBERNETES_USER}/bin/* /usr/local/bin ${SILENT}

		# Update /etc/hosts
		delete_host "${MASTERKUBE_NODE}"
		add_host ${NODE_IP} ${MASTERKUBE_NODE} ${MASTERKUBE_NODE}.${DOMAIN_NAME}
	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"
	fi

	#echo_separator
}

for INDEX in $(seq ${FIRSTNODE} ${TOTALNODES})
do
	create_vm ${INDEX} ${PUBLIC_NODE_IP} ${NODE_IP}

	IPADDRS+=(${NODE_IP})

		# Reserve 2 ip for potentiel HA cluster
	if [[ "${HA_CLUSTER}" == "false" ]] && [[ ${INDEX} = 0 ]]; then
		NODE_IP=$(nextip ${NODE_IP})
		NODE_IP=$(nextip ${NODE_IP})
		if [ "${PUBLIC_IP}" != "DHCP" ]; then
			PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
			PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
		fi
	fi

	NODE_IP=$(nextip ${NODE_IP})

	if [ "${PUBLIC_IP}" != "DHCP" ]; then
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
	fi
done

wait_jobs_finish

CLUSTER_NODES=
ETCD_ENDPOINT=

if [ "${HA_CLUSTER}" = "true" ]; then
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

		prepare-etcd.sh --node-group=${NODEGROUP_NAME} --cluster-nodes="${CLUSTER_NODES}"

		for INDEX in $(seq 1 ${CONTROLNODES})
		do
			if [ ! -f ${TARGET_CONFIG_LOCATION}/etdc-0${INDEX}-prepared ]; then
				IPADDR="${IPADDRS[${INDEX}]}"

				echo_title "Start etcd node: ${IPADDR}"
				
				eval scp ${SCP_OPTIONS} bin ${KUBERNETES_USER}@${IPADDR}:~ ${SILENT}
				eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/* ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}
				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo cp /home/${KUBERNETES_USER}/bin/* /usr/local/bin ${SILENT}

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-etcd.sh --user=${KUBERNETES_USER} --cluster-nodes="${CLUSTER_NODES}" --node-index="${INDEX}" ${SILENT}

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

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo /usr/local/bin/install-keepalived.sh \
					"${IPADDRS[0]}" \
					"${KUBERNETES_PASSWORD}" \
					"$((80-INDEX))" \
					${IPADDRS[${INDEX}]} \
					${KEEPALIVED_PEER1} \
					${KEEPALIVED_PEER2} \
					${KEEPALIVED_STATUS} ${SILENT}

				touch ${TARGET_CONFIG_LOCATION}/keepalived-0${INDEX}-prepared
			fi
		done
	fi
else
	IPADDR="${IPADDRS[0]}"
	IPRESERVED1=$(nextip ${IPADDR})
	IPRESERVED2=$(nextip ${IPRESERVED1})
	CLUSTER_NODES="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDR},${NODEGROUP_NAME}-master-02.${DOMAIN_NAME}:${IPRESERVED1},${NODEGROUP_NAME}-master-03.${DOMAIN_NAME}:${IPRESERVED2}"

	echo "export CLUSTER_NODES=${CLUSTER_NODES}" >> ${TARGET_CONFIG_LOCATION}/buildenv
fi

CERT_SANS=$(collect_cert_sans "${IPADDRS[0]}" "${CLUSTER_NODES}" "${MASTERKUBE}.${DOMAIN_NAME}")

for INDEX in $(seq ${FIRSTNODE} ${TOTALNODES})
do
	NODEINDEX=${INDEX}
	if [ ${NODEINDEX} = 0 ]; then
		MASTERKUBE_NODE="${MASTERKUBE}"
	elif [[ ${NODEINDEX} > ${CONTROLNODES} ]]; then
		NODEINDEX=$((INDEX - ${CONTROLNODES}))
		MASTERKUBE_NODE="${NODEGROUP_NAME}-worker-0${NODEINDEX}"
	else
		MASTERKUBE_NODE="${NODEGROUP_NAME}-master-0${NODEINDEX}"
	fi

	if [ -f ${TARGET_CONFIG_LOCATION}/kubeadm-0${INDEX}-prepared ]; then
		echo_title "Already prepared VM ${MASTERKUBE_NODE}"
	else
		IPADDR="${IPADDRS[${INDEX}]}"
		VMUUID=$(get_vmuuid ${MASTERKUBE_NODE})

		echo_title "Prepare VM ${MASTERKUBE_NODE}, UUID=${VMUUID} with IP:${IPADDR}"

		eval scp ${SCP_OPTIONS} bin ${KUBERNETES_USER}@${IPADDR}:~ ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo cp /home/${KUBERNETES_USER}/bin/* /usr/local/bin ${SILENT}

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

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo create-cluster.sh \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
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
					--node-index=${NODEINDEX} \
					--cni=${CNI_PLUGIN} \
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

				ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo create-cluster.sh \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
					--vm-uuid=${VMUUID} \
					--csi-region=${REGION} \
					--csi-zone=${ZONEID} \
					--max-pods=${MAX_PODS} \
					--allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
					--container-runtime=${CONTAINER_ENGINE} \
					--use-external-etcd=${EXTERNAL_ETCD} \
					--node-group=${NODEGROUP_NAME} \
					--node-index=${NODEINDEX} \
					--load-balancer-ip=${IPADDRS[0]} \
					--cluster-nodes="${CLUSTER_NODES}" \
					--control-plane-endpoint="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDRS[1]}" \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--tls-san="${CERT_SANS}" \
					--ha-cluster=true \
					--cni=${CNI_PLUGIN} \
					--net-if=${NET_IF} \
					--kubernetes-version="${KUBERNETES_VERSION}" ${SILENT}

				eval scp ${SCP_OPTIONS} ${KUBERNETES_USER}@${IPADDR}:/etc/cluster/* ${TARGET_CLUSTER_LOCATION}/ ${SILENT}

				echo_blue_dot_title "Wait for ELB start on IP: ${IPADDRS[0]}"

				while :
				do
					echo_blue_dot
					curl -s -k "https://${IPADDRS[0]}:6443" &> /dev/null && break
					sleep 1
				done
				echo

				echo -n ${IPADDRS[0]}:6443 > ${TARGET_CLUSTER_LOCATION}/manager-ip
			elif [[ ${INDEX} > ${CONTROLNODES} ]] || [ "${HA_CLUSTER}" = "false" ]; then
					echo_blue_bold "Join node ${MASTERKUBE_NODE} instance worker node, kubernetes version=${KUBERNETES_VERSION}"

					eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/* ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

					eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh \
						--plateform=${PLATEFORM} \
						--cloud-provider=${CLOUD_PROVIDER} \
						--k8s-distribution=${KUBERNETES_DISTRO} \
						--delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
						--csi-region=${REGION} \
						--csi-zone=${ZONEID} \
						--max-pods=${MAX_PODS} \
						--vm-uuid=${VMUUID} \
						--use-external-etcd=${EXTERNAL_ETCD} \
						--node-group=${NODEGROUP_NAME} \
						--node-index=${NODEINDEX} \
						--control-plane-endpoint="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDRS[0]}" \
						--tls-san="${CERT_SANS}" \
						--etcd-endpoint="${ETCD_ENDPOINT}" \
						--net-if=${NET_IF} \
						--cluster-nodes="${CLUSTER_NODES}" ${SILENT}
			else
				echo_blue_bold "Join node ${MASTERKUBE_NODE} instance master node, kubernetes version=${KUBERNETES_VERSION}"

				eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/* ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
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

if [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	SERVER_ADDRESS="${MASTER_IP%%:*}:9345"
else
	SERVER_ADDRESS="${MASTER_IP}"
fi

if [ "${DELETE_CREDENTIALS_CONFIG}" == "YES" ]; then
	DELETE_CREDENTIALS_CONFIG=true
else
	DELETE_CREDENTIALS_CONFIG=false
fi

echo ${MACHINE_DEFS} | jq . > ${TARGET_CONFIG_LOCATION}/machines.json

echo $(eval "cat <<EOF
$(<${PWD}/templates/setup/${PLATEFORM}/autoscaler.json)
EOF") | jq . > ${TARGET_CONFIG_LOCATION}/autoscaler.json

echo $(eval "cat <<EOF
$(<${PWD}/templates/setup/${PLATEFORM}/provider.json)
EOF") | jq . > ${TARGET_CONFIG_LOCATION}/provider.json

source ./bin/create-deployment.sh

