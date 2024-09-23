CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl openstack packer"

REGION=${OS_REGION_NAME}
ZONEID=${OS_ZONE_NAME}
PUBLIC_NODE_IP=NONE
PUBLIC_VIP_ADDRESS=
USE_CERT_SELFSIGNED=YES
SEED_ARCH=amd64
NLB_POOLS=()
NLB_LISTENERS=()
NLB_ID=

source ${PLATEFORMDEFS}

#===========================================================================================================================================
#
#===========================================================================================================================================
function usage() {
	common_usage
	cat <<EOF
### Flags ${PLATEFORM} plateform specific

  # Flags to configure nfs client provisionner
--nfs-server-adress=<value>                    # The NFS server address, default: ${NFS_SERVER_ADDRESS}
--nfs-server-mount=<value>                     # The NFS server mount path, default: ${NFS_SERVER_PATH}
--nfs-storage-class=<value>                    # The storage class name to use, default: ${NFS_STORAGE_CLASS}

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

  # Flags in ha mode only
--use-nlb=[none|nginx|cloud|keepalived]        # Use plateform load balancer in public AZ

  # Flags to configure network in ${PLATEFORM}
--vm-private-network=<value>                   # Override the name of the private network in ${PLATEFORM}, default: ${VC_NETWORK_PRIVATE}
--vm-public-network=<value>                    # Override the name of the public network in ${PLATEFORM}, empty for none second interface, default: ${VC_NETWORK_PUBLIC}
--no-dhcp-autoscaled-node                      # Autoscaled node don't use DHCP, default: ${SCALEDNODES_DHCP}
--dhcp-autoscaled-node                         # Autoscaled node use DHCP, default: ${SCALEDNODES_DHCP}
--private-domain=<value>                       # Override the domain name, default: ${PRIVATE_DOMAIN_NAME}

--prefer-ssh-publicip                          # Allow to SSH on publicip when available, default: ${PREFER_SSH_PUBLICIP}
--external-security-group=<name>               # Specify the public security group ID for VM, default: ${EXTERNAL_SECURITY_GROUP}
--internal-security-group=<name>               # Specify the private security group ID for VM, default: ${INTERNAL_SECURITY_GROUP}
--internet-facing                              # Expose the cluster on internet, default: ${EXPOSE_PUBLIC_CLUSTER}

  # Flags to expose nodes in public AZ with public IP
--control-plane-public                         # Control plane are exposed to public, default: ${CONTROLPLANE_USE_PUBLICIP}
--worker-node-public                           # Worker nodes are exposed to public, default: ${WORKERNODE_USE_PUBLICIP}

EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function parse_arguments() {
	OPTIONS+=(
		"control-plane-public"
		"create-nginx-apigateway"
		"external-security-group:"
		"internal-security-group:"
		"internet-facing"
		"nfs-server-adress:"
		"nfs-server-mount:"
		"nfs-storage-class:"
		"prefer-ssh-publicip"
		"private-domain:"
		"use-nlb:"
		"vm-private-network:"
		"vm-public-network:"
		"worker-node-public"
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
	### Bind9 space
		--use-named-server)
			USE_BIND9_SERVER="true"
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
		--prefer-ssh-publicip)
			PREFER_SSH_PUBLICIP=YES;
			shift 1
			;;
		--private-domain)
			PRIVATE_DOMAIN_NAME="$2"
			shift 2
			;;
		--use-nlb)
			case $2 in
				none|keepalived|cloud|nginx)
					USE_NLB="$2"
					;;
				*)
					echo_red_bold "Load balancer of type: $2 is not supported"
					exit 1
					;;
			esac
			shift 2
			;;
		--internal-security-group)
			INTERNAL_SECURITY_GROUP=$2
			shift 2
			;;
		--external-security-group)
			EXTERNAL_SECURITY_GROUP=$2
			shift 2
			;;
		--internet-facing)
			EXPOSE_PUBLIC_CLUSTER=true
			shift 1
			;;
		--control-plane-public)
			CONTROLPLANE_USE_PUBLICIP=true
			shift 1
			;;
		--worker-node-public)
			WORKERNODE_USE_PUBLICIP=true
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

	parsed_arguments
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function parsed_arguments() {
	VPC_PUBLIC_SUBNET_IDS=(${VC_NETWORK_PUBLIC})
	VPC_PRIVATE_SUBNET_IDS=(${VC_NETWORK_PRIVATE})

	if [ -z "${PRIVATE_IP}" ]; then
		local SUBNET=$(openstack subnet show -f json $(openstack network show ${VC_NETWORK_PRIVATE} -f json | jq -r '.subnets[0]//""'))
		local CIDR=$(echo ${SUBNET} | jq -r '.cidr' | cut -d '/' -f 1)

		PRIVATE_IP=$(cut -d '/' -f 1 <<< "${CIDR}")
		PRIVATE_IP="${PRIVATE_IP%.*}.${PRIVATE_IP_START}"
		PRIVATE_DNS=$(echo ${SUBNET} | jq -r '.dns_nameservers|first//""' | cut -d '/' -f 1)

		PRIVATE_MASK_CIDR=$(cut -d '/' -f 2 <<< "${CIDR}")
		PRIVATE_NETMASK=$(cidr_to_netmask ${PRIVATE_MASK_CIDR})
	fi
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
function plateform_create_vm() {
	local INDEX=$1
	local PUBLIC_IP=$2
	local NODE_IP=$3
	local SECURITY_GROUP=$(get_security_group ${INDEX})
	local FLOATING_IP=$(vm_use_floating_ip ${INDEX} ${USE_NLB})
	local MACHINE_TYPE=
	local MASTERKUBE_NODE=
	local VMHOST=
	local NIC_OPTIONS=

	MACHINE_TYPE=$(get_machine_type ${INDEX})
	MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})

	if [ -z "${MASTERKUBE_NODE_UUID}" ]; then
		NETWORK_ID=$(openstack network show -f json ${VC_NETWORK_PRIVATE} | jq -r '.id//""')

		# Cloud init user-data
		cat > ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.yaml <<EOF
