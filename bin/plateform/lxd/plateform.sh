CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl lxc packer qemu-img"
CLOUD_PROVIDER=

export LXD_INTERNAL_NLB=none
export LXD_EXTERNAL_NLB=none

source ${PLATEFORMDEFS}

#===========================================================================================================================================
#
#===========================================================================================================================================
function usage() {
	common_usage
	cat <<EOF
### Flags ${PLATEFORM} plateform specific

  # Flags to connect lxd client
--lxd-remote                                   # The remote lxd server, default: ${LXD_REMOTE}
--lxd-profile                                  # The lxd profile, default: ${LXD_KUBERNETES_PROFILE}
--lxd-project                                  # The lxd project, default: ${LXD_PROJECT}

--lxd-tls-client-cert                          # TLS certificate to use for client authentication, default: ${LXD_TLS_CLIENT_CERT}
--lxd-tls-client-key                           # TLS key to use for client authentication: ${LXD_TLS_CLIENT_KEY}
--lxd-tls-server-cert                          # TLS certificate of the remote server. If not specified, the system CA is used, default: ${LXD_TLS_SERVER_CERT}
--lxd-tls-ca                                   # TLS CA to validate against when in PKI mode, default: ${LXD_TLS_CA}
  # Flags to configure nfs client provisionner
--nfs-server-adress                            # The NFS server address, default: ${NFS_SERVER_ADDRESS}
--nfs-server-mount                             # The NFS server mount path, default: ${NFS_SERVER_PATH}
--nfs-storage-class                            # The storage class name to use, default: ${NFS_STORAGE_CLASS}

  # Flags to set the template vm
--seed-image=<value>                           # Override the seed image name used to create template, default: ${SEED_IMAGE}
--kube-user=<value>                            # Override the seed user in template, default: ${KUBERNETES_USER}
--kube-password | -p=<value>                   # Override the password to ssh the cluster VM, default random word

  # RFC2136 space
--use-named-server=[true|false]                # Tell if we use bind9 server for DNS registration, default: ${USE_BIND9_SERVER}
--install-named-server                         # Tell if we install bind9 server for DNS registration, default: ${INSTALL_BIND9_SERVER}
--named-server-host=<host address>             # Host of used bind9 server for DNS registration, default: ${BIND9_HOST}
--named-server-port=<bind port>                # Port of used bind9 server for DNS registration, default: ${BIND9_PORT}
--named-server-key=<path>                      # RNDC key file for used bind9 server for DNS registration, default: ${BIND9_RNDCKEY}

  # Flags to configure network in ${PLATEFORM}
--use-nlb=[none|cloud|nginx|keepalived]        # Wich load balancer to use
--vm-private-network=<value>                   # Override the name of the private network in ${PLATEFORM}, default: ${VC_NETWORK_PRIVATE}
--vm-public-network=<value>                    # Override the name of the public network in ${PLATEFORM}, empty for none second interface, default: ${VC_NETWORK_PUBLIC}
--no-dhcp-autoscaled-node                      # Autoscaled node don't use DHCP, default: ${SCALEDNODES_DHCP}
--dhcp-autoscaled-node                         # Autoscaled node use DHCP, default: ${SCALEDNODES_DHCP}
--private-domain=<value>                       # Override the domain name, default: ${PRIVATE_DOMAIN_NAME}

--public-address=<value>                       # The public address to expose kubernetes endpoint[ipv4/cidr, DHCP, NONE], default: ${PUBLIC_IP}
--metallb-ip-range                             # Override the metalb ip range, default: ${METALLB_IP_RANGE}
--add-route-private                            # Add route to private network syntax is --add-route-private=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-private=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default: ${NETWORK_PRIVATE_ROUTES[@]}
--add-route-public                             # Add route to public network syntax is --add-route-public=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-public=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default: ${NETWORK_PUBLIC_ROUTES[@]}

EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function parse_arguments() {
	OPTIONS+=(
		"lxd-remote:"
		"lxd-profile:"
		"lxd-project:"
		"lxd-tls-client-cert:"
		"lxd-tls-client-key:"
		"lxd-tls-server-cert:"
		"lxd-tls-ca:"
		"add-route-private:"
		"add-route-public:"
		"dhcp-autoscaled-node"
		"dont-use-dhcp-routes-private"
		"dont-use-dhcp-routes-public"
		"install-named-server"
		"metallb-ip-range:"
		"named-server-host:"
		"named-server-key:"
		"named-server-port:"
		"net-address:"
		"net-dns:"
		"net-gateway:"
		"nfs-server-adress:"
		"nfs-server-mount:"
		"nfs-storage-class:"
		"no-dhcp-autoscaled-node"
		"private-domain:"
		"public-address:"
		"use-named-server"
		"use-nlb:"
		"vm-private-network:"
		"vm-public-network:"
	)

	PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
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
			UBUNTU_DISTRIBUTION=$2
			SEED_IMAGE="${UBUNTU_DISTRIBUTION}-server-cloudimg-seed"
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
			USE_CERT_SELFSIGNED=YES
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
		--external-dns-provider)
			EXTERNAL_DNS_PROVIDER=$2
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
		-k|--kube-version)
			KUBERNETES_VERSION="$2"
			if [ ${KUBERNETES_VERSION:0:1} != "v" ]; then
				KUBERNETES_VERSION="v${KUBERNETES_VERSION}"
			fi
			shift 2
			;;
		-u|--kube-user)
			KUBERNETES_USER="$2"
			shift 2
			;;
		-p|--kube-password)
			KUBERNETES_PASSWORD="$2"
			shift 2
			;;
		--worker-nodes)
			WORKERNODES=$2
			shift 2
			;;
		# Same argument as cluster-autoscaler
		--grpc-provider)
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

	### LXD space
		--lxd-remote)
			LXD_REMOTE="$2"
			shift 2
			;;
		--lxd-profile)
			LXD_KUBERNETES_PROFILE="$2"
			shift 2
			;;
		--lxd-project)
			LXD_PROJECT="$2"
			shift 2
			;;

	### Bind9 space
		--use-named-server)
			USE_BIND9_SERVER=true
			shift 1
			;;
		--install-named-server)
			INSTALL_BIND9_SERVER=YES
			shift 1
			;;
		--named-server-host)
			BIND9_HOST=$2
			shift 2
			;;
		--named-server-port)
			BIND9_PORT=$2
			shift 2
			;;
		--named-server-key)
			BIND9_RNDCKEY=$2
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
		--add-route-private)
			NETWORK_PRIVATE_ROUTES+=($2)
			shift 2
			;;
		--add-route-public)
			NETWORK_PUBLIC_ROUTES+=($2)
			shift 2
			;;
		--net-address)
			IFS=/ read PRIVATE_IP PRIVATE_MASK_CIDR <<< "$2"
			shift 2
			;;
		--net-gateway)
			PRIVATE_GATEWAY="$2"
			shift 2
			;;
		--net-gateway-metric)
			PRIVATE_GATEWAY_METRIC="$2"
			shift 2
			;;
		--net-dns)
			PRIVATE_DNS="$2"
			shift 2
			;;
		--private-domain)
			PRIVATE_DOMAIN_NAME="$2"
			shift 2
			;;
		--dhcp-autoscaled-node)
			SCALEDNODES_DHCP=true
			shift 1
			;;
		--no-dhcp-autoscaled-node)
			SCALEDNODES_DHCP=false
			shift 1
			;;
		--public-address)
			IFS=/ read PUBLIC_IP PUBLIC_MASK_CIDR <<< "$2"
			PUBLIC_NETMASK=$(cidr_to_netmask ${PUBLIC_MASK_CIDR})
			shift 2
			;;
		--metallb-ip-range)
			METALLB_IP_RANGE="$2"
			shift 2
			;;
		--use-nlb)
			case $2 in
				none|keepalived|nginx|cloud)
					USE_NLB="$2"
					;;
				*)
					echo_red_bold "Load balancer of type: $2 is not supported"
					exit 1
					;;
			esac
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

	parsed_arguments
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function parsed_arguments() {
	VPC_PUBLIC_SUBNET_IDS=(${VC_NETWORK_PUBLIC})
	VPC_PRIVATE_SUBNET_IDS=(${VC_NETWORK_PRIVATE})

	if [ -z "$(lxc profile list ${LXD_REMOTE} --project ${LXD_PROJECT} --format=json | jq --arg LXD_KUBERNETES_PROFILE ${LXD_KUBERNETES_PROFILE} '.[]|select(.name == $LXD_KUBERNETES_PROFILE)|.name//""')" ]; then
		echo_blue_bold "Create LXD profile ${LXD_REMOTE}${LXD_KUBERNETES_PROFILE}"
		lxc profile create ${LXD_REMOTE}${LXD_KUBERNETES_PROFILE} --project ${LXD_PROJECT}
		curl -Ls https://raw.githubusercontent.com/ubuntu/microk8s/master/tests/lxc/microk8s.profile | lxc profile edit ${LXD_REMOTE}${LXD_KUBERNETES_PROFILE} --project ${LXD_PROJECT} 
	fi

	if [ -z "${PRIVATE_IP}" ]; then
		NETWORK_DEFS=$(lxc network list --format=json | jq -r --arg NAME ${VC_NETWORK_PRIVATE} '.[]|select(.name == $NAME)')

		CIDR=$(jq -r '.config."ipv4.address"//""' <<< "${NETWORK_DEFS}")
		IFS=/ read PRIVATE_IP PRIVATE_MASK_CIDR <<< "${CIDR}"
		PRIVATE_IP="${PRIVATE_IP%.*}.${PRIVATE_IP_START}"
		PRIVATE_NETMASK=$(cidr_to_netmask ${PRIVATE_MASK_CIDR})
		PRIVATE_DNS="${PRIVATE_IP%.*}.1"
	fi

	if [ -z "${PUBLIC_IP}" ] && [ -n "${VC_NETWORK_PUBLIC}" ]; then
		NETWORK_DEFS=$(lxc network list --format=json | jq -r --arg NAME ${VC_NETWORK_PUBLIC} '.[]|select(.name == $NAME)')

		CIDR=$(jq -r '.config."ipv4.address"//""' <<< "${NETWORK_DEFS}")
		IFS=/ read PUBLIC_IP PUBLIC_MASK_CIDR <<< "${CIDR}"
		PUBLIC_IP="${PUBLIC_IP%.*}.${PRIVATE_IP_START}"
		PUBLIC_NETMASK=$(cidr_to_netmask ${PUBLIC_MASK_CIDR})
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function determine_used_loadbalancers_on_network() {
	local NETWORK_NAME=$1
	local NLBTYPE=${USE_NLB}

	if [ "${USE_NLB}" == "cloud" ]; then
		NETWORK_TYPE=$(lxc network list --format=json | jq -r --arg NAME ${NETWORK_NAME} '.[]|select(.name == $NAME)' | jq -r '.type')

		if [ ${NETWORK_TYPE} = "ovn" ]; then
			echo_red_bold "Network: ${NETWORK_NAME} is an OVN network, NLB will use: ${NLBTYPE}" > /dev/stderr
		else
			if [ ${HA_CLUSTER} == "true" ]; then
				NLBTYPE=keepalived
			else
				NLBTYPE=nginx
			fi

			echo_red_bold "Network: ${NETWORK_NAME} is not an OVN network, NLB will use: ${NLBTYPE}" > /dev/stderr
		fi
	fi

	echo -n "${NLBTYPE}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function determine_used_loadbalancers() {
	if [ "${USE_NLB}" == "cloud" ]; then
		if [ ${EXPOSE_PUBLIC_CLUSTER} == "true" ] && [ -n "${VC_NETWORK_PUBLIC}" ]; then
			LXD_EXTERNAL_NLB=$(determine_used_loadbalancers_on_network ${VC_NETWORK_PUBLIC})
		fi

		LXD_INTERNAL_NLB=$(determine_used_loadbalancers_on_network ${VC_NETWORK_PRIVATE})

		if [ ${LXD_EXTERNAL_NLB} != "cloud" ]; then
			USE_NLB=${LXD_EXTERNAL_NLB}
			LXD_INTERNAL_NLB=none
			FIRSTNODE=0
		fi
	fi

}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_plateform() {
	find_private_dns_provider
	find_public_dns_provider
	prepare_node_indexes
	determine_used_loadbalancers
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_prepare_routes() {
	:
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_image_extras_args() {
	local EXTRAS=(
		"--lxd-project=${LXD_PROJECT}"
		"--lxd-profile=${LXD_KUBERNETES_PROFILE}"
		"--lxd-container-type=${LXD_CONTAINER_TYPE}"
		"--lxd-remote=${LXD_REMOTE}"
	)

	echo -n ${EXTRAS[@]}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function build_routes_lxd() {
	local OUTPUT=$1
	local ROUTES="[]"
	local ROUTE=

	shift

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
					TO=${VALUE:=}
					;;
				via)
					VIA=${VALUE:=}
					;;
				metric)
					METRIC=${VALUE:=500}
					;;
			esac
		done

		if [ -n "${TO}" ] && [ -n "${VIA}" ]; then
cat >> ${OUTPUT} <<EOF
      - type: route
        destination: '${TO}'
        gateway: '${VIA}'
        metric: ${METRIC}
EOF
		fi
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_create_vm() {
	local INDEX=$1
	local PUBLIC_IP=$2
	local NODE_IP=$3
	local MACHINE_TYPE=
	local MASTERKUBE_NODE=
	local MASTERKUBE_NODE_UUID=
	local IPADDR=
	local VMHOST=
	local VMTYPE=
	local DISK_SIZE=
	local NUM_VCPUS=
	local MEMSIZE=
	local SUFFIX=

	local RUNNING_PRIVATE_IP=
	local RUNNING_PUBLIC_IP=

	MACHINE_TYPE=$(get_machine_type ${INDEX})
	MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})
	SUFFIX=$(named_index_suffix $1)

	if [ -z "${MASTERKUBE_NODE_UUID}" ]; then

		read MEMSIZE NUM_VCPUS DISK_SIZE <<<"$(jq -r --arg MACHINE ${MACHINE_TYPE} '.[$MACHINE]|.memsize,.vcpus,.disksize' templates/setup/${PLATEFORM}/machines.json | tr '\n' ' ')"

		if [ -z "${MEMSIZE}" ] || [ -z "${NUM_VCPUS}" ] || [ -z "${DISK_SIZE}" ]; then
			echo_red_bold "MACHINE_TYPE=${MACHINE_TYPE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE} not correctly defined"
			exit 1
		fi

		cat > ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml << EOF
type: ${LXD_CONTAINER_TYPE}
profiles:
  - ${LXD_KUBERNETES_PROFILE}
devices:
  root:
    type: disk
    path: /
    pool: default
    size: ${DISK_SIZE}GiB
  ${PRIVATE_NET_INF}:
    type: nic
    network: ${VC_NETWORK_PRIVATE}
    ipv4.address: '${NODE_IP}'
EOF

		if [ -n ${PUBLIC_NET_INF} ] && [ ${PUBLIC_IP} != "NONE" ]; then
			cat >> ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml << EOF
  ${PUBLIC_NET_INF}:
    type: nic
    network: ${VC_NETWORK_PUBLIC}
EOF
			if [ "${PUBLIC_IP}" != "DHCP" ]; then
				echo "    ipv4.address: '${PUBLIC_IP}'" >> ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml
			fi
		fi

		cat >> ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml << EOF
config:
  limits.cpu: ${NUM_VCPUS}
  limits.memory: ${MEMSIZE}MiB
  cloud-init.network-config: |
    version: 1
    config:
      - type: physical
        name: '${PRIVATE_NET_INF}'
        subnets:
        - type: dhcp
EOF
		if [ ${#NETWORK_PRIVATE_ROUTES[@]} -gt 0 ]; then
			build_routes_lxd ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml ${NETWORK_PRIVATE_ROUTES[@]}
		fi

		if [ -n ${PUBLIC_NET_INF} ] && [ ${PUBLIC_IP} != "NONE" ]; then
			cat >> ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml << EOF
      - type: physical
        name: '${PUBLIC_NET_INF}'
        subnets:
        - type: dhcp
EOF

			if [ ${#NETWORK_PUBLIC_ROUTES[@]} -gt 0 ]; then
				build_routes_lxd ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml ${NETWORK_PUBLIC_ROUTES[@]}
			fi
		fi

		cat >> ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml << EOF
  cloud-init.user-data: |
    #cloud-config
    package_update: ${UPDATE_PACKAGE}
    package_upgrade: ${UPDATE_PACKAGE}
    timezone: ${TZ}
    runcmd:
    - echo "Create ${MASTERKUBE_NODE}" > /var/log/masterkube.log
    - hostnamectl set-hostname ${MASTERKUBE_NODE}
EOF

		if [ -f "${TARGET_CONFIG_LOCATION}/credential.yaml" ]; then
			cat >> ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml <<EOF
    write_files:
    - encoding: gzip+base64
      content: $(cat ${TARGET_CONFIG_LOCATION}/credential.yaml | gzip -c9 | base64 -w 0)
      owner: root:root
      path: ${IMAGE_CREDENTIALS_CONFIG}
      permissions: '0644'
EOF
		fi


		echo_line
		echo_blue_bold "Clone ${TARGET_IMAGE} to ${MASTERKUBE_NODE} TARGET_IMAGE=${TARGET_IMAGE} MASTERKUBE_NODE=${MASTERKUBE_NODE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE}M"
		echo_line

		# Clone my template
		echo_title "Launch ${MASTERKUBE_NODE}"

		lxc init ${LXD_REMOTE}${TARGET_IMAGE_UUID} ${LXD_REMOTE}${MASTERKUBE_NODE} \
			--project ${LXD_PROJECT} < ${TARGET_CONFIG_LOCATION}/config-${INDEX}.yaml
		lxc start ${LXD_REMOTE}${MASTERKUBE_NODE} --project ${LXD_PROJECT}
	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"
	fi

	while [ -z "${RUNNING_PRIVATE_IP}" ]; do
		local MASTERKUBE_INFOS=$(lxc list ${LXD_REMOTE} name=${MASTERKUBE_NODE} --project ${LXD_PROJECT} --format=json | jq -r  '.[0]')

		RUNNING_PRIVATE_IP=$(jq -r --arg PRIVATE_NET_INF ${PRIVATE_NET_INF} '.state.network|.[$PRIVATE_NET_INF].addresses[]|select(.family == "inet")|.address' <<< "${MASTERKUBE_INFOS}")
		RUNNING_PUBLIC_IP=$(jq -r --arg PUBLIC_NET_INF ${PUBLIC_NET_INF} '.state.network|.[$PUBLIC_NET_INF].addresses[]|select(.family == "inet")|.address' <<< "${MASTERKUBE_INFOS}")
		sleep 1
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_info_vm() {
	local INDEX=$1
	local PUBLIC_IP=$2
	local NODE_IP=$3
	local MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	local MASTERKUBE_INFOS=$(lxc list ${LXD_REMOTE} name=${MASTERKUBE_NODE} --project ${LXD_PROJECT} --format=json | jq -r  '.[0]')
	local MASTERKUBE_NODE_UUID=$(jq -r  '.config."volatile.uuid"//""' <<< "${MASTERKUBE_INFOS}")
	local SUFFIX=$(named_index_suffix $1)
	local PRIVATE_IP=$(jq -r --arg PRIVATE_NET_INF ${PRIVATE_NET_INF} '.state.network|.[$PRIVATE_NET_INF].addresses[]|select(.family == "inet")|.address' <<< "${MASTERKUBE_INFOS}")
	local PUBLIC_IP=$(jq -r --arg PUBLIC_NET_INF ${PUBLIC_NET_INF} '.state.network|.[$PUBLIC_NET_INF].addresses[]|select(.family == "inet")|.address' <<< "${MASTERKUBE_INFOS}")

    PRIVATE_ADDR_IPS[${INDEX}]=${PRIVATE_IP}
    PUBLIC_ADDR_IPS[${INDEX}]=${PUBLIC_IP}
    PRIVATE_DNS_NAMES[${INDEX}]=${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}

	cat > ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json <<EOF
{
	"Index": ${INDEX},
	"InstanceId": "${MASTERKUBE_NODE_UUID}",
	"PrivateIpAddress": "${PRIVATE_IP}",
	"PrivateDnsName": "${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}",
	"PublicIpAddress": "${PUBLIC_IP}",
	"PublicDnsName": "${MASTERKUBE_NODE}.${PUBLIC_DOMAIN_NAME}",
	"Tags": [
		{
			"Key": "Name",
			"Value": "${MASTERKUBE_NODE}"
		}
	]
}
EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_vm_by_name() {
    local VMNAME=$1

    if [ -n "$(lxc list ${LXD_REMOTE} name=${VMNAME} --project ${LXD_PROJECT} --format=json | jq -r  '.[0].name//""' 2>/dev/null)" ]; then
        echo_blue_bold "Delete VM: ${VMNAME}"
        lxc delete ${LXD_REMOTE}${VMNAME} --project ${LXD_PROJECT}  -f
	fi

    delete_host "${VMNAME}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_ovn_loadbalancer() {
	local NLB_NAME=$1
	local NLB_NETWORK_NAME=$2

	LISTEN_ADDR=$(lxc network load-balancer list ${LXD_REMOTE}${NLB_NETWORK_NAME} --project ${LXD_PROJECT} --format json | jq -r --arg NAME ${NLB_NETWORK_NAME} '.[]|select(.config."user.name" == $NAME)|.listen_address')

	if [ -n ${LISTEN_ADDR} ]; then
		lxc network load-balancer delete ${LXD_REMOTE}${NLB_NETWORK_NAME} ${LISTEN_ADDR} --project ${LXD_PROJECT}
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_load_balancers() {
	if [ "${LXD_INTERNAL_NLB}" == "cloud" ]; then
		delete_ovn_loadbalancer "nlb-${MASTERKUBE}" "${VC_NETWORK_PRIVATE}"
	fi

	if [ "${LXD_EXTERNAL_NLB}" == "cloud" ]; then
		delete_ovn_loadbalancer "nlb-${MASTERKUBE}" "${VC_NETWORK_PUBLIC}"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function update_build_env() {
	save_buildenv
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function update_provider_config() {
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vmuuid() {
	lxc list ${LXD_REMOTE} name=$1 --project ${LXD_PROJECT} --format=json | jq -r  '.[0].config."volatile.uuid"//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_image_uuid() {
    lxc image list ${LXD_REMOTE} name=${TARGET_IMAGE} --project ${LXD_PROJECT} --format=json | jq -r --arg TARGET_IMAGE "${TARGET_IMAGE}" '.[0].fingerprint//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_net_type() {
    echo -n "custom"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_ovn_loadbalancer() {
	local NLB_NAME=$1
	local NLB_NETWORK_NAME=$2
	local NLB_TARGET_PORTS=$3
	local NLB_TARGETS_IP="$4"
	local NLB_VIP_ADDRESS="$5"
	local NLB_PORTS=

	if [ -z "${NLB_VIP_ADDRESS}" ] || [ "${NLB_VIP_ADDRESS}" == "DHCP" ] || [ "${NLB_VIP_ADDRESS}" == "NONE" ]; then
		NLB_VIP_ADDRESS="--allocate=ipv4"
	fi

	NLB_VIP_ADDRESS=$(lxc network load-balancer create ${NLB_NETWORK_NAME} ${NLB_VIP_ADDRESS} user.name=${NLB_NAME} | cut -d ' ' -f 4)

	if [ -n "${NLB_VIP_ADDRESS}" ]; then
		for NLB_TARGET_IP in ${NLB_TARGETS_IP}
		do
			lxc network load-balancer backend add ${NLB_NETWORK_NAME} ${NLB_VIP_ADDRESS} "${NLB_NAME}-${NLB_TARGET_IP}" ${NLB_TARGET_IP} ${NLB_TARGET_PORTS}
			lxc network load-balancer port add ${NLB_NETWORK_NAME} ${NLB_VIP_ADDRESS} tcp ${NLB_TARGET_PORTS} "${NLB_NAME}-${NLB_TARGET_IP}"
		done
	else
		echo_red_bold "Unable to create ovn load balancer"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_plateform_nlb() {
	local NLB_TARGETS_IP=()
    local PUBLIC_NLB_DNS=${PUBLIC_ADDR_IPS[0]:=DHCP}
    local PRIVATE_NLB_DNS=
	local INDEX=
	local LISTEN_PORTS=
	local SUFFIX=

	if [ "${LXD_INTERNAL_NLB}" != "none" ]; then
		PRIVATE_NLB_DNS=${PRIVATE_ADDR_IPS[0]}
	else
		PRIVATE_NLB_DNS=${PRIVATE_ADDR_IPS[1]}
	fi

	LOAD_BALANCER_IP=${PRIVATE_NLB_DNS}

	for INDEX in $(seq ${CONTROLNODE_INDEX} $((CONTROLNODE_INDEX + ${CONTROLNODES} - 1)))
	do
		SUFFIX=$(named_index_suffix $INDEX)
		NLB_TARGETS_IP+=($(jq -r '.PublicIpAddress//""' ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json))
	done

	if [ "${LXD_EXTERNAL_NLB}" != "none" ]; then		
		echo_title "Create external NLB ${MASTERKUBE} with target: ${NLB_INSTANCE_IDS} at: ${PUBLIC_NLB_DNS}"

		if [ ${LXD_EXTERNAL_NLB} == "cloud" ]; then
			if [ ${CONTROLPLANE_USE_PUBLICIP} == "true" ]; then
				PUBLIC_NLB_DNS=$(create_ovn_loadbalancer "nlb-${MASTERKUBE}" "${VC_NETWORK_PUBLIC}" "${LOAD_BALANCER_PORT}" "${NLB_TARGETS_IP}" "${PUBLIC_NLB_DNS}")
			else
				PUBLIC_NLB_DNS=$(create_ovn_loadbalancer "nlb-${MASTERKUBE}" "${VC_NETWORK_PUBLIC}" "${EXPOSE_PUBLIC_PORTS}" "${NLB_TARGETS_IP}" "${PUBLIC_NLB_DNS}")
			fi
		else
			create_nginx_gateway
		fi
	else
		PUBLIC_NLB_DNS=${PRIVATE_NLB_DNS}
	fi

	if [ "${LXD_INTERNAL_NLB}" != "none" ]; then
		echo_title "Create internal NLB ${MASTERKUBE} with target: ${NLB_INSTANCE_IDS} at: ${PRIVATE_NLB_DNS}"

		LOAD_BALANCER_IP=${PRIVATE_NLB_DNS}

		if [ "${LXD_INTERNAL_NLB}" == "cloud" ]; then
			create_ovn_loadbalancer "nlb-${MASTERKUBE}" "${VC_NETWORK_PRIVATE}" "${LOAD_BALANCER_PORT}" "${NLB_INSTANCE_IDS}" "${PRIVATE_NLB_DNS}"
		else
			create_keepalived
		fi
	fi

	register_nlb_dns A "${PRIVATE_NLB_DNS}" "${PUBLIC_NLB_DNS}" "" ""
}