if [ -z "${PLATEFORM}" ]; then
    echo "export PLATEFORM=[ aws | vsphere | multipass | desktop ] not defined!"
    exit 1
fi

set -eu

export ANNOTE_MASTER=
export APISERVER_ADVERTISE_PORT=6443
export AUTOSCALE_MACHINE="medium"
export AUTOSCALER_DESKTOP_UTILITY_ADDR=
export AUTOSCALER_DESKTOP_UTILITY_CACERT=
export AUTOSCALER_DESKTOP_UTILITY_CERT=
export AUTOSCALER_DESKTOP_UTILITY_KEY=
export AUTOSCALER_DESKTOP_UTILITY_TLS=
export AUTOSTART=true
export AWS_ACCESSKEY=
export AWS_ROUTE53_ACCESSKEY=
export AWS_ROUTE53_PRIVATE_ZONE_ID=
export AWS_ROUTE53_PROFILE=
export AWS_ROUTE53_PUBLIC_ZONE_ID=
export AWS_ROUTE53_SECRETKEY=
export AWS_ROUTE53_TOKEN=
export AWS_SECRETKEY=
export AWS_TOKEN=
export CA_LOCATION=
export CACHE=${HOME}/.local/masterkube/${PLATEFORM}/cache
export CERT_EMAIL=
export CERT_GODADDY_API_KEY=${GODADDY_API_KEY:=}
export CERT_GODADDY_API_SECRET=${GODADDY_API_SECRET:=}
export CERT_SELFSIGNED=YES
export CERT_SELFSIGNED_FORCED=NO
export CERT_ZEROSSL_EAB_HMAC_SECRET=${ZEROSSL_EAB_HMAC_SECRET:=}
export CERT_ZEROSSL_EAB_KID=${ZEROSSL_EAB_KID:=}
export CLOUD_IMAGES_UBUNTU=cloud-images.ubuntu.com
export CLOUD_PROVIDER_CONFIG=
export CLOUD_PROVIDER=external
export CLUSTER_NODES=
export CNI_PLUGIN=flannel
export CNI_VERSION=v1.4.0
export CONFIGURATION_LOCATION=${PWD}
export CONTAINER_CTL=docker
export CONTAINER_ENGINE=containerd
export CONTROL_PLANE_ENDPOINT=
export CONTROL_PLANE_MACHINE="medium"
export CONTROLNODES=1
export CONTROLPLANE_USE_PUBLICIP=false
export CORESTOTAL="0:24"
export CREATE_IMAGE_ONLY=NO
export DASHBOARD_HOSTNAME=
export DELETE_CLUSTER=NO
export DEPLOY_COMPONENTS=YES
export DEPLOY_MODE=dev
export DISTRO=noble
export DOMAIN_NAME=
export ETCD_DST_DIR=
export ETCD_ENDPOINT=
export EXPOSE_PUBLIC_CLUSTER=false
export EXPOSE_PUBLIC_PORTS=80,443
export EXTERNAL_DNS_PROVIDER=none
export EXTERNAL_DNS_TARGET=
export EXTERNAL_ETCD_ARGS=
export EXTERNAL_ETCD=false
export INTERNAL_SECURITY_GROUP=
export EXTERNAL_SECURITY_GROUP=
export USE_ETC_HOSTS=true
export FIRST_WORKER_NODE_IP=
export FIRSTNODE=0
export GOVC_DATACENTER=${GOVC_DATACENTER:=}
export GOVC_DATASTORE=${GOVC_DATASTORE:=}
export GOVC_FOLDER=${GOVC_FOLDER:=}
export GOVC_HOST=${GOVC_HOST:=}
export GOVC_INSECURE=${GOVC_INSECURE:=}
export GOVC_NETWORK=${GOVC_NETWORK:=}
export GOVC_PASSWORD=${GOVC_PASSWORD:=}
export GOVC_RESOURCE_POOL=${GOVC_RESOURCE_POOL:=}
export GOVC_URL=${GOVC_URL:=}
export GOVC_USERNAME=${GOVC_USERNAME:=}
export GOVC_VIM_VERSION=${GOVC_VIM_VERSION:='6.0'}
export GRPC_PROVIDER=externalgrpc
export HA_CLUSTER=false
export IMAGE_CREDENTIALS_BIN=/usr/local/bin
export IMAGE_CREDENTIALS_CONFIG=/etc/kubernetes/credential.yaml
export KUBECONFIG=${HOME}/.kube/config
export KUBERNETES_DISTRO=k3s
export KUBERNETES_PASSWORD=
export KUBERNETES_USER=kubernetes
export KUBERNETES_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
export LAUNCH_CA=YES
export LOAD_BALANCER_IP=
export LOAD_BALANCER_PORT=
export MASTER_INSTANCE_PROFILE_ARN=
export MASTER_NODE_ALLOW_DEPLOYMENT=NO
export MASTER_PROFILE_NAME="kubernetes-master-profile"
export MASTERKUBE=
export MAX_PODS=110
export MAXAUTOPROVISIONNEDNODEGROUPCOUNT="1"
export MAXNODEPROVISIONTIME=15m
export MAXNODES=9
export MAXTOTALNODES=${MAXNODES}
export MEMORYTOTAL="0:96"
export METALLB_IP_RANGE=10.0.0.88-10.0.0.89
export MICROK8S_CHANNEL=latest
export MINNODES=0
export NETWORK_PRIVATE_ROUTES=()
export NETWORK_PUBLIC_ROUTES=()
export NFS_SERVER_ADDRESS=10.0.0.5
export NFS_SERVER_PATH=/mnt/Home/home/vmware
export NFS_STORAGE_CLASS=nfs-client
export NGINX_MACHINE="tiny"
export NODEGROUP_NAME=
export OS_APPLICATION_CREDENTIAL_ID=
export OS_APPLICATION_CREDENTIAL_NAME=
export OS_APPLICATION_CREDENTIAL_SECRET=
export OS_AUTH_URL=
export OS_DOMAIN_ID=
export OS_DOMAIN_NAME=
export OS_PASSWORD=
export OS_PRIVATE_DNS_ZONEID=
export OS_PROJECT_ID=
export OS_PROJECT_NAME=
export OS_PUBLIC_DNS_ZONEID=
export OS_REGION_NAME=RegionOne
export OS_SYSTEM_SCOPE=
export OS_TENANT_ID=
export OS_TENANT_NAME=
export OS_USER_DOMAIN_NAME=
export OS_USERNAME=
export OS_ZONE_NAME=nova
export OSDISTRO=$(uname -s)
export PREFER_SSH_PUBLICIP=NO
export PRIVATE_ADDR_IPS=()
export PRIVATE_DNS_NAMES=()
export PRIVATE_DNS=192.168.2.1
export PRIVATE_DOMAIN_NAME=acme.com
export PRIVATE_GATEWAY=192.168.2.254
export PRIVATE_GATEWAY_METRIC=100
export PRIVATE_IP=192.168.2.80
export PRIVATE_MASK_CIDR=24
export PRIVATE_NET_INF=eth0
export PRIVATE_NETMASK=255.255.255.0
export PUBLIC_ADDR_IPS=()
export PUBLIC_DOMAIN_NAME=acme.com
export PUBLIC_IP=DHCP
export PUBLIC_NETMASK=
export PUBLIC_DNS=
export PUBLIC_GATEWAY=
export PUBLIC_GATEWAY_METRIC=100
export PUBLIC_NET_INF=eth1
export REGION=home
export REGISTRY=fred78290
export RESUME=NO
export SCALEDNODES_DHCP=true
export SCALEDOWNDELAYAFTERADD="1m"
export SCALEDOWNDELAYAFTERDELETE="1m"
export SCALEDOWNDELAYAFTERFAILURE="1m"
export SCALEDOWNENABLED="true"
export SCALEDOWNGPUUTILIZATIONTHRESHOLD="0.5"
export SCALEDOWNUNEEDEDTIME="1m"
export SCALEDOWNUNREADYTIME="1m"
export SCALEDOWNUTILIZATIONTHRESHOLD="0.5"
export SEED_ARCH=$([[ "$(uname -m)" =~ arm64|aarch64 ]] && echo -n arm64 || echo -n amd64)
export SEED_IMAGE="${DISTRO}-server-cloudimg-seed"
export SEED_USER=ubuntu
export SILENT="&> /dev/null"
export SSH_KEY_FNAME=
export SSH_KEY=$(cat ${HOME}/.ssh/id_rsa.pub)
export SSH_KEYNAME="ssh-k8s-key"
export SSH_OPTIONS="-o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
export SSH_PRIVATE_KEY="${HOME}/.ssh/id_rsa"
export SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"
export SSL_LOCATION=
export TARGET_CLUSTER_LOCATION=
export TARGET_CONFIG_LOCATION=
export TARGET_DEPLOY_LOCATION=
export TARGET_IMAGE_AMI=
export TARGET_IMAGE="${DISTRO}-kubernetes-cni-${CNI_PLUGIN}-${KUBERNETES_VERSION}-${SEED_ARCH}-${CONTAINER_ENGINE}"
export TRACE_ARGS=
export TRACE_CURL=NO
export TRACE_FILE_CURL="utility-$(date +%s).log"
export TRANSPORT="tcp"
export UNREMOVABLENODERECHECKTIMEOUT="1m"
export UPDATE_PACKAGE=false
export UPGRADE_CLUSTER=NO
export USE_CLOUDINIT_TO_CONFIGURE=false
export USE_DHCP_ROUTES_PRIVATE=true
export USE_DHCP_ROUTES_PUBLIC=true
export USE_LOADBALANCER=false
export USE_NLB=none
export USE_ZEROSSL=NO
export VC_NETWORK_PRIVATE_TYPE=
export VC_NETWORK_PRIVATE="bridged100"
export VC_NETWORK_PUBLIC_ENABLED=true
export VC_NETWORK_PUBLIC_TYPE=
export VC_NETWORK_PUBLIC="en0"
export VERBOSE=NO
export VMREST_FOLDER=
export VMREST_INSECURE=true
export VMREST_PASSWORD=
export VMREST_URL=
export VMREST_USERNAME=
export VOLUME_SIZE=20
export VOLUME_TYPE=gp3
export VPC_PRIVATE_SECURITY_GROUPID=
export VPC_PRIVATE_SUBNET_ID=()
export VPC_PRIVATE_SUBNET_IDS=()
export VPC_PUBLIC_SECURITY_GROUPID=
export VPC_PUBLIC_SUBNET_ID=()
export VPC_PUBLIC_SUBNET_IDS=()
export WORKER_INSTANCE_PROFILE_ARN=
export WORKER_NODE_MACHINE="medium"
export WORKER_PROFILE_NAME="kubernetes-worker-profile"
export WORKERNODE_USE_PUBLICIP=false
export WORKERNODES=3
export ZONEID=office

