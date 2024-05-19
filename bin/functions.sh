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
--create-nginx-apigateway                        # Create NGINX instance to install an apigateway, default ${USE_NGINX_GATEWAY}
--use-cloud-init                                 # Use cloud-init to configure autoscaled nodes instead off ssh, default ${USE_CLOUDINIT_TO_CONFIGURE}

### Design domain

--public-domain=<value>                          # Specify the public domain to use, default ${PUBLIC_DOMAIN_NAME}
--private-domain=<value>                         # Specify the private domain to use, default ${PRIVATE_DOMAIN_NAME}
--dashboard-hostname=<value>                     # Specify the hostname for kubernetes dashboard, default ${DASHBOARD_HOSTNAME}
--external-dns-provider=<aws|godaddy|designate>  # Specify external dns provider.

### Cert Manager

--cert-email=<value>                             # Specify the mail for lets encrypt, default ${CERT_EMAIL}
--use-zerossl                                    # Specify cert-manager to use zerossl, default ${USE_ZEROSSL}
--use-self-signed-ca                             # Specify if use self-signed CA, default ${CERT_SELFSIGNED_FORCED}
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
--scale-down-utilization-threshold=<value>       # autoscaler flag, default: ${SCALEDOWNUTILIZATIONTHRESHOLD}
--scale-down-gpu-utilization-threshold=<value>   # autoscaler flag, default: ${SCALEDOWNGPUUTILIZATIONTHRESHOLD}
--scale-down-delay-after-add=<value>             # autoscaler flag, default: ${SCALEDOWNDELAYAFTERADD}
--scale-down-delay-after-delete=<value>          # autoscaler flag, default: ${SCALEDOWNDELAYAFTERDELETE}
--scale-down-delay-after-failure=<value>         # autoscaler flag, default: ${SCALEDOWNDELAYAFTERFAILURE}
--scale-down-unneeded-time=<value>               # autoscaler flag, default: ${SCALEDOWNUNEEDEDTIME}
--scale-down-unready-time=<value>                # autoscaler flag, default: ${SCALEDOWNUNREADYTIME}
--max-node-provision-time=<value>                # autoscaler flag, default: ${MAXNODEPROVISIONTIME}
--unremovable-node-recheck-timeout=<value>       # autoscaler flag, default: ${UNREMOVABLENODERECHECKTIMEOUT}

EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function usage() {
	common_usage
	cat <<EOF
### Flags ${PLATEFORM} plateform specific

  # Flags to configure nfs client provisionner
--nfs-server-adress                            # The NFS server address, default ${NFS_SERVER_ADDRESS}
--nfs-server-mount                             # The NFS server mount path, default ${NFS_SERVER_PATH}
--nfs-storage-class                            # The storage class name to use, default ${NFS_STORAGE_CLASS}

  # Flags to set the template vm
--seed-image=<value>                           # Override the seed image name used to create template, default ${SEED_IMAGE}
--kubernetes-user=<value>                      # Override the seed user in template, default ${KUBERNETES_USER}
--kubernetes-password | -p=<value>             # Override the password to ssh the cluster VM, default random word

  # Flags in ha mode only
--use-keepalived | -u                          # Use keepalived as load balancer else NGINX is used  # Flags to configure nfs client provisionner

  # Flags to configure network in ${PLATEFORM}
--vm-private-network=<value>                   # Override the name of the private network in ${PLATEFORM}, default ${VC_NETWORK_PRIVATE}
--vm-public-network=<value>                    # Override the name of the public network in ${PLATEFORM}, empty for none second interface, default ${VC_NETWORK_PUBLIC}
--no-dhcp-autoscaled-node                      # Autoscaled node don't use DHCP, default ${SCALEDNODES_DHCP}
--dhcp-autoscaled-node                         # Autoscaled node use DHCP, default ${SCALEDNODES_DHCP}
--private-domain=<value>                       # Override the domain name, default ${PRIVATE_DOMAIN_NAME}
--net-address=<value>                          # Override the IP of the kubernetes control plane node, default ${PRIVATE_IP}
--net-gateway=<value>                          # Override the IP gateway, default ${PRIVATE_GATEWAY}
--net-dns=<value>                              # Override the IP DNS, default ${PRIVATE_DNS}

--public-address=<value>                       # The public address to expose kubernetes endpoint[ipv4/cidr, DHCP, NONE], default ${PUBLIC_IP}
--metallb-ip-range                             # Override the metalb ip range, default ${METALLB_IP_RANGE}
--dont-use-dhcp-routes-private                 # Tell if we don't use DHCP routes in private network, default ${USE_DHCP_ROUTES_PRIVATE}
--dont-use-dhcp-routes-public                  # Tell if we don't use DHCP routes in public network, default ${USE_DHCP_ROUTES_PUBLIC}
--add-route-private                            # Add route to private network syntax is --add-route-private=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-private=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default ${NETWORK_PRIVATE_ROUTES[@]}
--add-route-public                             # Add route to public network syntax is --add-route-public=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-public=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default ${NETWORK_PUBLIC_ROUTES[@]}

EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function parse_arguments() {
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
		"private-domain:"
		"no-dhcp-autoscaled-node"
		"dhcp-autoscaled-node"
		"public-address:"
		"metallb-ip-range:"
		"use-keepalived"
		"use-named-server"
		"install-named-server"
		"named-server-host:"
		"named-server-port:"
		"named-server-key:"
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
			DISTRO=$2
			SEED_IMAGE="${DISTRO}-server-cloudimg-seed"
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
			CERT_SELFSIGNED_FORCED=YES
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
        --create-nginx-apigateway)
            USE_NGINX_GATEWAY=YES
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
		-k|--kubernetes-version)
			KUBERNETES_VERSION="$2"
			if [ ${KUBERNETES_VERSION:0:1} != "v" ]; then
				KUBERNETES_VERSION="v${KUBERNETES_VERSION}"
			fi
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
			PRIVATE_IP="$2"
			shift 2
			;;
		--net-gateway)
			PRIVATE_GATEWAY="$2"
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

	VPC_PUBLIC_SUBNET_IDS=(${VC_NETWORK_PUBLIC})
	VPC_PRIVATE_SUBNET_IDS=(${VC_NETWORK_PRIVATE})
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
	local NLB_IP=$1
	local CLUSTER_NODES=$2
	local CERT_EXTRA_SANS=$3

	local LB_IP=
	local CERT_EXTRA=
	local CLUSTER_NODE=
	local CLUSTER_IP=
	local CLUSTER_HOST=
	local TLS_SNA=(
		"${NLB_IP}"
	)

	IFS=, read -a CLUSTER_NODES <<< "${CLUSTER_NODES}"
	IFS=, read -a CERT_EXTRA_SANS <<< "${CERT_EXTRA_SANS}"

	for CERT_EXTRA in ${CERT_EXTRA_SANS[@]}
	do
		if [[ ! ${TLS_SNA[@]} =~ "${CERT_EXTRA}" ]]; then
			TLS_SNA+=("${CERT_EXTRA}")
		fi
	done

	for CLUSTER_NODE in ${CLUSTER_NODES[@]}
	do
		IFS=: read CLUSTER_HOST CLUSTER_IP <<< "${CLUSTER_NODE}"

		if [ -n ${CLUSTER_IP} ] && [[ ! ${TLS_SNA[@]} =~ "${CLUSTER_IP}" ]]; then
			TLS_SNA+=("${CLUSTER_IP}")
		fi

		if [ -n "${CLUSTER_HOST}" ]; then
			if [[ ! ${TLS_SNA[@]} =~ "${CLUSTER_HOST}" ]]; then
				TLS_SNA+=("${CLUSTER_HOST}")
				TLS_SNA+=("${CLUSTER_HOST%%.*}")
			fi
		fi
	done

	for INDEX in $(seq ${CONTROLNODE_INDEX} $((CONTROLNODE_INDEX + ${CONTROLNODES})))
	do
		local PRIVATEDNS=${PRIVATE_DNS_NAMES[${INDEX}]:-}

		if [ -n "${PRIVATEDNS}" ]; then
			if [[ ! ${TLS_SNA[@]} =~ "${PRIVATEDNS}" ]]; then
				TLS_SNA+=("${CLUSTER_HOST}")
			fi
		fi
	done

	echo -n "${TLS_SNA[@]}" | tr ' ' ','
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_ssh_ip() {
	local INDEX=$1

	if [ ${PREFER_SSH_PUBLICIP} = "NO" ] || [ -z "${PUBLIC_ADDR_IPS[${INDEX}]}" ]; then
		echo -n ${PRIVATE_ADDR_IPS[${INDEX}]}
	else
		echo -n ${PUBLIC_ADDR_IPS[${INDEX}]}
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_machine_type() {
	local NODEINDEX=$1
	local MACHINE_TYPE=

	if [ ${NODEINDEX} -lt ${CONTROLNODE_INDEX} ]; then
		MACHINE_TYPE=${NGINX_MACHINE}
	elif [ ${NODEINDEX} -lt ${WORKERNODE_INDEX} ]; then
		MACHINE_TYPE=${WORKER_NODE_MACHINE}
	else
		MACHINE_TYPE=${CONTROL_PLANE_MACHINE}
	fi

	echo -n ${MACHINE_TYPE}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function named_index_suffix() {
	local INDEX=$1

	local SUFFIX="0${INDEX}"

	echo ${SUFFIX:(-2)}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_node_index() {
	local NODEINDEX=$1

	if [ ${NODEINDEX} -ge ${CONTROLNODE_INDEX} ]; then
		if [[ ${NODEINDEX} -lt ${WORKERNODE_INDEX} ]]; then
			NODEINDEX=$((NODEINDEX - ${CONTROLNODE_INDEX} + 1))
		else
			NODEINDEX=$((NODEINDEX - ${WORKERNODE_INDEX} + 1))
		fi
	fi

	echo -n ${NODEINDEX}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vm_name() {
	local INDEX=$1
	local NODEINDEX=$(get_node_index ${INDEX})

	if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
		if [ ${HA_CLUSTER} = "true" ]; then
			if [ ${USE_NLB} = "YES" ] && [ "${USE_NGINX_GATEWAY}" = "YES" ]; then
				if [ ${CONTROLNODE_INDEX} -gt 1 ]; then
					MASTERKUBE_NODE="${NODEGROUP_NAME}-gateway-$(named_index_suffix $NODEINDEX)"
				else
					MASTERKUBE_NODE="${NODEGROUP_NAME}-gateway"
				fi
			else
				if [ ${CONTROLNODE_INDEX} -gt 1 ]; then
					MASTERKUBE_NODE="${MASTERKUBE}-$(named_index_suffix $NODEINDEX)"
				else
					MASTERKUBE_NODE="${MASTERKUBE}"
				fi
			fi
		else
			MASTERKUBE_NODE="${MASTERKUBE}"
		fi
	elif [[ ${INDEX} -lt ${WORKERNODE_INDEX} ]]; then
		if [ ${HA_CLUSTER} = "false" ] && [ ${INDEX} -eq ${CONTROLNODE_INDEX} ]; then
			MASTERKUBE_NODE="${MASTERKUBE}"
		else
			MASTERKUBE_NODE="${NODEGROUP_NAME}-master-$(named_index_suffix $NODEINDEX)"
		fi
	else
		MASTERKUBE_NODE="${NODEGROUP_NAME}-worker-$(named_index_suffix $NODEINDEX)"
	fi

	echo -n ${MASTERKUBE_NODE}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_info_vm() {
	local INDEX=$1
	local NAME=$(get_vm_name $1)
	local SUFFIX=$(named_index_suffix $1)
	local DNSNAME=${NAME}.${PRIVATE_DOMAIN_NAME}
	local PRIVATE_IP=${PRIVATE_ADDR_IPS[${INDEX}]}
	local PUBLIC_IP=${PUBLIC_ADDR_IPS[${INDEX}]}

	PRIVATE_DNS_NAMES[${INDEX}]=${DNSNAME}

	if [ "${PUBLIC_IP}" == "DHCP" ] || [ "${PUBLIC_IP}" == "NONE" ] || [ -z "${PUBLIC_IP}" ]; then
		PUBLIC_IP=${PRIVATE_IP}
	fi

	local INSTANCE=$(cat <<EOF
{
	"Index": ${INDEX},
	"InstanceId": "$(get_vmuuid ${NAME})",
	"PrivateIpAddress": "${PRIVATE_IP}",
	"PrivateDnsName": "${DNSNAME}",
	"PublicIpAddress": "${PUBLIC_IP}",
	"PublicDnsName": "${DNSNAME}",
	"Tags": [
		{
			"Key": "Name",
			"Value": "${NAME}"
		}
	]
}
EOF
)
	echo "${INSTANCE}" | jq . > ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function register_dns() {
    local INDEX=$1
    local IPADDR=$2
    local NAME=$3
	local SUFFIX=$(named_index_suffix ${INDEX})
	local RECORDTYPE=A

	if [ "${USE_ETC_HOSTS}" = "true" ] || [ ${INSTALL_BIND9_SERVER} = "YES" ]; then
		delete_host ${NAME}
		add_host ${IPADDR} ${NAME} ${NAME}.${PRIVATE_DOMAIN_NAME}
	fi

    if [ -n "${AWS_ROUTE53_PRIVATE_ZONE_ID}" ]; then
		echo_blue_bold "Register ${NAME} address: ${IPADDR} into Route53 dns zone ${AWS_ROUTE53_PRIVATE_ZONE_ID}"

		# Record kubernetes node in Route53 DNS
        cat > ${TARGET_CONFIG_LOCATION}/route53-private-${SUFFIX}.json <<EOF
{
	"Comment": "${NAME} private DNS entry",
	"Changes": [
		{
			"Action": "UPSERT",
			"ResourceRecordSet": {
				"Name": "${NAME}.${PRIVATE_DOMAIN_NAME}",
				"Type": "${RECORDTYPE}",
				"TTL": 60,
				"ResourceRecords": [
					{
						"Value": "${IPADDR}"
					}
				]
			}
		}
	]
}
EOF

        aws route53 change-resource-record-sets \
            --profile ${AWS_ROUTE53_PROFILE} \
            --hosted-zone-id ${AWS_ROUTE53_PRIVATE_ZONE_ID} \
            --change-batch file://${TARGET_CONFIG_LOCATION}/route53-private-${SUFFIX}.json > /dev/null

	elif [ -n "${OS_PRIVATE_DNS_ZONEID}" ]; then
		echo_blue_bold "Register with designate ${NAME} address: ${IPADDR} into private dns zone ${PRIVATE_DOMAIN_NAME} id: ${OS_PRIVATE_DNS_ZONEID}"
		
		DNS_ENTRY=$(openstack recordset create -f json --ttl 60 --type ${RECORDTYPE} --record ${IPADDR} "${PRIVATE_DOMAIN_NAME}." ${NAME} 2>/dev/null | jq -r '.id // ""')
		
		cat > ${TARGET_CONFIG_LOCATION}/designate-private-${SUFFIX}.json <<EOF
		{
			"id": "${DNS_ENTRY}",
			"zone_id": "${OS_PRIVATE_DNS_ZONEID}",
			"name": "${NAME}",
			"record": "${IPADDR}"
		}
EOF
	elif [ "${USE_BIND9_SERVER}" = "true" ]; then
		echo_blue_bold "Register with bind9 ${NAME} address: ${IPADDR} into private dns zone ${PRIVATE_DOMAIN_NAME}"

		cat > ${TARGET_CONFIG_LOCATION}/rfc2136-private-${SUFFIX}.cmd <<EOF
server ${BIND9_HOST} ${BIND9_PORT}
update add ${NAME}.${PRIVATE_DOMAIN_NAME} 60 ${RECORDTYPE} ${IPADDR}
send
EOF

		cat ${TARGET_CONFIG_LOCATION}/rfc2136-private-${SUFFIX}.cmd | nsupdate -k ${BIND9_RNDCKEY}

    # Register node in public zone DNS if we don't use private DNS
    elif [ "${EXTERNAL_DNS_PROVIDER}" = "aws" ]; then
		echo_blue_bold "Register ${NAME} address: ${IPADDR} into public Route33 dns zone ${PUBLIC_DOMAIN_NAME}"
		cat > ${TARGET_CONFIG_LOCATION}/route53-public-${SUFFIX}.cmd <<EOF
{
	"Comment": "${NAME} private DNS entry",
	"Changes": [
		{
			"Action": "UPSERT",
			"ResourceRecordSet": {
				"Name": "${NAME}.${PUBLIC_DOMAIN_NAME}",
				"Type": "${RECORDTYPE}",
				"TTL": 60,
				"ResourceRecords": [
					{
						"Value": "${IPADDR}"
					}
				]
			}
		}
	]
}
EOF

		# Register kubernetes nodes in route53
		aws route53 change-resource-record-sets \
			--profile ${AWS_ROUTE53_PROFILE} \
			--hosted-zone-id ${AWS_ROUTE53_PUBLIC_ZONE_ID} \
			--change-batch file://${TARGET_CONFIG_LOCATION}/route53-public-${SUFFIX}.json > /dev/null

	elif [ "${EXTERNAL_DNS_PROVIDER}" = "godaddy" ]; then

		# Register kubernetes nodes in godaddy if we don't use route53
		curl -s -X PUT "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/${RECORDTYPE}/${NAME}" \
			-H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
			-H "Content-Type: application/json" -d "[{\"data\": \"${IPADDR}\"}]"

		cat > ${TARGET_CONFIG_LOCATION}/godaddy-public-${SUFFIX}.json <<EOF
		{
			"zone": "${PUBLIC_DOMAIN_NAME}",
			"type": "${RECORDTYPE}",
			"name": "${NAME}",
			"record": [ "${IPADDR}" ]
		}
EOF

	elif [ "${EXTERNAL_DNS_PROVIDER}" = "designate" ]; then

		# Register in designate IP addresses point in public IP
		DNS_ENTRY=$(openstack recordset create -f json --ttl 60 --type ${RECORDTYPE} --record ${IPADDR} "${PUBLIC_DOMAIN_NAME}." ${NAME} 2>/dev/null | jq -r '.id // ""')

		cat > ${TARGET_CONFIG_LOCATION}/designate-public-${SUFFIX}.json <<EOF
		{
			"id": "${DNS_ENTRY}",
			"zone_id": "${OS_PUBLIC_DNS_ZONEID}",
			"name": "${NAME}",
			"record": "${IPADDR}"
		}
EOF
	elif [ "${EXTERNAL_DNS_PROVIDER}" = "rfc2136" ]; then
		cat > ${TARGET_CONFIG_LOCATION}/rfc2136-public-${SUFFIX}.cmd <<EOF
server ${BIND9_HOST} ${BIND9_PORT}
update add ${NAME}.${PUBLIC_DOMAIN_NAME} 60 ${RECORDTYPE} ${IPADDR}"
send
EOF

		cat ${TARGET_CONFIG_LOCATION}/rfc2136-public-${SUFFIX}.cmd | nsupdate -k ${BIND9_RNDCKEY}
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_named_server() {
	local INDEX=$1
	local IPADDR=$2
	local NAME=$3
	local ZONES=("--zone-name=${PRIVATE_DOMAIN_NAME}")

	if [ ${EXTERNAL_DNS_PROVIDER} = "rfc2136" ]; then
		ZONES+=("--zone-name=${PUBLIC_DOMAIN_NAME}")
	fi

	echo_blue_bold "Install named server on ${NAME}, ${IPADDR}"
	
	eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo /usr/local/bin/install-bind9.sh --user ${KUBERNETES_USER} --master-dns ${PRIVATE_DNS} ${ZONES[@]} ${SILENT}
	eval scp ${SCP_OPTIONS} ${KUBERNETES_USER}@${IPADDR}:/home/${KUBERNETES_USER}/rndc.key ${TARGET_CLUSTER_LOCATION} ${SILENT}

	PRIVATE_DNS=${IPADDR}
	BIND9_HOST=${IPADDR}
	BIND9_RNDCKEY=${TARGET_CLUSTER_LOCATION}/rndc.key
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_vm() {
	local INDEX=$1
	local NAME=$(get_vm_name ${INDEX})

	plateform_create_vm $@
	plateform_info_vm ${INDEX}

	if [ "${INSTALL_BIND9_SERVER}" == "YES" ] && [ ${INDEX} -eq ${FIRSTNODE} ]; then
		create_named_server ${INDEX} ${PRIVATE_ADDR_IPS[${INDEX}]} ${NAME}
	fi

	register_dns ${INDEX} ${PRIVATE_ADDR_IPS[${INDEX}]} ${NAME}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_nlb_ready() {
	echo_blue_dot_title "Wait for ELB start on IP: ${CONTROL_PLANE_ENDPOINT}:${APISERVER_ADVERTISE_PORT}"

	while :
	do
		echo_blue_dot
		curl -s -k --connect-timeout 1 "https://${CONTROL_PLANE_ENDPOINT}:${APISERVER_ADVERTISE_PORT}" &> /dev/null && break
		sleep 1
	done
	echo

	echo_line

	echo -n ${CONTROL_PLANE_ENDPOINT}:${APISERVER_ADVERTISE_PORT} > ${TARGET_CLUSTER_LOCATION}/manager-ip
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_node_indexes() {
	if [ "${HA_CLUSTER}" = "true" ]; then
		CONTROLNODES=3
		CONTROLNODE_INDEX=1

		if [ ${USE_KEEPALIVED} = "YES" ]; then
			FIRSTNODE=1
		elif [ "${USE_NLB}" = "YES" ]; then
			if [ "${USE_NGINX_GATEWAY}" = "YES" ]; then
				if [ $PLATEFORM == "aws" ]; then
					CONTROLNODE_INDEX=${#VPC_PUBLIC_SUBNET_IDS[@]}
				fi
			else
				FIRSTNODE=1
			fi
		else
			CONTROLNODE_INDEX=${#VPC_PUBLIC_SUBNET_IDS[@]}
		fi

	else
		CONTROLNODES=1
		CONTROLNODE_INDEX=0
		EXTERNAL_ETCD=false
		USE_KEEPALIVED=NO

		if [ "${EXPOSE_PUBLIC_CLUSTER}" != "${CONTROLPLANE_USE_PUBLICIP}" ]; then
			if [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
				CONTROLNODE_INDEX=1

				if [ ${USE_NLB} = "YES" ]; then
					if [ "${USE_NGINX_GATEWAY}" != "YES" ]; then
						FIRSTNODE=1
					fi
				fi
			fi
		fi
	fi

	WORKERNODE_INDEX=$((CONTROLNODE_INDEX + ${CONTROLNODES}))
	LASTNODE_INDEX=$((WORKERNODE_INDEX + ${WORKERNODES} - 1))
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_environment() {
	
	if [ -z "${NODEGROUP_NAME}" ]; then
		NODEGROUP_NAME=${PLATEFORM}-${DEPLOY_MODE}-${KUBERNETES_DISTRO}
	fi

	TARGET_CONFIG_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/config
	TARGET_DEPLOY_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/deployment
	TARGET_CLUSTER_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/cluster
	MASTERKUBE="${NODEGROUP_NAME}-masterkube"
	DASHBOARD_HOSTNAME=${NODEGROUP_NAME}-dashboard

	NODE_IP=${PRIVATE_IP}
	
    [ -z "${AWS_ROUTE53_PROFILE}" ] && AWS_ROUTE53_PROFILE=${AWS_PROFILE}
    [ -z "${AWS_ROUTE53_ACCESSKEY}" ] && AWS_ROUTE53_ACCESSKEY=${AWS_ACCESSKEY}
    [ -z "${AWS_ROUTE53_SECRETKEY}" ] && AWS_ROUTE53_SECRETKEY=${AWS_SECRETKEY}
    [ -z "${AWS_ROUTE53_TOKEN}" ] && AWS_ROUTE53_TOKEN=${AWS_TOKEN}

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

	if [ ${HA_CLUSTER} = "false" ]; then
		if [ "${USE_NGINX_GATEWAY}" = "NO" ] && [ "${CONTROLPLANE_USE_PUBLICIP}" = "false" ] && [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
			echo_red_bold "Single plane cluster can not be exposed to internet because because control plane require public IP or require NGINX gateway in front"
			exit
		fi
	elif [ ${PLATEFORM} != "aws" ] && [ ${PLATEFORM} != "openstack" ]; then
		USE_NLB=NO
	fi

	if [ "${CONTROLPLANE_USE_PUBLICIP}" = "true" ]; then
		PREFER_SSH_PUBLICIP=NO

		if [ "${USE_NGINX_GATEWAY}" = "YES" ] || [ "${USE_NLB}" = "YES" ] || [ "${EXPOSE_PUBLIC_CLUSTER}" = "false" ]; then
			echo_red_bold "Control plane can not have public IP because nginx gatewaway or NLB is required or cluster is not exposed to internet"
			exit 1
		fi

	elif [ "${WORKERNODE_USE_PUBLICIP}" = "true" ]; then
		echo_red_bold "Worker node can not have a public IP when control plane does not have public IP"
		exit 1
	fi

	if [ "${CONTROLPLANE_USE_PUBLICIP}" == "true" ] || [ ${WORKERNODE_USE_PUBLICIP} == "true" ]; then
		if [ "${VC_NETWORK_PUBLIC}" == "NONE" ] || [ -z "${VC_NETWORK_PUBLIC}" ]; then
			echo_red_bold "nodes with floating-ip require public network"
			exit 1
		fi
	fi

	if [ "${KUBERNETES_DISTRO}" == "microk8s" ]; then
		APISERVER_ADVERTISE_PORT=16443

		# microk8s can't join thru tcp load balancer
#		if [ "${HA_CLUSTER}" = "true" ]; then
#			USE_KEEPALIVED=YES
#			USE_NLB=NO
#			USE_NGINX_GATEWAY=NO
#		fi
	fi

	if [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
		LOAD_BALANCER_PORT="80,443,${APISERVER_ADVERTISE_PORT},9345"
		EXTERNAL_ETCD=false
	elif [ "${KUBERNETES_DISTRO}" == "microk8s" ]; then
		LOAD_BALANCER_PORT="80,443,${APISERVER_ADVERTISE_PORT},25000"
	else
		LOAD_BALANCER_PORT="80,443,${APISERVER_ADVERTISE_PORT}"
	fi

	if [ "${USE_NLB}" = "YES" ] || [ "${USE_KEEPALIVED}" = "YES" ]; then
		USE_LOADBALANCER=true
	fi

	SSH_KEY_FNAME="$(basename ${SSH_PRIVATE_KEY})"
	SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"
	SSH_KEY=$(cat "${SSH_PUBLIC_KEY}")

	TARGET_CONFIG_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/config
	TARGET_DEPLOY_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/deployment
	TARGET_CLUSTER_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/cluster

	if [ "${EXTERNAL_ETCD}" = "true" ]; then
		EXTERNAL_ETCD_ARGS="--use-external-etcd"
		ETCD_DST_DIR="/etc/etcd/ssl"
	else
		EXTERNAL_ETCD_ARGS="--no-use-external-etcd"
		ETCD_DST_DIR="/etc/kubernetes/pki/etcd"
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
		TARGET_IMAGE="${DISTRO}-kubernetes-${CNI_PLUGIN}-${KUBERNETES_VERSION}-${CONTAINER_ENGINE}-${SEED_ARCH}"
	else
		TARGET_IMAGE="${DISTRO}-kubernetes-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}"
	fi

	if [ ${PLATEFORM} == "multipass" ]; then
		TARGET_IMAGE="${PWD}/images/${TARGET_IMAGE}.img"
	elif [ ${PLATEFORM} == "aws" ]; then
		TARGET_IMAGE="$(echo -n ${TARGET_IMAGE} | tr '+' '_')"
	fi

	if [ ${WORKERNODES} -eq 0 ]; then
		MASTER_NODE_ALLOW_DEPLOYMENT=YES
	else
		MASTER_NODE_ALLOW_DEPLOYMENT=NO
	fi

	if [ ${INSTALL_BIND9_SERVER} = "YES" ]; then
		USE_BIND9_SERVER=true
	elif [ ${USE_BIND9_SERVER} = "true" ]; then
		if [ -z "${BIND9_HOST}" ]; then
			echo_red_bold "BIND9_HOST is not defined"
			exit 1
		fi

		if [ -z "${BIND9_RNDCKEY}" ] || [ ! -f ${BIND9_RNDCKEY} ]; then
			echo_red_bold "BIND9_RNDCKEY is not defined or not exists"
			exit 1
		fi
	fi

	if [ -z "${CERT_EMAIL}" ]; then
		if [ -n ${PUBLIC_DOMAIN_NAME} ]; then
			CERT_EMAIL=${USER}@${PUBLIC_DOMAIN_NAME}
		else
			CERT_EMAIL=${USER}@${PRIVATE_DOMAIN_NAME}
		fi
	fi

	prepare_node_indexes
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_transport() {
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
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_ssh() {
echo -n
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_kubernetes_distribution() {
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
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_previous_masterkube() {
	# Delete previous existing version
	if [ "${RESUME}" = "NO" ] && [ "${UPGRADE_CLUSTER}" == "NO" ]; then
		delete-masterkube.sh \
			--plateform=${PLATEFORM} \
			--configuration-location=${CONFIGURATION_LOCATION} \
			--defs=${PLATEFORMDEFS} \
			--node-group=${NODEGROUP_NAME}

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
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function zoneid_by_name() {
	local DOMAINNAME=$1

	if [ -n "${AWS_ROUTE53_PROFILE}" ]; then
		aws route53 list-hosted-zones-by-name --profile ${AWS_ROUTE53_PROFILE} --dns-name ${DOMAINNAME} \
			| jq --arg DNSNAME "${DOMAINNAME}." -r '.HostedZones[]|select(.Name == $DNSNAME)|.Id//""' \
			| sed -E 's/\/hostedzone\/(\w+)/\1/'
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function find_public_dns_provider() {
	if [ -n "${PUBLIC_DOMAIN_NAME}" ]; then
		# Check if aws is candidate
		AWS_ROUTE53_PUBLIC_ZONE_ID=$(zoneid_by_name ${PUBLIC_DOMAIN_NAME})

		if [ -n "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then
			echo_blue_bold "Found PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME} AWS_ROUTE53_PUBLIC_ZONE_ID=$AWS_ROUTE53_PUBLIC_ZONE_ID"
			echo_red_bold "Route53 will be used to register public domain hosts"
            EXTERNAL_DNS_PROVIDER=aws
			CERT_SELFSIGNED=${CERT_SELFSIGNED_FORCED}

			return
		fi

		# Check if godaddy is candidate
		if [ -n "${CERT_GODADDY_API_KEY}" ]; then
            local REGISTERED=$(curl -s "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}" \
				-H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
				-H "Content-Type: application/json" | jq -r '.status//""')

            if [ "${REGISTERED}" = "ACTIVE" ]; then
    			echo_blue_bold "Found PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME} from godaddy"
    			echo_red_bold "Godaddy will be used to register public domain hosts"
                EXTERNAL_DNS_PROVIDER=godaddy
				CERT_SELFSIGNED=${CERT_SELFSIGNED_FORCED}

				return
            fi
		fi
        
		CERT_SELFSIGNED=YES

		if [ ${USE_BIND9_SERVER} = "true" ]; then
			echo_red_bold "Use Bind9 DNS provider for PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}"

			if [ -z "$(rndc -s ${BIND9_HOST} -k ${BIND9_RNDCKEY} showzone ${PUBLIC_DOMAIN_NAME} 2>/dev/null)" ] && [ ${INSTALL_BIND9_SERVER} != "YES" ]; then
				echo_red_bold "Zone ${PUBLIC_DOMAIN_NAME} is not found on bind9 server: ${BIND9_HOST}"
				exit 1
			fi

			EXTERNAL_DNS_PROVIDER=rfc2136
			USE_ETC_HOSTS=false
		else
			echo_red_bold "PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME} not found, use self signed cert and /etc/hosts"

			EXTERNAL_DNS_PROVIDER=none
		fi
	else
		CERT_SELFSIGNED=YES
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function find_private_dns_provider() {
	if [ "${PUBLIC_DOMAIN_NAME}" != "${PRIVATE_DOMAIN_NAME}" ]; then
		if [ "${USE_BIND9_SERVER}" == "true" ]; then
			if [ -z "$(dig @${PRIVATE_DNS} ${PRIVATE_DOMAIN_NAME} NS +short)" ]; then
				echo_red_bold "Create Bind9 server for PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}"
				INSTALL_BIND9_SERVER=YES
			else
				echo_blue_bold "Found PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME} on Bind9 server"
				echo_red_bold "Use Bind9 server: ${BIND9_HOST} for PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}"
			fi
		# Create DNS server if needed
		elif [ -z "$(dig ${PRIVATE_DOMAIN_NAME} NS +short)" ]; then
			echo_red_bold "Create Bind9 server for PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}"
			USE_BIND9_SERVER=true
			INSTALL_BIND9_SERVER=YES
		fi
	elif [ "${EXTERNAL_DNS_PROVIDER}" = "none" ]; then
		if [ -z "$(dig ${PRIVATE_DOMAIN_NAME} NS +short)" ]; then
			echo_red_bold "Create Bind9 server for PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}"
			USE_BIND9_SERVER=true
			INSTALL_BIND9_SERVER=YES
			EXTERNAL_DNS_PROVIDER=rfc2136
		fi
	fi

	if [ "${USE_BIND9_SERVER}" = "true" ]; then
		USE_ETC_HOSTS=false
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_plateform() {
	find_private_dns_provider
	find_public_dns_provider
	prepare_node_indexes
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_image() {
	# If the VM template doesn't exists, build it from scrash
	TARGET_IMAGE_UUID=$(get_vmuuid ${TARGET_IMAGE})

	if [ -z "${TARGET_IMAGE_UUID}" ] || [ "${TARGET_IMAGE_UUID}" == "ERROR" ]; then
		echo_title "Create ${PLATEFORM} preconfigured image ${TARGET_IMAGE}"

		if [ ${PLATEFORM} == "multipass" ]; then
			PRIMARY_NETWORK="${VC_NETWORK_PUBLIC}"
		else
			PRIMARY_NETWORK="${VC_NETWORK_PRIVATE}"
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
			--primary-network="${VC_NETWORK_PRIVATE}"

		TARGET_IMAGE_UUID=$(get_vmuuid ${PRIMARY_NETWORK})
	fi

	if [ "${CREATE_IMAGE_ONLY}" = "YES" ]; then
		echo_blue_bold "Create image only, done..."
		exit 0
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_register_certificate() {
echo -n
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_cert() {
	if [ -z "${PRIVATE_DOMAIN_NAME}" ]; then
		echo_red_bold "PRIVATE_DOMAIN_NAME is not defined"
		exit
	fi

	# If CERT doesn't exist, create one autosigned
	if [ -z "${PUBLIC_DOMAIN_NAME}" ]; then
		DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}
	else
		DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
	fi

	if [ -z "${DOMAIN_NAME}" ]; then
		echo_red_bold "Public domaine is not defined, unable to create auto signed cert, exit"
		exit 1
	fi

	if [ -z ${SSL_LOCATION} ]; then
		if [ -f ${HOME}/etc/ssl/${DOMAIN_NAME}/cert.pem ]; then
			SSL_LOCATION=${HOME}/etc/ssl/${DOMAIN_NAME}
		elif [ -f ${HOME}/Library/etc/ssl/${DOMAIN_NAME}/cert.pem ]; then
			SSL_LOCATION=${HOME}/Library/etc/ssl/${DOMAIN_NAME}
		elif [ -f $HOME/.acme.sh/${DOMAIN_NAME}/cert.pem ]; then
			SSL_LOCATION=$HOME/.acme.sh/${DOMAIN_NAME}
		elif [ -f ${HOME}/Library/etc/ssl/${DOMAIN_NAME}/cert.pem ]; then
			SSL_LOCATION=${HOME}/Library/etc/ssl/${DOMAIN_NAME}
		elif [ -f $HOME/.acme.sh/${DOMAIN_NAME}/cert.pem ]; then
			SSL_LOCATION=${HOME}/.acme.sh/${DOMAIN_NAME}
		else
			SSL_LOCATION=${PWD}/etc/ssl/${DOMAIN_NAME}
		fi
	fi

	if [ ! -f ${SSL_LOCATION}/privkey.pem ]; then
		echo_blue_bold "Create autosigned certificat for domain: ${DOMAIN_NAME}, email: ${CERT_EMAIL}"
		${CURDIR}/create-cert.sh --domain ${DOMAIN_NAME} --ssl-location ${SSL_LOCATION} --cert-email ${CERT_EMAIL}
	else
		if [ ! -f ${SSL_LOCATION}/cert.pem ]; then
			echo_red "${SSL_LOCATION}/cert.pem not found, exit"
			exit 1
		fi

		if [ ! -f ${SSL_LOCATION}/fullchain.pem ]; then
			echo_red "${SSL_LOCATION}/fullchain.pem not found, exit"
			exit 1
		fi

		# Extract the domain name from CERT
		DOMAIN_NAME=$(openssl x509 -noout -subject -in ${SSL_LOCATION}/cert.pem -nameopt sep_multiline | grep 'CN=' | awk -F= '{print $2}' | sed -e 's/^[\s\t]*//')

		if [ "${DOMAIN_NAME}" != "${PRIVATE_DOMAIN_NAME}" ] && [ "${DOMAIN_NAME}" != "${PUBLIC_DOMAIN_NAME}" ]; then
			echo_red_bold "Warning: The provided domain ${DOMAIN_NAME} from certificat does not target domain ${PRIVATE_DOMAIN_NAME} or ${PUBLIC_DOMAIN_NAME}"
			exit 1
		fi
	fi

	plateform_register_certificate "${DOMAIN_NAME}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_dns() {
	echo -n
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function save_buildenv() {
    set +u

cat ${PLATEFORMDEFS} > ${TARGET_CONFIG_LOCATION}/buildenv

cat >> ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
#===============================================
export APISERVER_ADVERTISE_PORT=${APISERVER_ADVERTISE_PORT}
export AUTOSCALE_MACHINE=${AUTOSCALE_MACHINE}
export AUTOSCALER_DESKTOP_UTILITY_ADDR=${AUTOSCALER_DESKTOP_UTILITY_ADDR}
export AUTOSCALER_DESKTOP_UTILITY_CACERT=${AUTOSCALER_DESKTOP_UTILITY_CACERT}
export AUTOSCALER_DESKTOP_UTILITY_CERT=${AUTOSCALER_DESKTOP_UTILITY_CERT}
export AUTOSCALER_DESKTOP_UTILITY_KEY=${AUTOSCALER_DESKTOP_UTILITY_CERT}
export AUTOSCALER_DESKTOP_UTILITY_TLS=${AUTOSCALER_DESKTOP_UTILITY_TLS}
export AWS_ACCESSKEY=${AWS_ACCESSKEY}
export AWS_ROUTE53_ACCESSKEY=${AWS_ROUTE53_ACCESSKEY}
export AWS_ROUTE53_PUBLIC_ZONE_ID=${AWS_ROUTE53_PUBLIC_ZONE_ID}
export AWS_ROUTE53_SECRETKEY=${AWS_ROUTE53_SECRETKEY}
export AWS_SECRETKEY=${AWS_SECRETKEY}
export CERT_GODADDY_API_KEY=${CERT_GODADDY_API_KEY}
export CERT_GODADDY_API_SECRET=${CERT_GODADDY_API_SECRET}
export CERT_ZEROSSL_EAB_HMAC_SECRET=${CERT_ZEROSSL_EAB_HMAC_SECRET}
export CERT_ZEROSSL_EAB_KID=${CERT_ZEROSSL_EAB_KID}
export CLOUD_PROVIDER_CONFIG=${CLOUD_PROVIDER_CONFIG}
export CLOUD_PROVIDER=${CLOUD_PROVIDER}
export CNI_PLUGIN=${CNI_PLUGIN}
export CNI_VERSION=${CNI_VERSION}
export CONFIGURATION_LOCATION=${CONFIGURATION_LOCATION}
export CONTAINER_ENGINE=${CONTAINER_ENGINE}
export CONTROL_PLANE_MACHINE=${CONTROL_PLANE_MACHINE}
export CONTROLNODE_INDEX=${CONTROLNODE_INDEX}
export CONTROLNODES=${CONTROLNODES}
export CORESTOTAL="${CORESTOTAL}"
export DOMAIN_NAME=${DOMAIN_NAME}
export ETCD_DST_DIR=${ETCD_DST_DIR}
export EXTERNAL_DNS_PROVIDER=${EXTERNAL_DNS_PROVIDER}
export EXTERNAL_ETCD_ARGS=${EXTERNAL_ETCD_ARGS}
export EXTERNAL_ETCD=${EXTERNAL_ETCD}
export FIRSTNODE=${FIRSTNODE}
export GRPC_PROVIDER=${GRPC_PROVIDER}
export HA_CLUSTER=${HA_CLUSTER}
export KUBECONFIG=${KUBECONFIG}
export KUBERNETES_DISTRO=${KUBERNETES_DISTRO}
export KUBERNETES_PASSWORD=${KUBERNETES_PASSWORD}
export KUBERNETES_USER=${KUBERNETES_USER}
export KUBERNETES_VERSION=${KUBERNETES_VERSION}
export LASTNODE_INDEX=${LASTNODE_INDEX}
export LAUNCH_CA=${LAUNCH_CA}
export LOAD_BALANCER_PORT=${LOAD_BALANCER_PORT}
export MASTER_NODE_ALLOW_DEPLOYMENT=${MASTER_NODE_ALLOW_DEPLOYMENT}
export MASTERKUBE="${MASTERKUBE}"
export MAXAUTOPROVISIONNEDNODEGROUPCOUNT=${MAXAUTOPROVISIONNEDNODEGROUPCOUNT}
export MAXNODES=${MAXNODES}
export MAXTOTALNODES=${MAXTOTALNODES}
export MEMORYTOTAL="${MEMORYTOTAL}"
export METALLB_IP_RANGE=${METALLB_IP_RANGE}
export MINNODES=${MINNODES}
export NETWORK_PRIVATE_ROUTES=(${NETWORK_PRIVATE_ROUTES[@]})
export NETWORK_PUBLIC_ROUTES=(${NETWORK_PUBLIC_ROUTES[@]})
export NFS_SERVER_ADDRESS=${NFS_SERVER_ADDRESS}
export NFS_SERVER_PATH=${NFS_SERVER_PATH}
export NFS_STORAGE_CLASS=${NFS_STORAGE_CLASS}
export NGINX_MACHINE=${NGINX_MACHINE}
export NODEGROUP_NAME="${NODEGROUP_NAME}"
export OSDISTRO=${OSDISTRO}
export PLATEFORM="${PLATEFORM}"
export PREFER_SSH_PUBLICIP=${PREFER_SSH_PUBLICIP}
export PRIVATE_ADDR_IPS=(${PRIVATE_ADDR_IPS[@]})
export PRIVATE_DNS_NAMES=(${PRIVATE_DNS_NAMES[@]})
export PRIVATE_DNS=${PRIVATE_DNS}
export PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}
export PRIVATE_GATEWAY=${PRIVATE_GATEWAY}
export PRIVATE_IP=${PRIVATE_IP}
export PRIVATE_MASK_CIDR=${PRIVATE_MASK_CIDR}
export PRIVATE_NET_INF=${PRIVATE_NET_INF}
export PRIVATE_NETMASK=${PRIVATE_NETMASK}
export PUBLIC_ADDR_IPS=(${PUBLIC_ADDR_IPS[@]})
export PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
export PUBLIC_IP="${PUBLIC_IP}"
export REGION=${REGION}
export REGISTRY=${REGISTRY}
export RESUME=${RESUME}
export SCALEDNODES_DHCP=${SCALEDNODES_DHCP}
export SCALEDOWNDELAYAFTERADD=${SCALEDOWNDELAYAFTERADD}
export SCALEDOWNDELAYAFTERDELETE=${SCALEDOWNDELAYAFTERDELETE}
export SCALEDOWNDELAYAFTERFAILURE=${SCALEDOWNDELAYAFTERFAILURE}
export SCALEDOWNENABLED=${SCALEDOWNENABLED}
export SCALEDOWNUNEEDEDTIME=${SCALEDOWNUNEEDEDTIME}
export SCALEDOWNUNREADYTIME=${SCALEDOWNUNREADYTIME}
export SEED_ARCH=${SEED_ARCH}
export SEED_IMAGE="${SEED_IMAGE}"
export SEED_USER=${SEED_USER}
export SILENT="${SILENT}"
export SSH_KEY_FNAME=${SSH_KEY_FNAME}
export SSH_KEY="${SSH_KEY}"
export SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}
export SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}
export SSL_LOCATION=${SSL_LOCATION}
export TARGET_CLUSTER_LOCATION=${TARGET_CLUSTER_LOCATION}
export TARGET_CONFIG_LOCATION=${TARGET_CONFIG_LOCATION}
export TARGET_DEPLOY_LOCATION=${TARGET_DEPLOY_LOCATION}
export TARGET_IMAGE=${TARGET_IMAGE}
export TRANSPORT=${TRANSPORT}
export UNREMOVABLENODERECHECKTIMEOUT=${UNREMOVABLENODERECHECKTIMEOUT}
export UPGRADE_CLUSTER=${UPGRADE_CLUSTER}
export USE_DHCP_ROUTES_PRIVATE=${USE_DHCP_ROUTES_PRIVATE}
export USE_DHCP_ROUTES_PUBLIC=${USE_DHCP_ROUTES_PUBLIC}
export USE_ETC_HOSTS=${USE_ETC_HOSTS}
export USE_KEEPALIVED=${USE_KEEPALIVED}
export USE_NGINX_GATEWAY=${USE_NGINX_GATEWAY}
export USE_NLB=${USE_NLB}
export USE_ZEROSSL=${USE_ZEROSSL}
export VC_NETWORK_PRIVATE=${VC_NETWORK_PRIVATE}
export VC_NETWORK_PUBLIC=${VC_NETWORK_PUBLIC}
export VPC_PRIVATE_SUBNET_IDS=(${VPC_PRIVATE_SUBNET_IDS[@]})
export VPC_PUBLIC_SUBNET_IDS=(${VPC_PUBLIC_SUBNET_IDS[@]})
export WORKERNODE_INDEX=${WORKERNODE_INDEX}
export WORKERNODES=${WORKERNODES}
export ZONEID=${ZONEID}

#===============================================
EOF
    set -u
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_deployment() {
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
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_vendordata() {
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
- encoding: gzip+base64
  content: $(cat ${TARGET_CONFIG_LOCATION}/credential.yaml | gzip -c9 | base64 -w 0)
  owner: root:root
  path: ${IMAGE_CREDENTIALS_CONFIG}
  permissions: '0644'
EOF
	elif [ "${PLATEFORM}" = "aws" ]; then
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
EOF

		cat >>${TARGET_CONFIG_LOCATION}/vendordata.yaml <<EOF
write_files:
- encoding: gzip+base64
  content: $(cat ${TARGET_CONFIG_LOCATION}/credential.yaml | gzip -c9 | base64 -w 0)
  owner: root:root
  path: ${IMAGE_CREDENTIALS_CONFIG}
  permissions: '0644'
EOF
	fi

	gzip -c9 <${TARGET_CONFIG_LOCATION}/vendordata.yaml | base64 -w 0 | tee > ${TARGET_CONFIG_LOCATION}/vendordata.base64
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_networking() {
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
	if [ ${USE_KEEPALIVED} = "YES" ] || [[ "${USE_NLB}" = "YES" && ${USE_NGINX_GATEWAY} = "NO" ]]; then
		PRIVATE_ADDR_IPS[0]="${NODE_IP}"
		PRIVATE_DNS_NAMES[0]=""
		PUBLIC_ADDR_IPS[0]=${PUBLIC_NODE_IP}

		NODE_IP=$(nextip ${NODE_IP})
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
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
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_extras_ip() {
	local INDEX=$1

	for INDEX in 1 2
	do
		NODE_INDEX=$(($LASTNODE_INDEX + ${INDEX}))
		NODE_IP=$(nextip ${NODE_IP})
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})

		PRIVATE_ADDR_IPS[${NODE_INDEX}]=${NODE_IP}
		PUBLIC_ADDR_IPS[${NODE_INDEX}]=${PUBLIC_NODE_IP}
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function collect_cluster_nodes() {
	if [ "${HA_CLUSTER}" = "true" ]; then
		for INDEX in $(seq ${CONTROLNODE_INDEX} $((CONTROLNODE_INDEX + ${CONTROLNODES} - 1)))
		do
			MASTERKUBE_NODE="${NODEGROUP_NAME}-master-0${INDEX}"
			IPADDR="${PRIVATE_ADDR_IPS[${INDEX}]}"
			NODE_DNS="${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}:${IPADDR}"

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
	else
		IPADDR="${PRIVATE_ADDR_IPS[${CONTROLNODE_INDEX}]}"
		IPRESERVED1=${PRIVATE_ADDR_IPS[$((LASTNODE_INDEX + 1))]}
		IPRESERVED2=${PRIVATE_ADDR_IPS[$((LASTNODE_INDEX + 2))]}

		if [ ${CONTROLNODE_INDEX} -gt 0 ]; then
			CLUSTER_NODES="${NODEGROUP_NAME}-master-01.${PRIVATE_DOMAIN_NAME}:${IPADDR},${NODEGROUP_NAME}-master-02.${PRIVATE_DOMAIN_NAME}:${IPRESERVED1},${NODEGROUP_NAME}-master-03.${PRIVATE_DOMAIN_NAME}:${IPRESERVED2}"
		else
			CLUSTER_NODES="${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}:${IPADDR},${NODEGROUP_NAME}-master-02.${PRIVATE_DOMAIN_NAME}:${IPRESERVED1},${NODEGROUP_NAME}-master-03.${PRIVATE_DOMAIN_NAME}:${IPRESERVED2}"
		fi
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_all_vms() {
	local LAUNCH_IN_BACKGROUND="NO"

	if [ "${PLATEFORM}" == "openstack" ] || [ "${PLATEFORM}" == "aws" ] || [ "${PLATEFORM}" == "vsphere" ]; then
		LAUNCH_IN_BACKGROUND=YES
	fi

	for INDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
	do
		PRIVATE_ADDR_IPS[${INDEX}]="${NODE_IP}"
		PRIVATE_DNS_NAMES[${INDEX}]=""
		PUBLIC_ADDR_IPS[${INDEX}]=${PUBLIC_NODE_IP}
	
		if [ "${INSTALL_BIND9_SERVER}" == "YES" ] && [ ${INDEX} -eq ${FIRSTNODE} ]; then
			create_vm ${INDEX} ${PUBLIC_NODE_IP} ${NODE_IP}
		elif [ "${LAUNCH_IN_BACKGROUND}" = "YES" ]; then
			create_vm ${INDEX} ${PUBLIC_NODE_IP} ${NODE_IP} &
		else
			create_vm ${INDEX} ${PUBLIC_NODE_IP} ${NODE_IP}
		fi

		# Reserve 2 ip for potentiel HA cluster
		if [[ "${HA_CLUSTER}" == "false" ]] && [[ ${INDEX} -eq ${CONTROLNODE_INDEX} ]]; then
			create_extras_ip ${INDEX}
		fi

		NODE_IP=$(nextip ${NODE_IP})
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP})
	done

	wait_jobs_finish

	if [ ${LAUNCH_IN_BACKGROUND} = "YES" ]; then
		for INDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
		do
			local SUFFIX=$(named_index_suffix ${INDEX})
			local PRIV_ADDR=$(jq -r '.PrivateIpAddress' ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json)
			local PRIV_DNS=$(jq -r '.PrivateDnsName' ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json )
			local PUBLIC_ADDR=$(jq -r '.PublicIpAddress' ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json)

			PRIVATE_ADDR_IPS[${INDEX}]=${PRIV_ADDR}
			PRIVATE_DNS_NAMES[${INDEX}]=${PRIV_DNS}
			PUBLIC_ADDR_IPS[${INDEX}]=${PUBLIC_ADDR}
		done
	fi

	CONTROL_PLANE_ENDPOINT="${PRIVATE_ADDR_IPS[0]:-}"
	LOAD_BALANCER_IP=${CONTROL_PLANE_ENDPOINT}

	if [ ${WORKERNODES} -gt 0 ]; then
		FIRST_WORKER_NODE_IP=${PRIVATE_ADDR_IPS[${WORKERNODE_INDEX}]}
	else
		FIRST_WORKER_NODE_IP=${NODE_IP}
	fi

	# echo_red_bold "LASTNODE_INDEX=${LASTNODE_INDEX}"
	# echo_red_bold "$(typeset -p PRIVATE_ADDR_IPS)"
	# echo_red_bold "$(typeset -p PRIVATE_DNS_NAMES)"

	collect_cluster_nodes
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_keepalived() {
	echo_title "Created keepalived cluster: ${CLUSTER_NODES}"

	for INDEX in $(seq 1 ${CONTROLNODES})
	do
		if [ ! -f ${TARGET_CONFIG_LOCATION}/keepalived-0${INDEX}-prepared ]; then
			IPADDR="${PRIVATE_ADDR_IPS[${INDEX}]}"

			echo_title "Start keepalived node: ${IPADDR}"

			case "${INDEX}" in
				1)
					KEEPALIVED_PEER1=${PRIVATE_ADDR_IPS[2]}
					KEEPALIVED_PEER2=${PRIVATE_ADDR_IPS[3]}
					KEEPALIVED_STATUS=MASTER
					;;
				2)
					KEEPALIVED_PEER1=${PRIVATE_ADDR_IPS[1]}
					KEEPALIVED_PEER2=${PRIVATE_ADDR_IPS[3]}
					KEEPALIVED_STATUS=BACKUP
					;;
				3)
					KEEPALIVED_PEER1=${PRIVATE_ADDR_IPS[1]}
					KEEPALIVED_PEER2=${PRIVATE_ADDR_IPS[2]}
					KEEPALIVED_STATUS=BACKUP
					;;
			esac

			eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-keepalived.sh \
				--bind-address="${PRIVATE_ADDR_IPS[0]}" \
				--bind-port="${APISERVER_ADVERTISE_PORT}" \
				--keep-alive-password="${KUBERNETES_PASSWORD}" \
				--keep-alive-priority="$((80-INDEX))" \
				--keep-alive-multicast=${PRIVATE_ADDR_IPS[${INDEX}]} \
				--keep-alive-peer1=${KEEPALIVED_PEER1} \
				--keep-alive-peer2=${KEEPALIVED_PEER2} \
				--keep-alive-status=${KEEPALIVED_STATUS} ${SILENT}

			touch ${TARGET_CONFIG_LOCATION}/keepalived-0${INDEX}-prepared
		fi
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_nameserver() {
	if [ "${EXTERNAL_DNS_PROVIDER}" == "rfc2036" ]; then
		IPADDR=${PRIVATE_ADDR_IPS[${INDEX}]}

		echo_blue_bold "Start bind server with IP: ${IPADDR}"

		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-load-bind9.sh \
			--cluster-nodes="${CLUSTER_NODES}" \
			--master-dns=${PRIVATE_DNS} \
			--public-zone-name=${PUBLIC_DOMAIN_NAME} \
			--private-zone-name=${PRIVATE_DOMAIN_NAME} ${SILENT}
		
		eval scp ${SCP_OPTIONS} ${KUBERNETES_USER}@${IPADDR}:/etc/cluster/* ${TARGET_CLUSTER_LOCATION}/masterkube-key.key ${SILENT}
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_nginx_gateway() {
	for INDEX in $(seq ${FIRSTNODE} $((CONTROLNODE_INDEX - 1)) )
	do
		MASTERKUBE_NODE=$(get_vm_name ${INDEX})
		IPADDR=${PRIVATE_ADDR_IPS[${INDEX}]}

		if [ ${INDEX} -eq ${FIRSTNODE} ]; then
			LOAD_BALANCER_IP="${PRIVATE_ADDR_IPS[${INDEX}]}"
		else
			LOAD_BALANCER_IP="${LOAD_BALANCER_IP},${PRIVATE_ADDR_IPS[${INDEX}]}"
		fi

		echo_blue_bold "Start load balancer ${MASTERKUBE_NODE} instance ${INDEX} with IP: ${IPADDR}"

		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-load-balancer.sh \
			--listen-port=${LOAD_BALANCER_PORT} \
			--cluster-nodes="${CLUSTER_NODES}" \
			--control-plane-endpoint=${MASTERKUBE}.${PRIVATE_DOMAIN_NAME} \
			--listen-ip=0.0.0.0 ${SILENT}

		echo ${MASTERKUBE_NODE} > ${TARGET_CONFIG_LOCATION}/node-0${INDEX}-prepared
	done

	echo_red_bold LOAD_BALANCER_IP=$LOAD_BALANCER_IP
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function register_nlb_dns() {
	local RECORDTYPE=$1
	local PRIVATE_NLB_DNS=$2
	local PUBLIC_NLB_DNS=$3

	if [ -n "${PRIVATE_NLB_DNS}" ]; then
		CONTROL_PLANE_ENDPOINT=${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}

		if [ -n "${AWS_ROUTE53_PRIVATE_ZONE_ID}" ]; then
			echo_title "Register dns ${MASTERKUBE}.${PRIVATE_DOMAIN_NAME} in route53: ${AWS_ROUTE53_PRIVATE_ZONE_ID}, record: ${PRIVATE_NLB_DNS}"

			cat > ${TARGET_CONFIG_LOCATION}/route53-nlb.json <<EOF
			{
				"Comment": "${MASTERKUBE} private DNS entry",
				"Changes": [
					{
						"Action": "UPSERT",
						"ResourceRecordSet": {
							"Name": "${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}",
							"Type": "${RECORDTYPE}",
							"TTL": 60,
							"ResourceRecords": [
								{
									"Value": "${PRIVATE_NLB_DNS}"
								}
							]
						}
					}
				]
			}
EOF

			aws route53 change-resource-record-sets --profile ${AWS_ROUTE53_PROFILE} \
				--region ${AWS_REGION} \
				--hosted-zone-id ${AWS_ROUTE53_PRIVATE_ZONE_ID} \
				--change-batch file://${TARGET_CONFIG_LOCATION}/route53-nlb.json > /dev/null

			add_host "${PRIVATE_NLB_DNS} ${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}"
		elif [ -n "${OS_PRIVATE_DNS_ZONEID}" ]; then
			echo_title "Register dns ${MASTERKUBE}.${PRIVATE_DOMAIN_NAME} designate, id: ${OS_PRIVATE_DNS_ZONEID}, record: ${PRIVATE_NLB_DNS}"
			
			DNS_ENTRY=$(openstack recordset create -f json --ttl 60 --type ${RECORDTYPE} --record ${PRIVATE_NLB_DNS} "${PRIVATE_DOMAIN_NAME}." ${MASTERKUBE} 2>/dev/null | jq -r '.id // ""')
			CONTROL_PLANE_ENDPOINT=${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}

			cat > ${TARGET_CONFIG_LOCATION}/designate-nlb.json <<EOF
			{
				"id": "${DNS_ENTRY}",
				"zone_id": "${OS_PRIVATE_DNS_ZONEID}",
				"name": "${MASTERKUBE}",
				"type": "${RECORDTYPE}",
				"record": "${PRIVATE_NLB_DNS}"
			}
EOF
		elif [ ${USE_BIND9_SERVER} = "true" ]; then
			echo_title "Register bind9 dns ${MASTERKUBE}.${PRIVATE_DOMAIN_NAME} designate, record: ${PRIVATE_NLB_DNS}"

			cat > ${TARGET_CONFIG_LOCATION}/rfc2136-nlb.cmd <<EOF
server ${BIND9_HOST} ${BIND9_PORT}
update add ${MASTERKUBE}.${PRIVATE_DOMAIN_NAME} 60 ${RECORDTYPE} ${PRIVATE_NLB_DNS}
send
EOF

			CONTROL_PLANE_ENDPOINT=${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}

			cat ${TARGET_CONFIG_LOCATION}/rfc2136-nlb.cmd | nsupdate -k ${BIND9_RNDCKEY}
		fi
	fi

	if [ -n "${PUBLIC_NLB_DNS}" ]; then
		if [ "${EXTERNAL_DNS_PROVIDER}" = "aws" ]; then
			echo_title "Register public dns ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} in route53: ${AWS_ROUTE53_PUBLIC_ZONE_ID}"

			cat > ${TARGET_CONFIG_LOCATION}/route53-public.json <<EOF
{
	"Comment": "${MASTERKUBE} public DNS entry",
	"Changes": [
		{
			"Action": "UPSERT",
			"ResourceRecordSet": {
				"Name": "${MASTERKUBE}.${PUBLIC_DOMAIN_NAME}",
				"Type": "${RECORDTYPE}",
				"TTL": 60,
				"ResourceRecords": [
					{
						"Value": "${PUBLIC_NLB_DNS}"
					}
				]
			}
		}
	]
}
EOF

			aws route53 change-resource-record-sets --profile ${AWS_ROUTE53_PROFILE} --hosted-zone-id ${AWS_ROUTE53_PUBLIC_ZONE_ID} \
				--change-batch file://${TARGET_CONFIG_LOCATION}/route53-public.json > /dev/null

		elif [ "${EXTERNAL_DNS_PROVIDER}" = "godaddy" ]; then
			echo_title "Register public dns ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} in godaddy"

			curl -s -X PUT "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/${RECORDTYPE}/${MASTERKUBE}" \
				-H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
				-H "Content-Type: application/json" \
				-d "[{\"data\": \"${PUBLIC_NLB_DNS}\"}]"

			cat > ${TARGET_CONFIG_LOCATION}/godaddy-public.json <<EOF
			{
				"zone": "${PUBLIC_DOMAIN_NAME}",
				"type": "${RECORDTYPE}",
				"name": "${MASTERKUBE}",
				"record": [ "${PUBLIC_NLB_DNS}" ]
			}
EOF

		elif [ "${EXTERNAL_DNS_PROVIDER}" = "designate" ]; then
			echo_title "Register public dns ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} with designate"

			DNS_ENTRY=$(openstack recordset create -f json --ttl 60 --type ${RECORDTYPE} --record ${PUBLIC_NLB_DNS} "${PUBLIC_DOMAIN_NAME}." ${MASTERKUBE} 2>/dev/null | jq -r '.id // ""')

			cat > ${TARGET_CONFIG_LOCATION}/designate-public.json <<EOF
			{
				"id": "${DNS_ENTRY}",
				"zone_id": "${OS_PUBLIC_DNS_ZONEID}",
				"name": "${MASTERKUBE}",
				"record": "${PUBLIC_NLB_DNS}"
			}
EOF
		elif [ "${EXTERNAL_DNS_PROVIDER}" = "rfc2136" ]; then
			echo_title "Register public dns ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} with bind9"

			cat > ${TARGET_CONFIG_LOCATION}/rfc2136-public.cmd <<EOF
server ${BIND9_HOST} ${BIND9_PORT}
update add ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} 60 ${RECORDTYPE} ${PUBLIC_NLB_DNS}
send
EOF

			cat ${TARGET_CONFIG_LOCATION}/rfc2136-public.cmd | nsupdate -k ${BIND9_RNDCKEY}
		fi
	fi

	echo "export PRIVATE_NLB_DNS=${PRIVATE_NLB_DNS}" >> ${TARGET_CONFIG_LOCATION}/buildenv
	echo "export PUBLIC_NLB_DNS=${PUBLIC_NLB_DNS}" >> ${TARGET_CONFIG_LOCATION}/buildenv
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_plateform_nlb() {
	create_nginx_gateway
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_plateform_nlb_member() {
	local NAME=$1
	local ADDR=$2

	echo -n
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_nlb_member() {
	local NODEINDEX=$1

	if [ "${HA_CLUSTER}" = "true" ] && [ "${USE_NLB}" = "YES" ]; then
		local NAME=$(get_vm_name ${NODEINDEX})
		local ADDR=${PRIVATE_ADDR_IPS[${INDEX}]}

		create_plateform_nlb_member ${NAME} ${ADDR}
	fi
}
#===========================================================================================================================================
#
#===========================================================================================================================================
function create_load_balancer() {
	if [ "${HA_CLUSTER}" = "true" ]; then
		if [ "${USE_NGINX_GATEWAY}" = "YES" ]; then
			create_nginx_gateway
		fi

		if [ ${USE_KEEPALIVED} = "YES" ]; then
			create_keepalived
		elif [ "${USE_NLB}" = "YES" ]; then
			create_plateform_nlb
		fi
	elif [ ${CONTROLNODE_INDEX} -gt 0 ]; then
		create_nginx_gateway
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_dns_rentries() {
    local RECORDS=()
    local GODADDY_REGISTER="[]"
	local DESIGNATE_REGISTER=()
    local PRIVATE_ROUTE53_REGISTER=$(cat << EOF
    {
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}",
                    "Type": "A",
                    "TTL": 60,
                    "ResourceRecords": [
                    ]
                }
            }
        ]
    }
EOF
)

    local PUBLIC_ROUTE53_REGISTER=$(cat << EOF
    {
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "${MASTERKUBE}.${PUBLIC_DOMAIN_NAME}",
                    "Type": "A",
                    "TTL": 60,
                    "ResourceRecords": [
                    ]
                }
            }
        ]
    }
EOF
)

	if [ "${USE_KEEPALIVED}" == "YES" ]; then
		local PRIVATEIPADDR=${PRIVATE_ADDR_IPS[0]}

		for PRIVATEIPADDR in $(echo ${LOAD_BALANCER_IP} | tr ',' ' ')
		do
			DESIGNATE_REGISTER+=(${PRIVATEIPADDR})
			GODADDY_REGISTER=$(echo ${GODADDY_REGISTER} | jq --arg IPADDR "${PRIVATEIPADDR}" '. += [ { "data": $IPADDR, "ttl": 600 } ]')
			RECORDS+=("--record ${PRIVATEIPADDR}")
			PUBLIC_ROUTE53_REGISTER=$(echo ${PUBLIC_ROUTE53_REGISTER} | jq --arg IPADDR "${PRIVATEIPADDR}" '.Changes[0].ResourceRecordSet.ResourceRecords += [ { "Value": $IPADDR } ]')
		done
	fi

	for INDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
	do
		local SUFFIX=$(named_index_suffix ${INDEX})
		local LAUNCHED_INSTANCE=$(cat ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json)
		local PRIVATEIPADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateIpAddress // ""')
		local PUBLICIPADDR=$(echo ${LAUNCHED_INSTANCE} | jq --arg IPADDR ${PRIVATEIPADDR} -r '.PublicIpAddress // $IPADDR')

		PRIVATE_ADDR_IPS[${INDEX}]=${PRIVATEIPADDR}
		PUBLIC_ADDR_IPS[${INDEX}]=${PUBLICIPADDR}

		if [[ ${USE_KEEPALIVED} == "NO" ]] && [[ "${USE_NLB}" = "NO" || "${HA_CLUSTER}" = "false" ]]; then
			local REGISTER_IP=

#			if [ ${INDEX} -lt ${WORKERNODE_INDEX} ] && [ ${INDEX} -ge ${CONTROLNODE_INDEX} ] && [ ${EXPOSE_PUBLIC_CLUSTER} = "true" ] && [ "${CONTROLPLANE_USE_PUBLICIP}" = "true" ] && [ "${USE_NLB}" = "NO" ] && [ "${USE_NGINX_GATEWAY}" = "NO" ]; then

			if [ ${HA_CLUSTER} = "true" ] && [ ${INDEX} -lt ${WORKERNODE_INDEX} ] && [ ${INDEX} -ge ${CONTROLNODE_INDEX} ] && [ "${USE_NLB}" = "NO" ] && [ "${USE_NGINX_GATEWAY}" = "NO" ]; then
				REGISTER_IP=${PRIVATEIPADDR}
			elif [ ${INDEX} -eq 0 ] || [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
				REGISTER_IP=${PRIVATEIPADDR}
			fi

			if [ -n "${REGISTER_IP}" ]; then
				PRIVATE_ROUTE53_REGISTER=$(echo ${PRIVATE_ROUTE53_REGISTER} | jq --arg IPADDR "${REGISTER_IP}" '.Changes[0].ResourceRecordSet.ResourceRecords += [ { "Value": $IPADDR } ]')

				if [ -n "${PUBLICIPADDR}" ]; then
					REGISTER_IP=${PUBLICIPADDR}
				fi

				DESIGNATE_REGISTER+=(${REGISTER_IP})
				GODADDY_REGISTER=$(echo ${GODADDY_REGISTER} | jq --arg IPADDR "${REGISTER_IP}" '. += [ { "data": $IPADDR, "ttl": 600 } ]')
				RECORDS+=("--record ${REGISTER_IP}")
				PUBLIC_ROUTE53_REGISTER=$(echo ${PUBLIC_ROUTE53_REGISTER} | jq --arg IPADDR "${REGISTER_IP}" '.Changes[0].ResourceRecordSet.ResourceRecords += [ { "Value": $IPADDR } ]')
			fi
		fi
	done

	if [ ${#DESIGNATE_REGISTER[@]} -gt 0 ]; then
		local RECORDTYPE=A

		# Register in Route53 IP addresses point in private IP
		if [ -n "${AWS_ROUTE53_PRIVATE_ZONE_ID}" ]; then
			echo ${PRIVATE_ROUTE53_REGISTER} | jq . > ${TARGET_CONFIG_LOCATION}/route53-nlb.json
			aws route53 change-resource-record-sets --profile ${AWS_ROUTE53_PROFILE} \
				--hosted-zone-id ${AWS_ROUTE53_PRIVATE_ZONE_ID} \
				--change-batch file://${TARGET_CONFIG_LOCATION}/route53-nlb.json > /dev/null
		fi

		if [ "${EXTERNAL_DNS_PROVIDER}" = "aws" ]; then
			echo_title "Register public dns ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} in route53"
		
			# Register in Route53 IP addresses point in public IP
			echo ${PUBLIC_ROUTE53_REGISTER} | jq --arg HOSTNAME "${MASTERKUBE}.${PUBLIC_DOMAIN_NAME}" '.Changes[0].ResourceRecordSet.Name = $HOSTNAME' > ${TARGET_CONFIG_LOCATION}/route53-public.json
			aws route53 change-resource-record-sets --profile ${AWS_ROUTE53_PROFILE} \
				--hosted-zone-id ${AWS_ROUTE53_PUBLIC_ZONE_ID} \
				--change-batch file://${TARGET_CONFIG_LOCATION}/route53-public.json > /dev/null

		elif [ "${EXTERNAL_DNS_PROVIDER}" = "godaddy" ]; then
			echo_title "Register public dns ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} in godaddy: ${GODADDY_REGISTER}"

			# Register in godaddy IP addresses point in public IP
			curl -s -X PUT "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/A/${MASTERKUBE}" \
				-H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
				-H "Content-Type: application/json" \
				-d "${GODADDY_REGISTER}"

			cat > ${TARGET_CONFIG_LOCATION}/godaddy-public.json <<EOF
			{
				"zone": "${PUBLIC_DOMAIN_NAME}",
				"type": "${RECORDTYPE}",
				"name": "${MASTERKUBE}",
				"record": ${GODADDY_REGISTER}
			}
EOF

		elif [ "${EXTERNAL_DNS_PROVIDER}" = "designate" ]; then
			echo_title "Register public dns ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} in designate"

			# Register in designate IP addresses point in public IP
			DNS_ENTRY=$(openstack recordset create -f json --ttl 60 --type ${RECORDTYPE} ${RECORDS[@]} "${PUBLIC_DOMAIN_NAME}." ${MASTERKUBE} 2>/dev/null | jq -r '.id // ""')

			cat > ${TARGET_CONFIG_LOCATION}/designate-public.json <<EOF
			{
				"id": "${DNS_ENTRY}",
				"zone_id": "${OS_PUBLIC_DNS_ZONEID}",
				"name": "${MASTERKUBE}",
				"record": "${DESIGNATE_REGISTER[@]}"
			}
EOF
		elif [ "${EXTERNAL_DNS_PROVIDER}" = "rfc2136" ]; then
			echo_title "Register public dns ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} in bind9"
			cat > ${TARGET_CONFIG_LOCATION}/rfc2136-public.cmd <<EOF
server ${BIND9_HOST} ${BIND9_PORT}
update add ${MASTERKUBE}.${PUBLIC_DOMAIN_NAME} 60 ${RECORDTYPE} ${DESIGNATE_REGISTER[@]}
send
EOF

			cat ${TARGET_CONFIG_LOCATION}/rfc2136-public.cmd | nsupdate -k ${BIND9_RNDCKEY}
		fi
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_etcd() {
	if [ "${HA_CLUSTER}" = "true" ]; then
		if [ "${EXTERNAL_ETCD}" = "true" ]; then
			echo_title "Created etcd cluster: ${CLUSTER_NODES}"

			prepare-etcd.sh --node-group=${NODEGROUP_NAME} \
				--cluster-nodes="${CLUSTER_NODES}" \
				--target-location="${TARGET_CLUSTER_LOCATION}" ${SILENT}

			for INDEX in $(seq 1 ${CONTROLNODES})
			do
				if [ ! -f ${TARGET_CONFIG_LOCATION}/etdc-0${INDEX}-prepared ]; then
	                INDEX=$((${INDEX} + ${CONTROLNODE_INDEX} - 1))
					IPADDR="${PRIVATE_ADDR_IPS[${INDEX}]}"

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
	fi

	cat >> ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
export CLUSTER_NODES=${CLUSTER_NODES}
export CONTROL_PLANE_ENDPOINT=${CONTROL_PLANE_ENDPOINT}
export LOAD_BALANCER_IP=${LOAD_BALANCER_IP}
export FIRST_WORKER_NODE_IP=${FIRST_WORKER_NODE_IP}
EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_cluster() {
    local MASTER_IP=
echo_red_bold USE_ETC_HOSTS=${USE_ETC_HOSTS}
	CERT_SANS=$(collect_cert_sans "${LOAD_BALANCER_IP}" "${CLUSTER_NODES}" "${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}")

	for INDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
	do
		MASTERKUBE_NODE=$(get_vm_name ${INDEX})
        NODEINDEX=$((INDEX - ${CONTROLNODE_INDEX}))
		VMUUID=$(get_vmuuid ${MASTERKUBE_NODE})
		IPADDR=$(get_ssh_ip ${INDEX})

		if [ -f ${TARGET_CONFIG_LOCATION}/node-0${INDEX}-prepared ]; then
			echo_title "Already prepared VM ${MASTERKUBE_NODE}"
		else
			echo_title "Prepare VM ${MASTERKUBE_NODE}, index=${INDEX}, UUID=${VMUUID} with IP:${IPADDR}"

			if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
				create_nginx_gateway
			elif [ ${INDEX} = ${CONTROLNODE_INDEX} ]; then
				# Start create first master node
				echo_blue_bold "Start control plane ${MASTERKUBE_NODE} index=${INDEX}, kubernetes version=${KUBERNETES_VERSION}"

				MASTER_IP=${IPADDR}:${APISERVER_ADVERTISE_PORT}

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo create-cluster.sh ${TRACE_ARGS} \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--advertise-port=${APISERVER_ADVERTISE_PORT} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--vm-uuid=${VMUUID} \
					--region=${REGION} \
					--zone=${ZONEID} \
					--max-pods=${MAX_PODS} \
					--allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
					--container-runtime=${CONTAINER_ENGINE} \
					--use-external-etcd=${EXTERNAL_ETCD} \
					--node-group=${NODEGROUP_NAME} \
					--node-index=${INDEX} \
					--cluster-nodes="${CLUSTER_NODES}" \
					--load-balancer-ip=${LOAD_BALANCER_IP} \
					--control-plane-endpoint="${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}:${LOAD_BALANCER_IP}" \
					--use-etc-hosts=${USE_ETC_HOSTS} \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--tls-san="${CERT_SANS}" \
					--ha-cluster=${HA_CLUSTER} \
					--cni-plugin=${CNI_PLUGIN} \
					--net-if=${PRIVATE_NET_INF} \
					--kubernetes-version="${KUBERNETES_VERSION}" ${SILENT}

				create_nlb_member ${INDEX}

				eval scp ${SCP_OPTIONS} ${KUBERNETES_USER}@${IPADDR}:/etc/cluster/* ${TARGET_CLUSTER_LOCATION}/ ${SILENT}

				wait_nlb_ready

				echo_blue_bold "Master ${MASTERKUBE_NODE} started, master-ip=${MASTER_IP}"

			elif [ ${INDEX} -lt $((WORKERNODE_INDEX)) ]; then
				# Start control-plane join master node
				echo_blue_bold "Join control-plane ${MASTERKUBE_NODE} instance master node, kubernetes version=${KUBERNETES_VERSION}"

				eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/* ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh ${TRACE_ARGS} \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--kubernetes-version="${KUBERNETES_VERSION}" \
					--container-runtime=${CONTAINER_ENGINE} \
					--cni-plugin=${CNI_PLUGIN} \
					--region=${REGION} \
					--zone=${ZONEID} \
					--max-pods=${MAX_PODS} \
					--vm-uuid=${VMUUID} \
					--allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
					--use-etc-hosts=${USE_ETC_HOSTS} \
					--use-external-etcd=${EXTERNAL_ETCD} \
					--node-group=${NODEGROUP_NAME} \
					--node-index=${NODEINDEX} \
					--use-load-balancer=${USE_LOADBALANCER} \
					--control-plane-endpoint="${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}:${LOAD_BALANCER_IP}" \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--tls-san="${CERT_SANS}" \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--cluster-nodes="${CLUSTER_NODES}" \
					--net-if=${PRIVATE_NET_INF} \
					--join-master="${MASTER_IP}" \
					--control-plane=true ${SILENT}

					create_nlb_member ${INDEX}
			else
				# Start join worker node
				echo_blue_bold "Join node ${MASTERKUBE_NODE} instance worker node, kubernetes version=${KUBERNETES_VERSION}"

				eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/* ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh ${TRACE_ARGS} \
					--plateform=${PLATEFORM} \
					--cloud-provider=${CLOUD_PROVIDER} \
					--k8s-distribution=${KUBERNETES_DISTRO} \
					--kubernetes-version="${KUBERNETES_VERSION}" \
					--container-runtime=${CONTAINER_ENGINE} \
					--cni-plugin=${CNI_PLUGIN} \
					--region=${REGION} \
					--zone=${ZONEID} \
					--max-pods=${MAX_PODS} \
					--vm-uuid=${VMUUID} \
					--use-etc-hosts=${USE_ETC_HOSTS} \
					--use-external-etcd=${EXTERNAL_ETCD} \
					--node-group=${NODEGROUP_NAME} \
					--node-index=${NODEINDEX} \
					--join-master="${MASTER_IP}" \
					--use-load-balancer=${USE_LOADBALANCER} \
					--control-plane-endpoint="${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}:${LOAD_BALANCER_IP}" \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--tls-san="${CERT_SANS}" \
					--etcd-endpoint="${ETCD_ENDPOINT}" \
					--net-if=${PRIVATE_NET_INF} \
					--cluster-nodes="${CLUSTER_NODES}" ${SILENT}
			fi

			echo ${MASTERKUBE_NODE} > ${TARGET_CONFIG_LOCATION}/node-0${INDEX}-prepared
		fi

		echo_separator
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_load_balancers() {
	echo -n
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function unregister_dns() {
	local FILE=

    # Delete DNS entries
    for FILE in ${TARGET_CONFIG_LOCATION}/route53-*.json
    do
        if [ -f ${FILE} ]; then
			local DNS=$(cat ${FILE} | jq '.Changes[0].Action = "DELETE"')
            local DNSNAME=$(echo ${DNS} | jq -r '.Changes[0].ResourceRecordSet.Name')
			local ZONEID=

			echo ${DNS} | jq . > ${FILE}

			echo_blue_bold "Delete DNS entry: ${DNSNAME} in route53"
			if [[ "${DNSNAME}" == *.${PUBLIC_DOMAIN_NAME} ]]; then
				ZONEID=${AWS_ROUTE53_PUBLIC_ZONE_ID}
			else
				ZONEID=${AWS_ROUTE53_PRIVATE_ZONE_ID}
			fi

			aws route53 change-resource-record-sets \
				--profile ${AWS_ROUTE53_PROFILE} \
				--region ${AWS_REGION} \
				--hosted-zone-id ${ZONEID} \
				--change-batch file://${FILE} &> /dev/null || true

            delete_host "${DNSNAME}"
        fi
    done

	# Delete DNS entries
	for FILE in ${TARGET_CONFIG_LOCATION}/designate-*.json
	do
        if [ -f ${FILE} ]; then
			local DNS_ENTRY_ID=$(cat ${FILE} | jq -r '.id // ""')
			local DNSNAME=$(cat ${FILE} | jq -r '.name // ""')
			local ZONEID=$(cat ${FILE} | jq -r '.zone_id // ""')

			if [ -n "${DNS_ENTRY_ID}" ]; then
				echo_blue_bold "Delete DNS entry: ${DNSNAME} in designate"
				openstack recordset delete ${ZONEID} ${DNS_ENTRY_ID} &>/dev/null || true
				rm -f ${FILE}
			fi
		fi
	done

	# Delete DNS entries
	for FILE in ${TARGET_CONFIG_LOCATION}/godaddy-*.json
	do
        if [ -f ${FILE} ]; then
			local TYPE=$(cat ${FILE} | jq -r '.type // ""')
			local NAME=$(cat ${FILE} | jq -r '.name // ""')
			local ZONE=$(cat ${FILE} | jq -r '.zone // ""')

			if [ -n "${TYPE}" ]; then
				echo_blue_bold "Delete DNS entry: ${NAME} in godaddy"
				curl -s -X DELETE -H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
					"https://api.godaddy.com/v1/domains/${ZONE}/records/${TYPE}/${NAME}" &> /dev/null
			fi
		fi
	done

    # Delete DNS entries
    for FILE in ${TARGET_CONFIG_LOCATION}/rfc2136-*.cmd
	do
        if [ -f ${FILE} ]; then
			cat ${FILE} | sed 's/add/delete/g' | nsupdate -k ${BIND9_RNDCKEY} 2> /dev/null || true
		fi
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_config() {
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

	if [[ -n "${AWS_ACCESSKEY}" && -n "${AWS_SECRETKEY}" ]] || [ "${PLATEFORM}" == "aws" ]; then
		echo_title "Create ${TARGET_CONFIG_LOCATION}/image-credential-provider-config.json"
		echo $(eval "cat <<EOF
	$(<${PWD}/templates/setup/image-credential-provider-config.json)
EOF") | jq . | tee /dev/stderr > ${TARGET_CONFIG_LOCATION}/image-credential-provider-config.json

		IMAGE_CREDENTIALS=$(cat "${TARGET_CONFIG_LOCATION}/image-credential-provider-config.json")
	else
		IMAGE_CREDENTIALS='{}'
	fi

	echo_title "Create ${TARGET_CONFIG_LOCATION}/provider.json"

	echo $(eval "cat <<EOF
	$(<${PWD}/templates/setup/${PLATEFORM}/provider.json)
EOF") | jq . | tee /dev/stderr > ${TARGET_CONFIG_LOCATION}/provider.json

	echo_title "Create ${TARGET_CONFIG_LOCATION}/autoscaler.json"

	echo $(eval "cat <<EOF
	$(<${PWD}/templates/setup/${PLATEFORM}/autoscaler.json)
EOF") | jq --argjson IMAGE_CREDENTIALS "${IMAGE_CREDENTIALS}" '. += $IMAGE_CREDENTIALS' | tee /dev/stderr > ${TARGET_CONFIG_LOCATION}/autoscaler.json
}