#cloud-config
package_update: ${UPDATE_PACKAGE}
package_upgrade: ${UPDATE_PACKAGE}
timezone: ${TZ}
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false
EOF

		if [ -f "${TARGET_CONFIG_LOCATION}/credential.yaml" ]; then
			cat >> ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.yaml <<EOF
write_files:
- encoding: gzip+base64
  content: $(cat ${TARGET_CONFIG_LOCATION}/credential.yaml | gzip -c9 | base64 -w 0)
  owner: root:root
  path: ${IMAGE_CREDENTIALS_CONFIG}
  permissions: '0644'
runcmd:
- hostnamectl set-hostname ${MASTERKUBE_NODE}
EOF
		fi

		echo_line
		echo_blue_bold "Launch ${MASTERKUBE_NODE} index: ${INDEX} with ${TARGET_IMAGE} and flavor=${MACHINE_TYPE} TARGET_IMAGE=${TARGET_IMAGE} MASTERKUBE_NODE=${MASTERKUBE_NODE}"
		echo_line

		if [ ${FLOATING_IP} == "true" ]; then
			if [ ${PUBLIC_IP} != "DHCP" ]; then
				FLOATING_IP_NAME=$(openstack floating ip show ${PUBLIC_IP} -f json 2>/dev/null | jq -r '.name')

				if [ -z "${FLOATING_IP_NAME}" ]; then
					echo_blue_bold "Create floating ip: ${PUBLIC_IP} for ${MASTERKUBE_NODE} on network ${VC_NETWORK_PUBLIC}"
					PUBLIC_IP=$(openstack floating ip create --tag ${MASTERKUBE_NODE} --floating-ip-address ${PUBLIC_IP} -f json ${VC_NETWORK_PUBLIC} | jq -r '.floating_ip_address // ""')
				else
					echo_blue_bold "Use floating ip: ${PUBLIC_IP} for ${MASTERKUBE_NODE} on network ${VC_NETWORK_PUBLIC}"
				fi
			else
				PUBLIC_IP=$(openstack floating ip list --tags ${MASTERKUBE_NODE} -f json 2>/dev/null | jq -r '.[0]."Floating IP Address"//""')

				if [ -z "${PUBLIC_IP}" ]; then
					PUBLIC_IP=$(openstack floating ip create --tag ${MASTERKUBE_NODE} -f json ${VC_NETWORK_PUBLIC} | jq -r '.floating_ip_address // ""')

					echo_blue_bold "Create floating ip: ${PUBLIC_IP} for ${MASTERKUBE_NODE} on network ${VC_NETWORK_PUBLIC}"
				else
					echo_blue_bold "Use floating ip: ${PUBLIC_IP} for ${MASTERKUBE_NODE} on network ${VC_NETWORK_PUBLIC}"
				fi
			fi
		fi

		if [ ${NODE_IP} == "AUTO" ] || [ ${NODE_IP} == "DHCP" ]; then
			NIC_OPTIONS="net-id=${NETWORK_ID}"
		else
			NIC_OPTIONS="net-id=${NETWORK_ID},v4-fixed-ip=${NODE_IP}"
		fi

		LOCALIP=$(openstack server create \
			--flavor "${MACHINE_TYPE}" \
			--image "${TARGET_IMAGE}" \
			--nic "${NIC_OPTIONS}" \
			--security-group "${SECURITY_GROUP}" \
			--key-name "${SSH_KEYNAME}" \
			--user-data ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.yaml \
			--wait \
			-f json ${MASTERKUBE_NODE} 2>/dev/null | jq -r --arg NETWORK ${VC_NETWORK_PRIVATE}  '.addresses|.[$NETWORK][0]')

		if [ ${FLOATING_IP} == "true" ]; then
			eval openstack server add floating ip ${MASTERKUBE_NODE} ${PUBLIC_IP} ${SILENT}
		fi
	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"

		LOCALIP=$(openstack server show -f json ${MASTERKUBE_NODE} 2>/dev/null | jq -r --arg NETWORK ${VC_NETWORK_PRIVATE} '.addresses|.[$NETWORK][0]')

		if [ ${FLOATING_IP} == "true" ]; then
			PUBLIC_IP=$(openstack floating ip list --fixed-ip-address ${LOCALIP} -f json | jq -r '.[0]."Floating IP Address"')
		fi
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_info_vm() {
	local INDEX=$1
	local PUBLIC_IP=$2
	local NODE_IP=$3
	local FLOATING_IP=$(vm_use_floating_ip ${INDEX} ${USE_NLB})
	local MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	local MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})
	local SUFFIX=$(named_index_suffix $1)
	local PRIVATE_IP=$(openstack server show -f json ${MASTERKUBE_NODE} 2>/dev/null | jq -r --arg NETWORK ${VC_NETWORK_PRIVATE} '.addresses|.[$NETWORK][0]')

	if [ ${FLOATING_IP} == "true" ]; then
		PUBLIC_IP=$(openstack floating ip list --fixed-ip-address ${PRIVATE_IP} -f json | jq -r '.[0]."Floating IP Address"')
	else
		PUBLIC_IP=${PRIVATE_IP}
	fi

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
	local FLOATING_ID=

    if [ "$(openstack server show "${VMNAME}" 2>/dev/null)" ]; then
        echo_blue_bold "Delete VM: ${VMNAME}"
		openstack server delete --force --wait ${VMNAME} &>/dev/null

		FLOATING_ID=$(openstack floating ip list --network ${VC_NETWORK_PUBLIC} --tags ${VMNAME} -f json 2>/dev/null | jq -r '.[0].ID // ""')

		if [ -n "${FLOATING_ID}" ]; then
			echo_blue_bold "Delete floating ip: ${FLOATING_ID} for ${VMNAME} on network ${VC_NETWORK_PUBLIC}"
			openstack floating ip delete ${FLOATING_ID} &>/dev/null
		fi
	fi

    delete_host "${VMNAME}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_load_balancer() {
	local NAME=$1
	local NBL=$(openstack loadbalancer show ${NAME} -f json 2>/dev/null || echo '{}')

	if [ -n "$(echo ${NBL} | jq -r '.id//""')" ]; then
		echo_blue_bold "Delete load balancer: ${NAME}"
		openstack loadbalancer delete --cascade --wait ${NAME} &>/dev/null

		local PORTID=$(echo ${NBL} | jq -r '.vip_port_id//""')

		echo_blue_bold "Delete port: ${PORTID}"

		openstack port delete ${PORTID} &>/dev/null || :
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_load_balancers() {
	delete_load_balancer "nlb-external-${MASTERKUBE}"
	delete_load_balancer "nlb-internal-${MASTERKUBE}"

	FLOATING_ID=$(openstack floating ip list --network ${VC_NETWORK_PUBLIC} --tags nlb-internal-${MASTERKUBE} -f json 2>/dev/null | jq -r '.[0].ID // ""')

	if [ -n "${FLOATING_ID}" ]; then
		echo_blue_bold "Delete floating ip: ${FLOATING_ID} for nlb-internal-${MASTERKUBE} on network ${VC_NETWORK_PUBLIC}"
		openstack floating ip delete ${FLOATING_ID}
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
    PROVIDER_AUTOSCALER_CONFIG=$(cat ${TARGET_CONFIG_LOCATION}/provider.json)

    echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE "${TARGET_IMAGE}" '.template-name = $TARGET_IMAGE' > ${TARGET_CONFIG_LOCATION}/provider.json
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vmuuid() {
    local VMNAME=$1
    
	openstack server show -f json "${VMNAME}" 2>/dev/null| jq -r '.id // ""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_image_uuid() {
	local TARGET_IMAGE=$1

	openstack image list --all -f json | jq -r --arg TARGET_IMAGE ${TARGET_IMAGE} '.[]|select(.Name == $TARGET_IMAGE)|.ID//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_net_type() {
	local TYPE=$(openstack network show $1 -f json 2>/dev/stderr | jq -r '."router:external"')

	if [ -n "${TYPE}" ]; then
		if [ ${TYPE} == "true" ]; then
			echo -n "public"
		elif [ ${TYPE} == "false" ]; then
			echo -n "private"
		else
			echo -n ""
		fi
	else
		echo -n ""
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_ssh() {
	KEYEXISTS=$(openstack keypair show -f json "${SSH_KEYNAME}" 2>/dev/null | jq -r '.id // ""')

	if [ -z ${KEYEXISTS} ]; then
		echo_blue_bold "SSH Public key doesn't exist"
		eval openstack keypair create --public-key ${SSH_PUBLIC_KEY} --type ssh ${SSH_KEYNAME} ${SILENT}
	else
		echo_blue_bold "SSH Public key already exists"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_plateform() {
	if [ ${USE_NLB} = "cloud" ] && [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
		PUBLIC_VIP_ADDRESS="${NODE_IP}"
		NODE_IP=$(nextip ${NODE_IP} false)
	fi

	prepare_node_indexes

	# Check if dns service is present
	if [ "${USE_BIND9_SERVER}" = "true" ]; then
		find_private_dns_provider
		find_public_dns_provider
	else
		if [ -n "$(openstack service show -f json dns 2>/dev/null | jq -r '.id // ""')" ]; then
			if [ -n "${PUBLIC_DOMAIN_NAME}" ] && [ "${PUBLIC_DOMAIN_NAME}" != "${PRIVATE_DOMAIN_NAME}" ]; then
				OS_PUBLIC_DNS_ZONEID=$(openstack zone show -f json "${PUBLIC_DOMAIN_NAME}." 2>/dev/null | jq -r '.id // ""')

				if [ -n "${OS_PUBLIC_DNS_ZONEID}" ]; then
					echo_blue_bold "Found PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME} handled by designate: ${OS_PUBLIC_DNS_ZONEID}"
					echo_red_bold "Designate will be used to register public domain hosts"
					EXTERNAL_DNS_PROVIDER=designate
					CERT_SELFSIGNED=${USE_CERT_SELFSIGNED}
				fi
			fi
		fi

		if [ -z "${OS_PUBLIC_DNS_ZONEID}" ]; then
			find_public_dns_provider
		fi
	fi

	echo_title "Prepare flavors"

	local FLAVORS=$(cat ${PWD}/templates/setup/${PLATEFORM}/machines.json)
	local FLAVORS_KEYS=$(echo ${FLAVORS} | jq -r 'keys_unsorted | .[]')
	local FLAVORS_INSTALLED=$(openstack flavor list -f json)

	local MEMSIZE=
	local NUM_VCPUS=
	local DISK_SIZE=

	for SECURITY_GROUP in ${EXTERNAL_SECURITY_GROUP} ${INTERNAL_SECURITY_GROUP}
	do
		SECURITY_GROUP_ID=$(openstack security group show -f json ${SECURITY_GROUP} 2>/dev/null | jq -r '.id')

		if [ -z "${SECURITY_GROUP_ID}" ]; then
			echo_red_bold "The security group: ${SECURITY_GROUP} doesn't exists"
			exit 1
		fi
	done

	for FLAVOR in ${FLAVORS_KEYS}
	do
		if [ -z "$(echo "${FLAVORS_INSTALLED}" | jq -r --arg NAME "${FLAVOR}" '.[]|select(.Name == $NAME)|.ID')" ]; then
			read MEMSIZE NUM_VCPUS DISK_SIZE <<<"$(echo ${FLAVORS} | jq -r --arg FLAVOR ${FLAVOR} '.[$FLAVOR]|.memsize,.vcpus,.disksize' | tr '\n' ' ')"

			echo_blue_bold "Create flavor: ${FLAVOR}, disk: ${DISK_SIZE}MB memory: ${MEMSIZE} vcpus: ${NUM_VCPUS}"
			eval openstack flavor create --disk $((DISK_SIZE / 1024)) --vcpus ${NUM_VCPUS} --ram ${MEMSIZE} \
				--public --property "hw:cpu_mode=host-passthrough" --property "hw_rng:allowed=true" \
				--id ${FLAVOR} ${FLAVOR} ${SILENT}
		else
			echo_blue_bold "Flavor: ${FLAVOR} already exists"
		fi
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_dns() {
	if [ "${USE_BIND9_SERVER}" != "true" ]; then
		if [ "${PUBLIC_DOMAIN_NAME}" == "${PRIVATE_DOMAIN_NAME}" ] && [ "${EXTERNAL_DNS_PROVIDER}" != "none" ]; then
			echo_red_bold "Use DNS provider: ${EXTERNAL_DNS_PROVIDER} for private domain"
			return
		fi

		if [ -n "$(openstack service show -f json dns 2>/dev/null | jq -r '.id // ""')" ]; then
			OS_PRIVATE_DNS_ZONEID=$(openstack zone show -f json "${PRIVATE_DOMAIN_NAME}." 2>/dev/null | jq -r '.id // ""')

			if [ -z "${OS_PRIVATE_DNS_ZONEID}" ]; then
				echo_blue_bold "Register zone: ${PRIVATE_DOMAIN_NAME}. with email: ${CERT_EMAIL}"
				OS_PRIVATE_DNS_ZONEID=$(openstack zone create -f json --email ${CERT_EMAIL} --ttl 60 "${PRIVATE_DOMAIN_NAME}." 2>/dev/null | jq -r '.id // ""')

				echo_blue_dot_title "Wait zone ${PRIVATE_DOMAIN_NAME} to be ready"
				while [ "$(openstack zone show ${PRIVATE_DOMAIN_NAME}. -f json | jq -r '.status//""')" != "ACTIVE" ];
				do
					echo_blue_dot
					sleep 1
				done
				echo
			else
				echo_blue_bold "Zone: ${PRIVATE_DOMAIN_NAME}. already registered with ID: ${OS_PRIVATE_DNS_ZONEID}"
			fi

			if [ -n "${OS_PRIVATE_DNS_ZONEID}" ]; then
				USE_ETC_HOSTS=false
			fi
		fi
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_security_group() {
	local INDEX=$1
	local SG=${INTERNAL_SECURITY_GROUP}
	
	if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
		if [ "${EXPOSE_PUBLIC_CLUSTER}" == "true" ]; then
			SG=${EXTERNAL_SECURITY_GROUP}
		fi
	elif [ "${USE_NLB}" == "none" ]; then
		if [ ${INDEX} -lt ${WORKERNODE_INDEX} ] && [ "${CONTROLPLANE_USE_PUBLICIP}" == "true" ]; then
			SG=${EXTERNAL_SECURITY_GROUP}
		elif [ ${INDEX} -ge ${WORKERNODE_INDEX} ] && [ "${WORKERNODE_USE_PUBLICIP}" == "true" ]; then
			SG=${EXTERNAL_SECURITY_GROUP}
		fi
	fi

	echo -n "${SG}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_member_in_nlb() {
	local NLB_NAME=$1
	local NLB_PORTS=$2
	local NAME=$3
	local ADDR=$4
	local NLB_SUBNET=$(openstack network show ${VC_NETWORK_PRIVATE} -f json | jq -r '.subnets[0]//""')

	IFS=, read -a NLB_PORTS <<< "${NLB_PORTS}"

	for NLB_PORT in ${NLB_PORTS[@]}
	do
		POOL_ID=$(openstack loadbalancer pool show -f json ${NLB_NAME}-pool-${NLB_PORT} | jq -r '.id//""')

		eval openstack loadbalancer member create \
			--name ${NAME}-${NLB_PORT} \
			--subnet-id ${NLB_SUBNET} \
			--address ${ADDR} \
			--protocol-port ${NLB_PORT} ${POOL_ID} ${SILENT}
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function not_create_plateform_nlb_member() {
	local NAME=$1
	local ADDR=$2

	create_member_in_nlb "nlb-internal-${MASTERKUBE}" "${LOAD_BALANCER_PORT}" ${NAME} ${ADDR}

	if [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
		if [ "${CONTROLPLANE_USE_PUBLICIP}" == "true" ]; then
			create_member_in_nlb "nlb-external-${MASTERKUBE}" "${LOAD_BALANCER_PORT}" ${NAME} ${ADDR}
		else
			create_member_in_nlb "nlb-external-${MASTERKUBE}" "${EXPOSE_PUBLIC_PORTS}" ${NAME} ${ADDR}
		fi
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_nlb_active() {
	local NLB_NAME=$1

	while :
	do
		if [ $(openstack loadbalancer show -f json ${NLB_NAME} | jq -r '.provisioning_status') = "ACTIVE" ]; then
			break
		fi
 
		sleep 5
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_nlb() {
	local NLB_NAME=$1
	local NLB_PUBLIC=$2
	local NLB_PORTS=$3
	local NLB_TYPE=$4
	local NLB_TARGETS=$5
	local NLB_VIP_ADDRESS=$6
	local NLB_FLOATING_IP=$7
	local NLB_PORT=
	local NBL_TARGET=
	local NLB_PROVIDER=
	local NLB_SUBNET=$(openstack network show ${VC_NETWORK_PRIVATE} -f json | jq -r '.subnets[0]//""')

	NLB_ID=$(openstack loadbalancer create --vip-address ${NLB_VIP_ADDRESS} --vip-network-id ${VC_NETWORK_PRIVATE} -f json --name ${NLB_NAME} | jq -r '.id//""')

	if [ -n "${NLB_ID}" ]; then
		IFS=,  read -a NLB_PORTS <<< "${NLB_PORTS}"
		IFS=,  read -a NLB_TARGETS <<< "${NLB_TARGETS}"

		wait_nlb_active ${NLB_NAME}

		NLB_PROVIDER=$(openstack loadbalancer show -f json ${NLB_NAME} | jq -r '.provider')

		if [ ${NLB_FLOATING_IP} = "YES" ]; then
			FLOATIP_ID=$(openstack floating ip create  --tag ${NLB_NAME} ${VC_NETWORK_PUBLIC} -f json  | jq -r '.floating_ip_address // ""')
			PORT_ID=$(openstack loadbalancer show -f json ${NLB_NAME} | jq -r '.vip_port_id')

			eval openstack floating ip set --port ${PORT_ID} ${FLOATIP_ID} ${SILENT}
		fi

		if [ -n ${NLB_ID} ]; then
			for NLB_PORT in ${NLB_PORTS[@]}
			do
				# Create load balancer listener
				LISTENER_ID=$(openstack loadbalancer listener create -f json \
					--name ${NLB_NAME}-listen-${NLB_PORT} \
					--protocol TCP \
					--protocol-port ${NLB_PORT} ${NLB_ID} | jq -r '.id')

				# Create load balancer pool
				POOL_ID=$(openstack loadbalancer pool create -f json \
					--name ${NLB_NAME}-pool-${NLB_PORT} \
					--protocol tcp \
					--lb-algorithm SOURCE_IP_PORT \
					--listener ${NLB_NAME}-listen-${NLB_PORT} | jq -r '.id')

				HEALTH_ID=$(openstack loadbalancer healthmonitor create \
					--name ${NLB_NAME}-health-${NLB_PORT} \
					--delay 15 \
					--max-retries 5 \
					--timeout 5 \
					--type TCP ${POOL_ID})

				# Append member
				for NLB_TARGET in ${NLB_TARGETS[@]}
				do
					IFS=: read NAME IP <<< "${NLB_TARGET}"
					eval openstack loadbalancer member create \
						--subnet-id ${NLB_SUBNET} \
						--address ${IP} \
						--protocol-port ${NLB_PORT} ${POOL_ID} ${SILENT}
				done
			done
		fi
	else
		echo_red_bold "Unable to create loadbalancer: ${NLB_NAME}"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_plateform_nlb() {
	local LOAD_BALANCER=
    local PRIVATE_NLB_DNS=
    local PUBLIC_NLB_DNS=
	local NLB_TARGETS=
	local VIP_ADDRESS=

	NLB_TARGETS=${CLUSTER_NODES}
	VIP_ADDRESS=${PRIVATE_ADDR_IPS[0]}

	echo_title "Create internal NLB ${MASTERKUBE} with target: ${NLB_TARGETS} at: ${VIP_ADDRESS}"

	create_nlb "nlb-internal-${MASTERKUBE}" false "${LOAD_BALANCER_PORT}" network "${NLB_TARGETS}" "${VIP_ADDRESS}" NO

	LOAD_BALANCER=$(openstack loadbalancer show -f json nlb-internal-${MASTERKUBE} 2>/dev/null)
	LOAD_BALANCER_IP=${echo "${LOAD_BALANCER}" | jq -r '.vip_address'}
	PRIVATE_NLB_DNS=${LOAD_BALANCER_IP}

	if [ ${EXPOSE_PUBLIC_CLUSTER} = "true" ]; then
		echo_title "Create external NLB ${MASTERKUBE} with target: ${NLB_TARGETS} at: ${PUBLIC_VIP_ADDRESS}"

		if [ ${CONTROLPLANE_USE_PUBLICIP} == "true" ]; then
			create_nlb "nlb-external-${MASTERKUBE}" true "${LOAD_BALANCER_PORT}" network "${NLB_TARGETS}" "${PUBLIC_VIP_ADDRESS}" "YES"
		else
			create_nlb "nlb-external-${MASTERKUBE}" true "${EXPOSE_PUBLIC_PORTS}" network "${NLB_TARGETS}" "${PUBLIC_VIP_ADDRESS}" "YES"
		fi

		LOAD_BALANCER=$(openstack loadbalancer show -f json nlb-external-${MASTERKUBE} 2>/dev/null)
		PUBLIC_NLB_DNS=$(openstack floating ip list --fixed-ip-address ${PUBLIC_VIP_ADDRESS} -f json | jq -r '.[0]."Floating IP Address"')
	else
		PUBLIC_NLB_DNS=${PRIVATE_NLB_DNS}
	fi

	register_nlb_dns A "${PRIVATE_NLB_DNS}" "${PUBLIC_NLB_DNS}" "" ""
}
