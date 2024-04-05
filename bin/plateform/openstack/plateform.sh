CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl openstack packer"
VC_NETWORK_PRIVATE="private"
VC_NETWORK_PUBLIC="public"
NGINX_MACHINE="k8s.tiny"
CONTROL_PLANE_MACHINE="k8s.small"
WORKER_NODE_MACHINE="k8s.medium"
AUTOSCALE_MACHINE="k8s.medium"
REGION=${OS_REGION_NAME}
ZONEID=${OS_ZONE_NAME}
PUBLIC_NODE_IP=NONE
PUBLIC_VIP_ADDRESS=
PRIVATE_VIP_ADDRESS=

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
--use-nlb                                      # Use plateform load balancer in public AZ

  # Flags to configure network in ${PLATEFORM}
--vm-private-network=<value>                   # Override the name of the private network in ${PLATEFORM}, default ${VC_NETWORK_PRIVATE}
--vm-public-network=<value>                    # Override the name of the public network in ${PLATEFORM}, empty for none second interface, default ${VC_NETWORK_PUBLIC}
--no-dhcp-autoscaled-node                      # Autoscaled node don't use DHCP, default ${SCALEDNODES_DHCP}
--private-domain=<value>                       # Override the domain name, default ${PRIVATE_DOMAIN_NAME}
--net-address=<value>                          # Override the IP of the kubernetes control plane node, default ${PRIVATE_IP}
--net-gateway=<value>                          # Override the IP gateway, default ${PRIVATE_GATEWAY}
--net-dns=<value>                              # Override the IP DNS, default ${PRIVATE_DNS}

--prefer-ssh-publicip                          # Allow to SSH on publicip when available, default ${PREFER_SSH_PUBLICIP}
--external-security-group=<name>               # Specify the public security group ID for VM, default ${EXTERNAL_SECURITY_GROUP}
--internal-security-group=<name>               # Specify the private security group ID for VM, default ${INTERNAL_SECURITY_GROUP}
--internet-facing                              # Expose the cluster on internet, default ${EXPOSE_PUBLIC_CLUSTER}--public-subnet-id=<subnetid,...>                # Specify the public subnet ID for created VM, default ${VPC_PUBLIC_SUBNET_ID}

  # Flags to expose nodes in public AZ with public IP
