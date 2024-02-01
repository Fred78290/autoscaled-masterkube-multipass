if [ -z "${PLATEFORM}" ]; then
    echo "export PLATEFORM=[ aws | vsphere | multipass | desktop ] not defined!"
    exit 1
fi

set -eu

export ACM_DOMAIN_NAME=
export AUTOSCALE_MACHINE="medium"
export AUTOSCALER_DESKTOP_UTILITY_ADDR=
export AUTOSCALER_DESKTOP_UTILITY_CACERT=
export AUTOSCALER_DESKTOP_UTILITY_CERT=
export AUTOSCALER_DESKTOP_UTILITY_KEY=
export AUTOSCALER_DESKTOP_UTILITY_TLS=
export AWS_ACCESSKEY=
export AWS_ROUTE53_ACCESSKEY=
export AWS_ROUTE53_PRIVATE_ZONE_ID=
export AWS_ROUTE53_PUBLIC_ZONE_ID=
export AWS_ROUTE53_SECRETKEY=
export AWS_ROUTE53_TOKEN=
export AWS_SECRETKEY=
export AWS_TOKEN=
export CACHE=${HOME}/.local/masterkube/${PLATEFORM}/cache
export CERT_DOMAIN=
export CERT_EMAIL=
export CERT_GODADDY_API_KEY=${GODADDY_API_KEY}
export CERT_GODADDY_API_SECRET=${GODADDY_API_SECRET}
export CERT_ZEROSSL_EAB_HMAC_SECRET=${ZEROSSL_EAB_HMAC_SECRET}
export CERT_ZEROSSL_EAB_KID=${ZEROSSL_EAB_KID}
export CERT_SELFSIGNED=NO
export CLOUD_IMAGES_UBUNTU=cloud-images.ubuntu.com
export CLOUD_PROVIDER_CONFIG=
export CLOUD_PROVIDER=
export CNI_PLUGIN=flannel
export CNI_VERSION=v1.4.0
export CONFIGURATION_LOCATION=${PWD}
export CONTAINER_ENGINE=containerd
export CONTAINER_CTL=docker
export CONTROL_PLANE_MACHINE="small"
export CONTROLNODES=1
export CONTROLPLANE_USE_PUBLICIP=false
export CORESTOTAL="0:16"
export CREATE_IMAGE_ONLY=NO
export DELETE_CLUSTER=NO
export DELETE_CREDENTIALS_CONFIG=NO
export DEPLOY_COMPONENTS=YES
export DISTRO=jammy
export DOMAIN_NAME=
export ETCD_DST_DIR=
export EXPOSE_PUBLIC_CLUSTER=false
export EXTERNAL_ETCD_ARGS=
export EXTERNAL_ETCD=false
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
export KUBECONFIG=${HOME}/.kube/config
export KUBERNETES_DISTRO=kubeadm
export KUBERNETES_PASSWORD=
export KUBERNETES_USER=kubernetes
export KUBERNETES_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
export LAUNCH_CA=YES
export LOAD_BALANCER_PORT=6443
export MASTER_INSTANCE_PROFILE_ARN=
export MASTER_NODE_ALLOW_DEPLOYMENT=NO
export MASTER_PROFILE_NAME="kubernetes-master-profile"
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
export NET_IF=eth0
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
export PREFER_SSH_PUBLICIP=NO
export PRIVATE_DOMAIN_NAME=
export PUBLIC_DOMAIN_NAME=
export PUBLIC_IP=DHCP
export PUBLIC_NETMASK=
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
export SEED_ARCH=amd64
export SEED_IMAGE="${DISTRO}-server-cloudimg-seed"
export SEED_USER=ubuntu
export SILENT="&> /dev/null"
export SSH_KEY_FNAME=
export SSH_KEY=$(cat ${HOME}/.ssh/id_rsa.pub)
export SSH_KEYNAME="aws-k8s-key"
export SSH_OPTIONS="-o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
export SSH_PRIVATE_KEY="${HOME}/.ssh/id_rsa"
export SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"
export SSL_LOCATION=${CONFIGURATION_LOCATION}/etc/ssl
export TARGET_CLUSTER_LOCATION=
export TARGET_CONFIG_LOCATION=
export TARGET_DEPLOY_LOCATION=
export TARGET_IMAGE_AMI=
export TARGET_IMAGE="${ROOT_IMG_NAME}-cni-${CNI_PLUGIN}-${KUBERNETES_VERSION}-${SEED_ARCH}-${CONTAINER_ENGINE}"
export TRANSPORT="tcp"
export UNREMOVABLENODERECHECKTIMEOUT="1m"
export UPDATE_PACKAGE=false
export UPGRADE_CLUSTER=NO
export USE_DHCP_ROUTES_PRIVATE=true
export USE_DHCP_ROUTES_PUBLIC=true
export USE_KEEPALIVED=NO
export USE_NGINX_GATEWAY=NO
export USE_NLB=NO
export USE_ZEROSSL=YES
export VC_NETWORK_PRIVATE_TYPE=
export VC_NETWORK_PRIVATE="bridged100"
export VC_NETWORK_PUBLIC_TYPE=
export VC_NETWORK_PUBLIC="en0"
export VC_NETWORK_PUBLIC_ENABLED=true
export VERBOSE=NO
export VMREST_FOLDER=
export VMREST_INSECURE=true
export VMREST_PASSWORD=
export VMREST_URL=
export VMREST_USERNAME=
export VOLUME_SIZE=20
export VOLUME_TYPE=gp3
export VPC_PRIVATE_SECURITY_GROUPID=
export VPC_PRIVATE_SUBNET_ID=
export VPC_PUBLIC_SECURITY_GROUPID=
export VPC_PUBLIC_SUBNET_ID=
export WORKER_INSTANCE_PROFILE_ARN=
export WORKER_NODE_MACHINE="medium"
export WORKER_PROFILE_NAME="kubernetes-worker-profile"
export WORKERNODE_USE_PUBLICIP=false
export WORKERNODES=3
export ZONEID=office