export INSTALL_BIND9_SERVER=NO
export USE_BIND9_SERVER=false
export BIND9_HOST=
export BIND9_PORT=53
export BIND9_RNDCKEY=${CURDIR}/../etc/bind/rndc.key

export SCP_OPTIONS="${SSH_OPTIONS} -p -r"

export TARGET_CONFIG_LOCATION=
export TARGET_DEPLOY_LOCATION=
export TARGET_CLUSTER_LOCATION=

export PLATEFORMDEFS=${CURDIR}/plateform/${PLATEFORM}/vars.def

if [ "${OSDISTRO}" == "Darwin" ]; then
    export VMWAREWM=".vmwarevm"
else
    export VMWAREWM=""
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

#===========================================================================================================================================
#
#===========================================================================================================================================

source ${CURDIR}/echo.sh
source ${CURDIR}/network.sh
source ${CURDIR}/functions.sh

#===========================================================================================================================================
#
#===========================================================================================================================================
if [ "${OSDISTRO}" == "Darwin" ]; then
	if [ -z "$(command -v cfssl)" ]; then
		echo_red_bold "You must install gnu cfssl with brew (brew install cfssl)"
		exit 1
	fi

	if [ -z "$(command -v gsed)" ]; then
		echo_red_bold "You must install gnu sed with brew (brew install gsed), this script is not compatible with the native macos sed"
		exit 1
	fi

	if [ -z "$(command -v gbase64)" ]; then
		echo_red_bold "You must install gnu base64 with brew (brew install coreutils), this script is not compatible with the native macos base64"
		exit 1
	fi

	if [ ! -e /usr/local/opt/gnu-getopt/bin/getopt ] && [ ! -e /opt/homebrew/opt/gnu-getopt/bin/getopt ]; then
		echo_red_bold "You must install gnu gnu-getopt with brew (brew install coreutils), this script is not compatible with the native macos base64"
		exit 1
	fi

	if [ -z "$(command -v jq)" ]; then
		echo_red_bold "You must install gnu jq with brew (brew install jq)"
		exit 1
	fi

	shopt -s expand_aliases

	alias base64=gbase64
	alias sed=gsed

	if [ -e /usr/local/opt/gnu-getopt/bin/getopt ]; then
		alias getopt=/usr/local/opt/gnu-getopt/bin/getopt
	else
		alias getopt=/opt/homebrew/opt/gnu-getopt/bin/getopt
	fi

	function delete_host() {
		sudo gsed -i "/$1/d" /etc/hosts
	}

	TZ=$(sudo systemsetup -gettimezone | awk -F: '{print $2}' | tr -d ' ')
	TRANSPORT_IF=$(route get 1 | grep -m 1 interface | awk '{print $2}')
	LOCAL_IPADDR=$(ifconfig ${TRANSPORT_IF} | grep -m 1 "inet\s" | sed -n 1p | awk '{print $2}')
else
	TZ=$(cat /etc/timezone)
	TRANSPORT_IF=$(ip route get 1 | awk '{print $5;exit}')
	LOCAL_IPADDR=$(ip addr show ${TRANSPORT_IF} | grep -m 1 "inet\s" | tr '/' ' ' | awk '{print $2}')

	function delete_host() {
		sudo sed -i "/$1/d" /etc/hosts
	}
fi

#===========================================================================================================================================
#
#===========================================================================================================================================
mkdir -p ${CACHE}

if [ -f ${CURDIR}/plateform/${PLATEFORM}/override.sh ]; then
	source ${CURDIR}/plateform/${PLATEFORM}/override.sh
fi

source ${CURDIR}/plateform/${PLATEFORM}/plateform.sh
source ${PLATEFORMDEFS}

#===========================================================================================================================================
#
#===========================================================================================================================================
for MANDATORY in ${CMD_MANDATORIES}
do
	if [ -z "$(command -v ${MANDATORY})" ]; then
		echo_red "The command ${MANDATORY} is missing"
		exit 1
	fi
done