--control-plane-public                         # Control plane are hosted in public subnet with public IP, default ${CONTROLPLANE_USE_PUBLICIP}
--worker-node-public                           # Worker nodes are hosted in public subnet with public IP, default ${WORKERNODE_USE_PUBLICIP}

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
		"internet-facing"
		"control-plane-public"
		"worker-node-public"
		"use-nlb"
		"create-nginx-apigateway"
		"internal-security-group:"
		"external-security-group:"
		"prefer-ssh-publicip"
		"private-domain:"
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
		--prefer-ssh-publicip)
			PREFER_SSH_PUBLICIP=YES;
			shift 1
			;;
		--private-domain)
			PRIVATE_DOMAIN_NAME="$2"
			shift 2
			;;
		--use-nlb)
			USE_NLB=YES
			shift 1
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

	VPC_PUBLIC_SUBNET_IDS=(${VC_NETWORK_PUBLIC})
	VPC_PRIVATE_SUBNET_IDS=(${VC_NETWORK_PRIVATE})
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function vm_use_floating_ip() {
	local INDEX=$1

	if [ ${HA_CLUSTER} = "true" ]; then
		if [ ${USE_NLB} = "YES" ]; then
			echo -n false
		elif [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
			echo -n ${EXPOSE_PUBLIC_CLUSTER}
		elif [ ${INDEX} -lt ${WORKERNODE_INDEX} ]; then
			echo -n ${CONTROLPLANE_USE_PUBLICIP}
		else
			echo -n ${WORKERNODE_USE_PUBLICIP}
		fi
	elif [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
		echo -n ${EXPOSE_PUBLIC_CLUSTER}
	elif [ ${INDEX} -lt ${WORKERNODE_INDEX} ]; then
		echo -n ${CONTROLPLANE_USE_PUBLICIP}
	else
		echo -n ${WORKERNODE_USE_PUBLICIP}
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_create_vm() {
	local INDEX=$1
	local PUBLIC_IP=$2
	local NODE_IP=$3
	local SECURITY_GROUP=$(get_security_group ${INDEX})
	local FLOATING_IP=$(vm_use_floating_ip ${INDEX})
	local MACHINE_TYPE=
	local MASTERKUBE_NODE=
	local VMHOST=
	local DISK_SIZE=
	local NUM_VCPUS=
	local MEMSIZE=
	local NIC_OPTIONS=

	MACHINE_TYPE=$(get_machine_type ${INDEX})
	MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})

	if [ -z "${MASTERKUBE_NODE_UUID}" ]; then
		NETWORK_ID=$(openstack network show -f json private | jq -r '.id//""')

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
			PUBLIC_IP=$(openstack floating ip list --tags ${MASTERKUBE_NODE} -f json 2>/dev/null | jq -r '.[0]."Floating IP Address"//""')

			if [ -z "${PUBLIC_IP}" ]; then
				PUBLIC_IP=$(openstack floating ip create --tag ${MASTERKUBE_NODE} -f json ${VC_NETWORK_PUBLIC} | jq -r '.floating_ip_address // ""')

				echo_blue_bold "Create floating ip: ${PUBLIC_IP} for ${MASTERKUBE_NODE} on network ${VC_NETWORK_PUBLIC}"
			else
				echo_blue_bold "Use floating ip: ${PUBLIC_IP} for ${MASTERKUBE_NODE} on network ${VC_NETWORK_PUBLIC}"
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

		echo_title "Wait ssh ready on ${KUBERNETES_USER}@${LOCALIP}"
		wait_ssh_ready ${KUBERNETES_USER}@${LOCALIP}

		echo_title "Prepare ${MASTERKUBE_NODE} instance with IP:${LOCALIP}"
		eval scp ${SCP_OPTIONS} tools ${KUBERNETES_USER}@${LOCALIP}:~ ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${LOCALIP} mkdir -p /home/${KUBERNETES_USER}/cluster ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${LOCALIP} sudo chown -R root:adm /home/${KUBERNETES_USER}/tools ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${LOCALIP} sudo cp /home/${KUBERNETES_USER}/tools/* /usr/local/bin ${SILENT}
	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"

		LOCALIP=$(openstack server show -f json ${MASTERKUBE_NODE} 2/dev/null | jq -r --arg NETWORK ${VC_NETWORK_PRIVATE}  '.addresses|.[$NETWORK][0]')

		if [ ${FLOATING_IP} == "true" ]; then
			PUBLIC_IP=$(openstack floating ip list --fixed-ip-address ${LOCALIP} -f json | jq -r '.[0]."Floating IP Address"')
		fi
	fi

	PRIVATE_ADDR_IPS[${INDEX}]=${LOCALIP}
	PUBLIC_ADDR_IPS[${INDEX}]=${PUBLIC_IP}
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

	if [ -n "$(openstack loadbalancer show -f json ${NAME} 2>/dev/null | jq -r '.id')" ]; then
		echo_blue_bold "Delete load balancer: ${NAME}"
		openstack loadbalancer delete --cascade --wait ${NAME} &>/dev/null
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
		echo_grey "SSH Public key doesn't exist"
		eval openstack keypair create --public-key ${SSH_PUBLIC_KEY} --type ssh ${SSH_KEYNAME} ${SILENT}
	else
		echo_grey "SSH Public key already exists"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_plateform() {
	if [ ${USE_NLB} = "YES" ] && [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
		PUBLIC_VIP_ADDRESS="${NODE_IP}"
		NODE_IP=$(nextip ${NODE_IP})

		if [ "${USE_NGINX_GATEWAY}" = "YES" ]; then
			PRIVATE_VIP_ADDRESS="${NODE_IP}"
			NODE_IP=$(nextip ${NODE_IP})
		fi

	fi

	prepare_node_indexes

	# Check if dns service is present
	if [ -n "$(openstack service show -f json dns 2>/dev/null | jq -r '.id // ""')" ]; then
		if [ -n "${PUBLIC_DOMAIN_NAME}" ] && [ "${PUBLIC_DOMAIN_NAME}" != "${PRIVATE_DOMAIN_NAME}" ]; then
			OS_PUBLIC_DNS_ZONEID=$(openstack zone show -f json "${PUBLIC_DOMAIN_NAME}." 2>/dev/null | jq -r '.id // ""')

			if [ -n "${OS_PUBLIC_DNS_ZONEID}" ]; then
				echo_blue_bold "Found PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME} handled by designate: ${OS_PUBLIC_DNS_ZONEID}"
				EXTERNAL_DNS_PROVIDER=designate
			fi
		fi
	fi

	if [ -z "${OS_PUBLIC_DNS_ZONEID}" ]; then
		find_public_dns_provider
	fi

	echo_title "Prepare flavors"

	local FLAVORS=$(cat ${PWD}/templates/setup/${PLATEFORM}/machines.json)
	local FLAVORS_KEYS=$(echo ${FLAVORS} | jq -r 'keys_unsorted | .[]')
	local FLAVORS_INSTALLED=$(openstack flavor list -f json)

	local MEMSIZE=
	local NUM_VCPUS=
	local DISK_SIZE=

	for FLAVOR in ${FLAVORS_KEYS}
	do
		if [ -z "$(echo "${FLAVORS_INSTALLED}" jq -r --arg NAME "${FLAVOR}" '.[]|select(.Name == $NAME)|.ID')" ]; then
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
	if [ -n "$(openstack service show -f json dns 2>/dev/null | jq -r '.id // ""')" ]; then
		OS_PRIVATE_DNS_ZONEID=$(openstack zone show -f json "${PRIVATE_DOMAIN_NAME}." 2>/dev/null | jq -r '.id // ""')

		if [ -z "${OS_PRIVATE_DNS_ZONEID}" ]; then
			echo_blue_bold "Register zone: ${PRIVATE_DOMAIN_NAME}. with email: ${CERT_EMAIL}"
			OS_PRIVATE_DNS_ZONEID=$(openstack zone create -f json --email ${CERT_EMAIL} --ttl 60 "${PRIVATE_DOMAIN_NAME}." 2>/dev/null | jq -r '.id // ""')
		else
			echo_blue_bold "Zone: ${PRIVATE_DOMAIN_NAME}. already registered with ID: ${OS_PRIVATE_DNS_ZONEID}"
		fi

		if [ -n "${OS_PRIVATE_DNS_ZONEID}" ]; then
			FILL_ETC_HOSTS=NO
		fi
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_security_group() {
	local INDEX=$1
	local SG=${INTERNAL_SECURITY_GROUP}

	if [ "${HA_CLUSTER}" == "true" ]; then
		if [ "${CONTROLPLANE_USE_PUBLICIP}" == "true" ] && [ ${INDEX} -lt ${WORKERNODE_INDEX} ]; then
			SG=${EXTERNAL_SECURITY_GROUP}
		elif [ "${WORKERNODE_USE_PUBLICIP}" == "true" ] && [ ${INDEX} -ge ${WORKERNODE_INDEX} ]; then
			SG=${EXTERNAL_SECURITY_GROUP}
		elif [ ${INDEX} -lt ${CONTROLNODE_INDEX} ] && [ "${USE_NGINX_GATEWAY}" == "YES" ]; then
			SG=${EXTERNAL_SECURITY_GROUP}
		fi
	elif [ ${INDEX} -eq 0 ]; then
		if [ "${USE_NGINX_GATEWAY}" == "YES" ] || [ "${CONTROLPLANE_USE_PUBLICIP}" == "true" ]; then
			SG=${EXTERNAL_SECURITY_GROUP}
		fi
	fi

	echo -n "${SG}"
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
	local NLB_SUBNET=$(openstack network show ${VC_NETWORK_PRIVATE} -f json | jq -r '.subnets[0]//""')

	NLB_ID=$(openstack loadbalancer create --vip-address ${NLB_VIP_ADDRESS} --vip-network-id ${VC_NETWORK_PRIVATE} -f json --name ${NLB_NAME} | jq -r '.id//""')

	IFS=,  read -a NLB_PORTS <<< "${NLB_PORTS}"
	IFS=,  read -a NLB_TARGETS <<< "${NLB_TARGETS}"

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

			eval openstack loadbalancer healthmonitor create \
				--name ${NLB_NAME}-health-${NLB_PORT} \
				--delay 15 \
				--max-retries 5 \
				--timeout 5 \
				--type TCP ${POOL_ID} ${SILENT}

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

	if [ ${USE_NGINX_GATEWAY} = "YES" ]; then
		NLB_TARGETS="${MASTERKUBE}:${PRIVATE_ADDR_IPS[0]}"
		VIP_ADDRESS=${PRIVATE_VIP_ADDRESS}
	else
		NLB_TARGETS=${CLUSTER_NODES}
		VIP_ADDRESS=${PRIVATE_ADDR_IPS[0]}
	fi

	echo_title "Create internal NLB ${MASTERKUBE} with target: ${NLB_TARGETS} at: ${VIP_ADDRESS}"

	create_nlb "nlb-internal-${MASTERKUBE}" false "${LOAD_BALANCER_PORT}" network "${NLB_TARGETS}" "${VIP_ADDRESS}" NO

	LOAD_BALANCER=$(openstack loadbalancer show -f json nlb-internal-${MASTERKUBE} 2>/dev/null)
	CONTROL_PLANE_ENDPOINT=$(echo "${LOAD_BALANCER}" | jq -r '.vip_address')
	LOAD_BALANCER_IP=$(echo "${LOAD_BALANCER}" | jq -r '.vip_address , .additional_vips[] | .' | tr '[:space:]' ',')
	PRIVATE_NLB_DNS=$(echo "${LOAD_BALANCER}" | jq -r '.vip_address')

	if [ ${EXPOSE_PUBLIC_CLUSTER} = "true" ]; then
		echo_title "Create external NLB ${MASTERKUBE} with target: ${NLB_TARGETS} at: ${PUBLIC_VIP_ADDRESS}"

		create_nlb "nlb-external-${MASTERKUBE}" true "80,443" network "${NLB_TARGETS}" "${PUBLIC_VIP_ADDRESS}" "YES"

		LOAD_BALANCER=$(openstack loadbalancer show -f json nlb-external-${MASTERKUBE} 2>/dev/null)
		PUBLIC_NLB_DNS=$(openstack floating ip list --fixed-ip-address ${PUBLIC_VIP_ADDRESS} -f json | jq -r '.[0]."Floating IP Address"')
	else
		PUBLIC_NLB_DNS=${PRIVATE_NLB_DNS}
	fi

	register_nlb_dns A ${PRIVATE_NLB_DNS} ${PUBLIC_NLB_DNS}
}