export SCP_OPTIONS="${SSH_OPTIONS} -p -r"

export NODEGROUP_NAME="${PLATEFORM}-ca-k8s"
export MASTERKUBE=${NODEGROUP_NAME}-masterkube
export DASHBOARD_HOSTNAME=masterkube-${PLATEFORM}-dashboard
export TARGET_CONFIG_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/config
export TARGET_DEPLOY_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/deployment
export TARGET_CLUSTER_LOCATION=${CONFIGURATION_LOCATION}/cluster/${NODEGROUP_NAME}

export PLATEFORMDEFS=${CURDIR}/plateform/${PLATEFORM}/vars.def

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
function common_usage() {
cat <<EOF
$0 create a kubernetes simple cluster or HA cluster with 3 control planes
Options are:
--help | -h                                      # Display usage
--plateform=[vsphere|aws|desktop|multipass]      # Where to deploy cluster
--verbose | -v                                   # Verbose
--trace | -x                                     # Trace execution
--resume | -r                                    # Allow to resume interrupted creation of cluster kubernetes
--delete | -d                                    # Delete cluster and exit
--distribution                                   # Ubuntu distribution to use ${DISTRO}
--create-image-only                              # Create image only
--upgrade                                        # Upgrade existing cluster to upper version of kubernetes

### Flags to set some location informations

--configuration-location=<path>                  # Specify where configuration will be stored, default ${CONFIGURATION_LOCATION}
--ssl-location=<path>                            # Specify where the etc/ssl dir is stored, default ${SSL_LOCATION}
--defs=<path>                                    # Specify the ${PLATEFORM} definitions, default ${PLATEFORMDEFS}

### Design the kubernetes cluster

--autoscale-machine=<value>                      # Override machine type used for auto scaling, default ${AUTOSCALE_MACHINE}
--cni-plugin=<value>                             # Override CNI plugin, default: ${CNI_PLUGIN}
--cni-version=<value>                            # Override CNI plugin version, default: ${CNI_VERSION}
--container-runtime=<docker|containerd|cri-o>    # Specify which OCI runtime to use, default ${CONTAINER_ENGINE}
--control-plane-machine=<value>                  # Override machine type used for control plane, default ${CONTROL_PLANE_MACHINE}
--ha-cluster | -c                                # Allow to create an HA cluster, default ${HA_CLUSTER}
--k8s-distribution=<kubeadm|k3s|rke2>            # Which kubernetes distribution to use: kubeadm, k3s, rke2, default ${KUBERNETES_DISTRO}
--kubernetes-version | -k=<value>                # Override the kubernetes version, default ${KUBERNETES_VERSION}
--max-pods=<value>                               # Specify the max pods per created VM, default ${MAX_PODS}
--nginx-machine=<value>                          # Override machine type used for nginx as ELB, default ${NGINX_MACHINE}
--node-group=<value>                             # Override the node group name, default ${NODEGROUP_NAME}
--ssh-private-key=<path>                         # Override ssh key is used, default ${SSH_PRIVATE_KEY}
--transport=<value>                              # Override the transport to be used between autoscaler and kubernetes-cloud-autoscaler, default ${TRANSPORT}
--worker-node-machine=<value>                    # Override machine type used for worker nodes, default ${WORKER_NODE_MACHINE}
--worker-nodes=<value>                           # Specify the number of worker nodes created in HA cluster, default ${WORKERNODES}
--create-external-etcd | -e                      # Create an external HA etcd cluster, default ${EXTERNAL_ETCD}

### Design domain

--public-domain=<value>                          # Specify the public domain to use, default ${PUBLIC_DOMAIN_NAME}
--private-domain=<value>                         # Specify the private domain to use, default ${PRIVATE_DOMAIN_NAME}
--dashboard-hostname=<value>                     # Specify the hostname for kubernetes dashboard, default ${DASHBOARD_HOSTNAME}

### Cert Manager

--cert-email=<value>                             # Specify the mail for lets encrypt, default ${CERT_EMAIL}
--use-zerossl                                    # Specify cert-manager to use zerossl, default ${USE_ZEROSSL}
--use-self-signed-ca                             # Specify if use self-signed CA, default ${CERT_SELFSIGNED}
--zerossl-eab-kid=<value>                        # Specify zerossl eab kid, default ${CERT_ZEROSSL_EAB_KID}
--zerossl-eab-hmac-secret=<value>                # Specify zerossl eab hmac secret, default ${CERT_ZEROSSL_EAB_HMAC_SECRET}

  # GoDaddy
--godaddy-key                                    # Specify godaddy api key
--godaddy-secret                                 # Specify godaddy api secret

  # Route53
--route53-zone-id                                # Specify the route53 zone id, default ${AWS_ROUTE53_PUBLIC_ZONE_ID}
--route53-access-key                             # Specify the route53 aws access key, default ${AWS_ROUTE53_ACCESSKEY}
--route53-secret-key                             # Specify the route53 aws secret key, default ${AWS_ROUTE53_SECRETKEY}

### Flags for autoscaler
--cloudprovider=<value>                          # autoscaler flag <grpc|externalgrpc>, default: ${GRPC_PROVIDER}
--max-nodes-total=<value>                        # autoscaler flag, default: ${MAXTOTALNODES}
--cores-total=<value>                            # autoscaler flag, default: ${CORESTOTAL}
--memory-total=<value>                           # autoscaler flag, default: ${MEMORYTOTAL}
--max-autoprovisioned-node-group-count=<value>   # autoscaler flag, default: ${MAXAUTOPROVISIONNEDNODEGROUPCOUNT}
--scale-down-enabled=<value>                     # autoscaler flag, default: ${SCALEDOWNENABLED}
--scale-down-delay-after-add=<value>             # autoscaler flag, default: ${SCALEDOWNDELAYAFTERADD}
--scale-down-delay-after-delete=<value>          # autoscaler flag, default: ${SCALEDOWNDELAYAFTERDELETE}
--scale-down-delay-after-failure=<value>         # autoscaler flag, default: ${SCALEDOWNDELAYAFTERFAILURE}
--scale-down-unneeded-time=<value>               # autoscaler flag, default: ${SCALEDOWNUNEEDEDTIME}
--scale-down-unready-time=<value>                # autoscaler flag, default: ${SCALEDOWNUNREADYTIME}
--unremovable-node-recheck-timeout=<value>       # autoscaler flag, default: ${UNREMOVABLENODERECHECKTIMEOUT}

EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function add_host() {
	local LINE=

	for ARG in $@
	do
		if [ -n "${LINE}" ]; then
			LINE="${LINE} ${ARG}"
		else
			LINE="${ARG}     "
		fi
	done

	sudo bash -c "echo '${LINE}' >> /etc/hosts"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function verbose() {
	if [ ${VERBOSE} = "YES" ]; then
		eval "$1"
	else
		eval "$1 &> /dev/null"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_jobs_finish() {
	wait $(jobs -p)
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_dot() {
	>&2 echo -n -e "\x1B[90m\x1B[39m\x1B[1m\x1B[34m.\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_dot_title() {
	# echo message in blue and bold
	>&2 echo -n -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[39m\x1B[1m\x1B[34m$1\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_bold() {
	# echo message in blue and bold
	>&2 echo -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[39m\x1B[1m\x1B[34m$1\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_title() {
	# echo message in blue and bold
	echo
	echo_line
	echo_blue_bold "$1"
	echo_line
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_grey() {
	# echo message in light grey
	>&2 echo -e "\x1B[90m$1\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_red() {
	# echo message in red
	>&2 echo -e "\x1B[31m$1\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_red_bold() {
	# echo message in blue and bold
	>&2 echo -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[31m\x1B[1m\x1B[31m$1\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_separator() {
	echo_line
	>&2 echo
	>&2 echo
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_line() {
	echo_grey "============================================================================================================================="
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_ssh_ready() {
	while :
	do
		ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=1 $1 'exit 0' && break
 
		sleep 5
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function nextip()
{
	local IP=$1

	if [ "${IP}" == "DHCP" ] || [ "${IP}" == "NONE" ]; then
		echo "${IP}"
	else
		local IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo ${IP} | tr '.' ' '`)
		local NEXT_IP_HEX=$(printf %.8X `echo $(( 0x${IP_HEX} + 1 ))`)
		local NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo ${NEXT_IP_HEX} | sed -r 's/(..)/0x\1\ /g'`)

		echo "${NEXT_IP}"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function build_routes() {
	local ROUTES="[]"
	local ROUTE=

	for ROUTE in $@
	do
		local TO=
		local VIA=
		local METRIC=500

		IFS=, read -a DEFS <<< "${ROUTE}"

		for DEF in ${DEFS[@]}
		do
			IFS== read KEY VALUE <<< "${DEF}"
			case ${KEY} in
				to)
					TO=${VALUE}
					;;
				via)
					VIA=${VALUE}
					;;
				metric)
					METRIC=${VALUE}
					;;
			esac
		done

		if [ -n "${TO}" ] && [ -n "${VIA}" ]; then
			ROUTES=$(echo ${ROUTES} | jq --arg TO ${TO} --arg VIA ${VIA} --argjson METRIC ${METRIC} '. += [{ "to": $TO, "via": $VIA, "metric": $METRIC }]')
		fi
	done

	echo -n ${ROUTES}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function collect_cert_sans() {
	local LOAD_BALANCER_IP=$1
	local CLUSTER_NODES=$2
	local CERT_EXTRA_SANS=$3

	local LB_IP=
	local CERT_EXTRA=
	local CLUSTER_NODE=
	local CLUSTER_IP=
	local CLUSTER_HOST=
	local TLS_SNA=(
		"${LOAD_BALANCER_IP}"
	)

	for CERT_EXTRA in $(echo ${CERT_EXTRA_SANS} | tr ',' ' ')
	do
		if [[ ! ${TLS_SNA[*]} =~ "${CERT_EXTRA}" ]]; then
			TLS_SNA+=("${CERT_EXTRA}")
		fi
	done

	for CLUSTER_NODE in $(echo ${CLUSTER_NODES} | tr ',' ' ')
	do
		IFS=: read CLUSTER_HOST CLUSTER_IP <<< "${CLUSTER_NODE}"

		if [ -n ${CLUSTER_IP} ] && [[ ! ${TLS_SNA[*]} =~ "${CLUSTER_IP}" ]]; then
			TLS_SNA+=("${CLUSTER_IP}")
		fi

		if [ -n "${CLUSTER_HOST}" ]; then
			if [[ ! ${TLS_SNA[*]} =~ "${CLUSTER_HOST}" ]]; then
				TLS_SNA+=("${CLUSTER_HOST}")
				TLS_SNA+=("${CLUSTER_HOST%%.*}")
			fi
		fi
	done

	echo -n "${TLS_SNA[*]}" | tr ' ' ','
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function cidr_to_netmask() {
    value=$(( 0xffffffff ^ ((1 << (32 - $1)) - 1) ))
    echo "$(( (value >> 24) & 0xff )).$(( (value >> 16) & 0xff )).$(( (value >> 8) & 0xff )).$(( value & 0xff ))"
}
#===========================================================================================================================================
#
#===========================================================================================================================================
function ipv4() {
	local INF=$1
	local LOCAL_IPADDR=

	if [ "${OSDISTRO}" == "Darwin" ]; then
		read -a LOCAL_IPADDR <<< "$(ifconfig ${INF} | grep -m 1 "inet\s" | sed -n 1p)"
	else
		read -a LOCAL_IPADDR <<< "$(ip addr show ${INF} | grep -m 1 "inet\s" | tr '/' ' ' | cut -d ' ' -f 2 3)"
	fi

	echo -n "${LOCAL_IPADDR[1]}"
}
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

source ${CURDIR}/plateform/${PLATEFORM}/plateform.sh

source ${PLATEFORMDEFS}

#===========================================================================================================================================
#
#===========================================================================================================================================

if [ -f ${HOME}/Library/etc/ssl/${PUBLIC_DOMAIN_NAME}/cert.pem ]; then
    SSL_LOCATION=${HOME}/Library/etc/ssl/${PUBLIC_DOMAIN_NAME}
elif [ -f $HOME/.acme.sh/${PUBLIC_DOMAIN_NAME}/cert.pem ]; then
    SSL_LOCATION=$HOME/.acme.sh/${PUBLIC_DOMAIN_NAME}
elif [ -f ${HOME}/Library/etc/ssl/${NET_DOMAIN}/cert.pem ]; then
    SSL_LOCATION=${HOME}/Library/etc/ssl/${NET_DOMAIN}
elif [ -f $HOME/.acme.sh/${NET_DOMAIN}/cert.pem ]; then
    SSL_LOCATION=$HOME/.acme.sh/${NET_DOMAIN}
fi

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

