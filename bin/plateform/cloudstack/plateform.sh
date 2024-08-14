#!/bin/bash

CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl cmk packer"

export PRIVATE_GATEWAY=
export PRIVATE_IP=
export PRIVATE_MASK_CIDR=

export CLOUDSTACK_API_URL=
export CLOUDSTACK_API_KEY=
export CLOUDSTACK_SECRET_KEY=
export CLOUDSTACK_ZONE_NAME=default
export CLOUDSTACK_POD_NAME=default
export CLOUDSTACK_CLUSTER_NAME=default
export CLOUDSTACK_HOST_NAME=default
export CLOUDSTACK_PROJECT_NAME=default
export CLOUDSTACK_TEMPLATE_TYPE=user
export CLOUDSTACK_TRACE_CMK=NO

export CLOUDSTACK_ZONE_ID=
export CLOUDSTACK_POD_ID=
export CLOUDSTACK_CLUSTER_ID=
export CLOUDSTACK_HOST_ID=
export CLOUDSTACK_PROJECT_ID=
export CLOUDSTACK_HYPERVISOR=
export CLOUDSTACK_NETWORK_ID=
export CLOUDSTACK_VPC_ID=

export CLOUDSTACK_NETWORK_ASSOCIATE_PUBLICIP=
export CLOUDSTACK_NETWORK_NLB_SCHEME="Public|Internal"
export CLOUDSTACK_INTERNAL_NLB=
export CLOUDSTACK_EXTERNAL_NLB=

export PUBLIC_VIP_ADDRESS=
export PRIVATE_VIP_ADDRESS=
#===========================================================================================================================================
#
#===========================================================================================================================================
function usage() {
	common_usage
	cat <<EOF
### Flags ${PLATEFORM} plateform specific

  # Flags cloudstack
--cloudstack-api-url=<value>                   # The cloudstack api endpoint, default ${CLOUDSTACK_API_URL}
--cloudstack-api-key=<value>                   # The cloudstack api key, default ${CLOUDSTACK_API_KEY}
--cloudstack-secret-key=<value>                # The cloudstack secret key, default ${CLOUDSTACK_SECRET_KEY}

--cloudstack-zone-name=<value>                 # The cloudstack zone name, default ${CLOUDSTACK_ZONE_NAME}
--cloudstack-pod-name=<value>                  # The cloudstack pod name, default ${CLOUDSTACK_POD_NAME}
--cloudstack-cluster-name=<value>              # The cloudstack cluster name, default ${CLOUDSTACK_CLUSTER_NAME}
--cloudstack-host-name=<value>                 # The cloudstack host name, default ${CLOUDSTACK_HOST_NAME}
--cloudstack-project-name=<value>              # The cloudstack project name, default ${CLOUDSTACK_PROJECT_NAME}
--cloudstack-template-type=<value>             # The cloudstack template type, default ${CLOUDSTACK_TEMPLATE_TYPE}

  # Flags to configure nfs client provisionner
--nfs-server-adress=<value>                    # The NFS server address, default ${NFS_SERVER_ADDRESS}
--nfs-server-mount=<value>                     # The NFS server mount path, default ${NFS_SERVER_PATH}
--nfs-storage-class=<value>                    # The storage class name to use, default ${NFS_STORAGE_CLASS}

  # Flags to set the template vm
--seed-image=<value>                           # Override the seed image name used to create template, default ${SEED_IMAGE}
--kube-user=<value>                            # Override the seed user in template, default ${KUBERNETES_USER}
--kube-password | -p=<value>                   # Override the password to ssh the cluster VM, default random word

  # Flags in ha mode only
--use-nlb=[none|nginx|cloud]                   # Use plateform load balancer in public AZ

  # Flags to configure network in ${PLATEFORM}
--vm-network=<value>                           # Override the name of the private network in ${PLATEFORM}, default ${VC_NETWORK_PRIVATE}
--no-dhcp-autoscaled-node                      # Autoscaled node don't use DHCP, default ${SCALEDNODES_DHCP}
--dhcp-autoscaled-node                         # Autoscaled node use DHCP, default ${SCALEDNODES_DHCP}
--private-domain=<value>                       # Override the domain name, default ${PRIVATE_DOMAIN_NAME}
--net-address=<value>                          # Override the IP of the kubernetes control plane node, default ${PRIVATE_IP}
--net-dns=<value>                              # Override the IP DNS, default ${PRIVATE_DNS}

--prefer-ssh-publicip                          # Allow to SSH on publicip when available, default ${PREFER_SSH_PUBLICIP}
--external-security-group=<name>               # Specify the public security group ID for VM, default ${EXTERNAL_SECURITY_GROUP}
--internal-security-group=<name>               # Specify the private security group ID for VM, default ${INTERNAL_SECURITY_GROUP}
--internet-facing                              # Expose the cluster on internet, default ${EXPOSE_PUBLIC_CLUSTER}--public-subnet-id=<subnetid,...>                # Specify the public subnet ID for created VM, default ${VPC_PUBLIC_SUBNET_ID}

  # Flags to expose nodes in public AZ with public IP
--control-plane-public                         # Control plane are exposed to public, default ${CONTROLPLANE_USE_PUBLICIP}
--worker-node-public                           # Worker nodes are exposed to public, default ${WORKERNODE_USE_PUBLICIP}

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
		"vm-network:"
		"worker-node-public"
		"use-named-server"
		"install-named-server"
		"named-server-host:"
		"named-server-port:"
		"named-server-key:"
		"cloudstack-api-url:"
		"cloudstack-api-key:"
		"cloudstack-secret-key:"
		"cloudstack-zone-name:"
		"cloudstack-pod-name:"
		"cloudstack-cluster-name:"
		"cloudstack-host-name:"
		"cloudstack-project-name:"
		"cloudstack-template-type:"
		"cloudstack-trace"
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
		--cloudstack-api-url)
			CLOUDSTACK_API_URL="$2"
			shift 2
			;;
		--cloudstack-api-key)
			CLOUDSTACK_API_KEY="$2"
			shift 2
			;;
		--cloudstack-secret-key)
			CLOUDSTACK_SECRET_KEY="$2"
			shift 2
			;;

		--cloudstack-zone-name)
			CLOUDSTACK_ZONE_NAME="$2"
			shift 2
			;;
		--cloudstack-pod-name)
			CLOUDSTACK_POD_NAME="$2"
			shift 2
			;;
		--cloudstack-cluster-name)
			CLOUDSTACK_CLUSTER_NAME="$2"
			shift 2
			;;
		--cloudstack-host-name)
			CLOUDSTACK_HOST_NAME="$2"
			shift 2
			;;
		--cloudstack-project-name)
			CLOUDSTACK_PROJECT_NAME="$2"
			shift 2
			;;
		--cloudstack-template-type)
			CLOUDSTACK_TEMPLATE_TYPE=$2
			shift 2;;
		--cloudstack-trace)
			CLOUDSTACK_TRACE_CMK=YES
			shift;;
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
		--vm-network)
			VC_NETWORK_PRIVATE="$2"
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
				none|cloud|nginx)
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

	OUTPUT=$(eval "cmk -o json ${ARGS[@]}")

	if [ -z "${OUTPUT}" ]; then
		OUTPUT='{}'
	fi

	if [ -n "$(grep 'Error: (HTTP' <<< "${OUTPUT}")" ]; then
		echo_red_bold "${OUTPUT}" > /dev/stderr
		OUTPUT='{}'
	fi

	if [ "${CLOUDSTACK_TRACE_CMK}" == "YES" ]; then
		echo_blue_bold "cmk -o json ${ARGS[@]}" > /dev/stderr
		jq -r . <<<"${OUTPUT}" > /dev/stderr
	fi

	echo -n "${OUTPUT}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_image_extras_args() {
	local EXTRAS=(
		"--cloudstack-api-url=${CLOUDSTACK_API_URL}"
		"--cloudstack-api-key=${CLOUDSTACK_API_KEY}"
		"--cloudstack-api-secret=${CLOUDSTACK_SECRET_KEY}"
		"--cloudstack-keypair=${SSH_KEYNAME}"
		"--cloudstack-zone-id=${CLOUDSTACK_ZONE_ID}"
		"--cloudstack-pod-id=${CLOUDSTACK_POD_ID}"
		"--cloudstack-cluster-id=${CLOUDSTACK_CLUSTER_ID}"
		"--cloudstack-host-id=${CLOUDSTACK_HOST_ID}"
		"--cloudstack-hypervisor=${CLOUDSTACK_HYPERVISOR}"
		"--cloudstack-project-id=${CLOUDSTACK_PROJECT_ID}"
		"--cloudstack-network-id=${CLOUDSTACK_NETWORK_ID}"
		"--cloudstack-vpc-id=${CLOUDSTACK_VPC_ID}"
		"--cloudstack-template-type=${CLOUDSTACK_TEMPLATE_TYPE}"
	)

	echo -n ${EXTRAS[@]}
}
#===========================================================================================================================================
#
#===========================================================================================================================================
function parsed_arguments() {
	cmk <<EOF                                                                                                    
set url ${CLOUDSTACK_API_URL}
set apikey ${CLOUDSTACK_API_KEY}
set secretkey ${CLOUDSTACK_SECRET_KEY}
sync
EOF

	CLOUDSTACK_NETWORK_ID=$(get_network_id ${VC_NETWORK_PRIVATE})

	if [ -z "${CLOUDSTACK_NETWORK_ID}" ]; then
		echo_red_bold "Unable to find network id for network named: ${VC_NETWORK_PRIVATE}"
		exit 1
	fi
	
	CLOUDSTACK_VPC_ID=($(get_vpc_id ${CLOUDSTACK_NETWORK_ID}))

	VPC_PUBLIC_SUBNET_IDS=()
	VPC_PRIVATE_SUBNET_IDS=(${CLOUDSTACK_NETWORK_ID})

	CLOUDSTACK_ZONE_ID=$(cloudmonkey list zones name=${CLOUDSTACK_ZONE_NAME} | jq -r '.zone[0].id//""')
	if [ -z "${CLOUDSTACK_ZONE_ID}" ]; then
		echo_red_bold "Zone: ${CLOUDSTACK_ZONE_NAME} not found, exit"
		exit 1
	fi

	CLOUDSTACK_POD_ID=$(cloudmonkey list pods name=${CLOUDSTACK_POD_NAME} zoneid=${CLOUDSTACK_ZONE_ID} | jq -r '.pod[0].id//""')
	if [ -z "${CLOUDSTACK_POD_ID}" ]; then
		echo_red_bold "Pod: ${CLOUDSTACK_POD_NAME} not found, exit"
		exit 1
	fi

	CLOUDSTACK_CLUSTER_ID=$(cloudmonkey list clusters name=${CLOUDSTACK_CLUSTER_NAME} podid=${CLOUDSTACK_POD_ID} zoneid=${CLOUDSTACK_ZONE_ID} | jq -r '.cluster[0].id//""')
	if [ -z "${CLOUDSTACK_CLUSTER_ID}" ]; then
		echo_red_bold "Cluster: ${CLOUDSTACK_CLUSTER_NAME} not found, exit"
		exit 1
	fi

	CLOUDSTACK_HOST_ID=($(cloudmonkey list hosts name=${CLOUDSTACK_HOST_NAME} type=routing clusterid=${CLOUDSTACK_CLUSTER_ID} podid=${CLOUDSTACK_POD_ID} zoneid=${CLOUDSTACK_ZONE_ID} | jq -r '.host[]|.id//""'))
	if [ -z "${#CLOUDSTACK_HOST_ID[@]}" ]; then
		echo_red_bold "Host: ${CLOUDSTACK_HOST_NAME} not found, exit"
		exit 1
	fi

	CLOUDSTACK_HYPERVISOR=$(cloudmonkey list hosts id=${CLOUDSTACK_HOST_ID[0]} | jq -r '.host[0].hypervisor//""')
	if [ -z "${CLOUDSTACK_HYPERVISOR}" ]; then
		echo_red_bold "Hypervisor not found for host: ${CLOUDSTACK_HOST_NAME}, exit"
		exit 1
	fi

	CLOUDSTACK_PROJECT_ID=$(cloudmonkey list projects name=${CLOUDSTACK_PROJECT_NAME} | jq -r '.project[0].id//""')
	if [ -z "${CLOUDSTACK_PROJECT_ID}" ]; then
		echo_red_bold "Project: ${CLOUDSTACK_PROJECT_NAME} not found, exit"
		exit 1
	fi

	if [ -z "${PRIVATE_IP}" ]; then
		local NETWORK_DEFS=$(cloudmonkey list networks projectid=${CLOUDSTACK_PROJECT_ID} id=${CLOUDSTACK_NETWORK_ID})

		PRIVATE_GATEWAY=$(jq -r '.network[0].gateway' <<< "${NETWORK_DEFS}")
		CIDR=$(jq -r '.network[0].cidr' <<< "${NETWORK_DEFS}")
		IFS=/ read PRIVATE_IP PRIVATE_MASK_CIDR <<< "${CIDR}"
		PRIVATE_IP="${PRIVATE_IP%.*}.10"
		PRIVATE_DNS=$(jq -r '.network[0].dns1' <<< "${NETWORK_DEFS}")
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
function get_security_group() {
	local INDEX=$1
	local SG=

	if [ -z "${CLOUDSTACK_VPC_ID}" ]; then
		SG=${INTERNAL_SECURITY_GROUP}

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
	fi

	echo -n "${SG}"
}

#===========================================================================================================================================
#s
#===========================================================================================================================================
function plateform_create_vm() {
	local INDEX=$1
	local PUBLIC_IP=$2
	local NODE_IP=$3
	local FLOATING_IP=$(vm_use_floating_ip ${INDEX} ${CLOUDSTACK_EXTERNAL_NLB})
	local SECURITY_GROUP=$(get_security_group ${INDEX})
	local MACHINE_TYPE=$(get_machine_type ${INDEX})
	local MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	local MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})
	local SERVICEOFFERING_ID=$(get_serviceoffering_id ${MACHINE_TYPE})

	if [ -z "${MASTERKUBE_NODE_UUID}" ]; then
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
		echo_blue_bold "Launch ${MASTERKUBE_NODE} index: ${INDEX} with ${TARGET_IMAGE} and serviceoffering=${MACHINE_TYPE} TARGET_IMAGE=${TARGET_IMAGE} MASTERKUBE_NODE=${MASTERKUBE_NODE}"
		echo_line

		if [ ${NODE_IP} != "AUTO" ] && [ ${NODE_IP} != "DHCP" ]; then
			IPADDRESS="${NODE_IP}"
		fi

		INSTANCE=$(cloudmonkey deploy virtualmachine \
			startvm=true \
			name=${MASTERKUBE_NODE} \
			displayname=${MASTERKUBE_NODE} \
			ipaddress=${IPADDRESS} \
			securitygroupids=${SECURITY_GROUP} \
			hypervisor=${CLOUDSTACK_HYPERVISOR} \
			templateid=${TARGET_IMAGE_UUID} \
			networkids=${CLOUDSTACK_NETWORK_ID} \
			serviceofferingid=${SERVICEOFFERING_ID} \
			keypair="${SSH_KEYNAME}" \
			userdata=$(cat ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.yaml | base64 -w 0) \
			projectid=${CLOUDSTACK_PROJECT_ID} \
			clusterid=${CLOUDSTACK_CLUSTER_ID} \
			podid=${CLOUDSTACK_POD_ID} \
			zoneid=${CLOUDSTACK_ZONE_ID})

		INSTANCE_ID=$(jq -r '.virtualmachine.id//""' <<< ${INSTANCE})

		if [ -z "${INSTANCE_ID}" ]; then
			jq . <<< "${INSTANCE}"
			echo_red_bold "Unable to create instance:${MASTERKUBE_NODE}"
			return 1
		fi

		if [ ${FLOATING_IP} == "true" ]; then
			if [ ${PUBLIC_IP} == "DHCP" ] || [ ${PUBLIC_IP} == NONE ]; then
				PUBLIC_IP=
			fi

			IPADDRESS=$(cloudmonkey associate ipaddress ipaddress=${PUBLIC_IP} virtualmachineid=${INSTANCE_ID} projectid=${CLOUDSTACK_PROJECT_ID} vpcid=${CLOUDSTACK_VPC_ID} networkid=${CLOUDSTACK_NETWORK_ID})
			PUBLIC_IP=$(echo ${IPADDRESS} | jq -r '.ipaddress//""')

			SUCCESS=$(cloudmonkey enable staticnat \
				ipaddressid=$(echo ${PUBLIC_IP} | jq -r '.id//""') \
				virtualmachineid=${INSTANCE_ID}  \
				networkid=${CLOUDSTACK_NETWORK_ID})
		fi
	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"

		INSTANCE=$(cloudmonkey list virtualmachines projectid=${CLOUDSTACK_PROJECT_ID} name=${MASTERKUBE_NODE})
		LOCALIP=$(echo ${INSTANCE} | jq -r '.virtualmachine[0].nic[0].ipaddress//""')

		if [ ${FLOATING_IP} == "true" ]; then
			PUBLIC_IP=$(echo ${INSTANCE} | jq -r '.virtualmachine[0].nic[0].publicip//""')
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
	local FLOATING_IP=$(vm_use_floating_ip ${INDEX} ${CLOUDSTACK_EXTERNAL_NLB})
	local MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	local SUFFIX=$(named_index_suffix $1)
	local INSTANCE=$(cloudmonkey list virtualmachines projectid=${CLOUDSTACK_PROJECT_ID} name=${MASTERKUBE_NODE})
	local PRIVATE_IP=$(echo ${INSTANCE} | jq -r '.virtualmachine[0].nic[0].ipaddress//""')
	local MASTERKUBE_NODE_UUID=$(echo ${INSTANCE} | jq -r '.virtualmachine[0].id//""')

	if [ ${FLOATING_IP} == "true" ]; then
		PUBLIC_IP=$(echo ${INSTANCE} | jq -r '.virtualmachine[0].nic[0].publicip//""')
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
	local INSTANCE=$(cloudmonkey list virtualmachines \
		name=${VMNAME} \
		projectid=${CLOUDSTACK_PROJECT_ID} \
		zoneid=${CLOUDSTACK_ZONE_ID} \
		podid=${CLOUDSTACK_POD_ID} \
		clusterid=${CLOUDSTACK_CLUSTER_ID} \
		hypervisor=${CLOUDSTACK_HYPERVISOR} | jq '.virtualmachine|first')
    local VMUUID=$(jq -r '.id//""' <<< "${INSTANCE}")

	if [ -n "${VMUUID}" ]; then
        echo_blue_bold "Delete VM: ${VMNAME}"
		PUBLICIP=$(jq -r '.publicip//""' <<< "${INSTANCE}")
		PUBLICIPID=$(jq -r '.publicipid//""' <<< "${INSTANCE}")

		if [ -n "${PUBLICIPID}" ]; then
			echo_blue_bold "Delete public ip: ${PUBLICIP}, id: ${PUBLICIPID}"
			SUCCESS=$(cloudmonkey disassociate ipaddress id=${PUBLICIPID} | jq -r '.success//"false"')
		fi

		SUCCESS=$(cloudmonkey destroy virtualmachine expunge=true id=${VMUUID})
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_internal_loadbalancer() {
	local NAME=$1
	local LOADBALANCERS=$(cloudmonkey list loadbalancers networkid=${CLOUDSTACK_NETWORK_ID} projectid=${CLOUDSTACK_PROJECT_ID} tags[0].key=cluster tags[0].value=${NAME})
	local NLBID=
	local NLB_NAME=
	local SUCCESS=

	if [ $(jq -r '.count//0' <<< "${LOAD_BALANCERS}") -gt 0 ]; then
		for NLBID in $(jq -r '.loadbalancer[]|.id//""' <<< "${LOADBALANCERS}")
		do
			NLB_NAME=$(jq -r --arg ID ${NLBID} '.loadbalancer[]|select(.id == $ID)|.name//""' <<< "${LOADBALANCERS}")

			SUCCESS=$(cloudmonkey delete loadbalancer id=${NLBID} | jq -r '.success//"false"')

			echo_blue_bold "Delete internal loadbalancer: ${NLB_NAME}, ID: ${NLBID}, success: ${SUCCESS}"
		done
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_public_loadbalancer() {
	local NAME=$1
	local LOAD_BALANCERS=$(cloudmonkey list loadbalancerrules networkid=${CLOUDSTACK_NETWORK_ID} projectid=${CLOUDSTACK_PROJECT_ID} tags[0].key=cluster tags[0].value=${NAME})
	local SUCCESS=
	local PUBLIC_ADDR_IPS=
	local PUBLIC_ADDR_IP=
	local NLB_NAME=

	if [ $(jq -r '.count//0' <<< "${LOAD_BALANCERS}") -gt 0 ]; then
		local NLB_IDS=$(jq -r '.loadbalancerrule[]|.id' <<< "${LOAD_BALANCERS}")

		for NLB_ID in $NLB_IDS
		do
			local NLB_NAME=$(jq -r --arg ID ${NLB_ID} '.loadbalancerrule[]|select(.id == $ID)|.name//""' <<< "${LOAD_BALANCERS}")

			SUCCESS=$(cloudmonkey delete loadbalancerrule id=${NLB_ID} | jq -r '.success//"false"')

			echo_blue_bold "Delete public loadbalancer rule: ${NLB_NAME}, ID: ${NLB_ID}, success: ${SUCCESS}"
		done
	fi

	PUBLIC_ADDR_IPS=$(cloudmonkey list publicipaddresses projectid=${CLOUDSTACK_PROJECT_ID} tags[0].key=cluster tags[0].value=${NAME})
	
	if [ $(jq -r '.count//0' <<< "${PUBLIC_ADDR_IPS}") -gt 0 ]; then
		for PUBLIC_ADDR_IP in $(jq -r '.publicipaddress[]|.ipaddress//""' <<< "${PUBLIC_ADDR_IPS}")
		do
			SUCCESS=$(cloudmonkey disassociate ipaddress ipaddress=${PUBLIC_ADDR_IP} | jq -r '.success//"false"')
			echo_blue_bold "Delete public ipaddress: ${PUBLIC_ADDR_IP}, success: ${SUCCESS}"
		done
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_load_balancers() {
	if [ "${CLOUDSTACK_INTERNAL_NLB}" == "cloud" ]; then
		delete_internal_loadbalancer "nlb-${MASTERKUBE}"
	fi

	if [ "${CLOUDSTACK_EXTERNAL_NLB}" == "cloud" ]; then
		delete_public_loadbalancer "nlb-${MASTERKUBE}"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function update_build_env() {
	save_buildenv

cat >> ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
#===============================================
export CLOUDSTACK_API_URL=${CLOUDSTACK_API_URL}
export CLOUDSTACK_API_KEY=${CLOUDSTACK_API_KEY}
export CLOUDSTACK_SECRET_KEY=${CLOUDSTACK_SECRET_KEY}
export CLOUDSTACK_ZONE_NAME=${CLOUDSTACK_ZONE_NAME}
export CLOUDSTACK_POD_NAME=${CLOUDSTACK_POD_NAME}
export CLOUDSTACK_CLUSTER_NAME=${CLOUDSTACK_CLUSTER_NAME}
export CLOUDSTACK_HOST_NAME=${CLOUDSTACK_HOST_NAME}
export CLOUDSTACK_PROJECT_NAME=${CLOUDSTACK_PROJECT_NAME}
export CLOUDSTACK_ZONE_ID=${CLOUDSTACK_ZONE_ID}
export CLOUDSTACK_POD_ID=${CLOUDSTACK_POD_ID}
export CLOUDSTACK_CLUSTER_ID=${CLOUDSTACK_CLUSTER_ID}
export CLOUDSTACK_HOST_ID=(${CLOUDSTACK_HOST_ID[@]})
export CLOUDSTACK_PROJECT_ID=${CLOUDSTACK_PROJECT_ID}
export CLOUDSTACK_HYPERVISOR=${CLOUDSTACK_HYPERVISOR}
export CLOUDSTACK_NETWORK_ID=${CLOUDSTACK_NETWORK_ID}
export CLOUDSTACK_VPC_ID=${CLOUDSTACK_VPC_ID}
export CLOUDSTACK_NETWORK_ASSOCIATE_PUBLICIP=${CLOUDSTACK_NETWORK_ASSOCIATE_PUBLICIP}
export CLOUDSTACK_NETWORK_NLB_SCHEME=${CLOUDSTACK_NETWORK_NLB_SCHEME}
export CLOUDSTACK_INTERNAL_NLB=${CLOUDSTACK_INTERNAL_NLB}
export CLOUDSTACK_EXTERNAL_NLB=${CLOUDSTACK_EXTERNAL_NLB}
EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function update_provider_config() {
	PROVIDER_AUTOSCALER_CONFIG=$(cat ${TARGET_CONFIG_LOCATION}/provider.json)

	echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE ${TARGET_IMAGE_UUID} "template = $TARGET_IMAGE_UUID" > ${TARGET_CONFIG_LOCATION}/provider.json
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_serviceoffering_id() {
	cloudmonkey list serviceofferings \
		name=$1 \
		projectid=${CLOUDSTACK_PROJECT_ID} \
		zoneid=${CLOUDSTACK_ZONE_ID} \
		| jq -r --arg NAME "$1" '.serviceoffering[]|select(.name == $NAME)|.id//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_image_uuid() {
	local TARGET_IMAGE=$1

	cloudmonkey list templates \
		name=${TARGET_IMAGE} \
		templatefilter=self \
		projectid=${CLOUDSTACK_PROJECT_ID} \
		hypervisor=${CLOUDSTACK_HYPERVISOR} | jq -r '.template[0].id//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vmuuid() {
    local VMNAME=$1

	cloudmonkey list virtualmachines \
		name=${VMNAME} \
		projectid=${CLOUDSTACK_PROJECT_ID} \
		zoneid=${CLOUDSTACK_ZONE_ID} \
		podid=${CLOUDSTACK_POD_ID} \
		clusterid=${CLOUDSTACK_CLUSTER_ID} \
		hypervisor=${CLOUDSTACK_HYPERVISOR} \
		| jq -r '.virtualmachine[0].id//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_net_type() {
	local NAME=$1

	cloudmonkey list networks \
		projectid=${CLOUDSTACK_PROJECT_ID} \
		zoneid=${CLOUDSTACK_ZONE_ID} \
		podid=${CLOUDSTACK_POD_ID} \
		clusterid=${CLOUDSTACK_CLUSTER_ID} \
		| jq -r --arg NAME "${NAME}" '.network[]|select(.name == $NAME)|.traffictype//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_network_id() {
	local NAME=$1

	cloudmonkey list networks \
		projectid=${CLOUDSTACK_PROJECT_ID} \
		zoneid=${CLOUDSTACK_ZONE_ID} \
		podid=${CLOUDSTACK_POD_ID} \
		clusterid=${CLOUDSTACK_CLUSTER_ID} \
		| jq -r --arg NAME "${NAME}" '.network[]|select(.name == $NAME)|.id//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vpc_id() {
	local NETWORK_ID=$1

	cloudmonkey list networks \
		networkid=${NETWORK_ID} \
		projectid=${CLOUDSTACK_PROJECT_ID} \
		zoneid=${CLOUDSTACK_ZONE_ID} \
		podid=${CLOUDSTACK_POD_ID} \
		clusterid=${CLOUDSTACK_CLUSTER_ID} \
		| jq -r '.network[0].vpcid//""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_ssh() {
	FINGER_PRINT="$(ssh-keygen -l -E md5 -f ${SSH_PUBLIC_KEY} | cut -d ' ' -f 2 | sed 's/MD5://')"
	SSHKEY=$(cloudmonkey list sshkeypairs projectid=${CLOUDSTACK_PROJECT_ID} fingerprint=${FINGER_PRINT})
	KEYEXISTS=$(jq -r '.sshkeypair[0].id // ""' <<<"${SSHKEY}")

	if [ -z ${KEYEXISTS} ]; then
		echo_blue_bold "SSH Public key doesn't exist"
		eval cloudmonkey register sshkeypair \
			name=${SSH_KEYNAME} \
			projectid=${CLOUDSTACK_PROJECT_ID} \
			publickey="$(cat ${SSH_PUBLIC_KEY})" ${SILENT}
	else
		SSH_KEYNAME=$(jq -r '.sshkeypair[0].name // ""' <<<"${SSHKEY}")
		echo_blue_bold "SSH Public keypair already exists with fingerprint=${FINGER_PRINT} and name=${SSH_KEYNAME}"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function determine_used_loadbalancers() {
	local NETWORK_DEFS=$(cloudmonkey list networks projectid=${CLOUDSTACK_PROJECT_ID} id=${CLOUDSTACK_NETWORK_ID})

	CLOUDSTACK_NETWORK_NLB_SCHEME=$(jq -r '.network[0].service[]|select(.name == "Lb")|.capability[]|select(.name == "LbSchemes")|.value' <<< "${NETWORK_DEFS}" )
	CLOUDSTACK_NETWORK_NLB_SCHEME=${CLOUDSTACK_NETWORK_NLB_SCHEME:=None}
	CLOUDSTACK_NETWORK_ASSOCIATE_PUBLICIP=$(jq -r '.network[0].service[]|select(.name == "StaticNat")|.capability[]|select(.name == "AssociatePublicIP")|.value' <<< "${NETWORK_DEFS}" )
	CLOUDSTACK_NETWORK_ASSOCIATE_PUBLICIP=${CLOUDSTACK_NETWORK_ASSOCIATE_PUBLICIP:=false}
	CLOUDSTACK_INTERNAL_NLB=none
	CLOUDSTACK_EXTERNAL_NLB=none

	# Check if we can create public ip if exposed
	if [ ${CLOUDSTACK_NETWORK_ASSOCIATE_PUBLICIP} == "false" ]; then
		if [ "${EXPOSE_PUBLIC_CLUSTER}" == "true" ] || [ "${CONTROLPLANE_USE_PUBLICIP}" == "true" ] || [ "${WORKERNODE_USE_PUBLICIP}" == "true" ]; then
			echo_red_bold "The selected network: ${CLOUDSTACK_NETWORK_ID} doesn't allow associate a public IP"
			exit 1
		fi
	fi

	# Check if we can create public load balancer with the provider
	if [ "${USE_NLB}" == "cloud" ]; then
		if [ ${CLOUDSTACK_NETWORK_NLB_SCHEME} != "None" ] && [ ${CLOUDSTACK_NETWORK_NLB_SCHEME} != "Internal" ] && [ ${CLOUDSTACK_NETWORK_NLB_SCHEME} != "Public" ]; then
			echo_red_bold "Unknown network loadbalancer scheme: ${CLOUDSTACK_NETWORK_NLB_SCHEME}"
			exit 1
		fi

		if [ "${HA_CLUSTER}" == "true" ]; then
			case ${CLOUDSTACK_NETWORK_NLB_SCHEME} in
				"None")
					CLOUDSTACK_INTERNAL_NLB=keepalived
					if [ "${EXPOSE_PUBLIC_CLUSTER}" == "true" ]; then
						echo_red_bold "The selected network: ${CLOUDSTACK_NETWORK_ID} doesn't allow to create loadbalancer, use nginx instead with keepalived"
						CLOUDSTACK_EXTERNAL_NLB=nginx
					fi
					;;
				"Internal")
					CLOUDSTACK_INTERNAL_NLB=cloud
					if [ "${EXPOSE_PUBLIC_CLUSTER}" == "true" ]; then
						echo_red_bold "The selected network: ${CLOUDSTACK_NETWORK_ID} doesn't allow create public loadbalancer use nginx instead with internal lb"

						CLOUDSTACK_EXTERNAL_NLB=nginx
					fi
					;;
				"Public")
					echo_red_bold "The selected network: ${CLOUDSTACK_NETWORK_ID} doesn't allow to create internal loadbalancer, use keepalived"
					CLOUDSTACK_INTERNAL_NLB=keepalived
					CLOUDSTACK_EXTERNAL_NLB=cloud
					;;
			esac
		else
			case ${CLOUDSTACK_NETWORK_NLB_SCHEME} in
				"None")
					echo_red_bold "The selected network: ${CLOUDSTACK_NETWORK_ID} doesn't allow to create loadbalancer, use nginx"
					USE_NLB=nginx
					;;
				"Internal")
					CLOUDSTACK_INTERNAL_NLB=cloud
					;;
				"Public")
					if [ "${EXPOSE_PUBLIC_CLUSTER}" == "false" ]; then
						echo_red_bold "The selected network: ${CLOUDSTACK_NETWORK_ID} allow to create public loadbalancer but the cluster is not exposed to public"
						exit 1
					fi
					CLOUDSTACK_EXTERNAL_NLB=cloud
					;;
			esac
		fi
	fi

	if [ ${CLOUDSTACK_EXTERNAL_NLB} == "nginx" ]; then
		FIRSTNODE=0
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

	echo_title "Prepare service offering"

	local SERVICEOFFERINS=$(cat ${PWD}/templates/setup/${PLATEFORM}/machines.json)
	local SERVICEOFFERINS_KEYS=$(echo ${SERVICEOFFERINS} | jq -r 'keys_unsorted | .[]')
	local SERVICEOFFERINS_INSTALLED=$(cloudmonkey list serviceofferings projectid=${CLOUDSTACK_PROJECT_ID} zoneid=${CLOUDSTACK_ZONE_ID})

	for SERVICEOFFERIN in ${SERVICEOFFERINS_KEYS}
	do
		if [ -z "$(echo "${SERVICEOFFERINS_INSTALLED}" | jq -r --arg NAME "${SERVICEOFFERIN}" '.serviceoffering[]|select(.name == $NAME)|.id')" ]; then
			read MEMSIZE NUM_VCPUS DISK_SIZE CPU_SPEED <<<"$(echo ${SERVICEOFFERINS} | jq -r --arg SERVICEOFFERIN ${SERVICEOFFERIN} '.[$SERVICEOFFERIN]|.memsize,.vcpus,.disksize,.cpuspeed' | tr '\n' ' ')"

			echo_blue_bold "Create service offering: ${SERVICEOFFERIN}, disk: ${DISK_SIZE} MB memory: ${MEMSIZE} vcpus: ${NUM_VCPUS} cpu speed Mhz: ${CPU_SPEED}"

			eval cloudmonkey create serviceoffering  \
				name=${SERVICEOFFERIN} \
				cpunumber=${NUM_VCPUS} \
				memory=${MEMSIZE} \
				provisioningtype=thin\
				zoneid=${CLOUDSTACK_ZONE_ID} \
				cpuspeed=${CPU_SPEED:=2000} \
				rootdisksize=$((DISK_SIZE / 1024))  ${SILENT}
		else
			echo_blue_bold "Service offering: ${SERVICEOFFERIN} already exists"
		fi
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function check_ip_public_free() {
	local IP=$1

	ID=$(cloudmonkey list publicipaddresses state=free ipaddress=${IP} | jq -r '.publicipaddress[0].id')

	if [ -z "${ID}" ]; then
		IP=$(nextip ${IP} true)
	fi

	echo -n "${IP}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_networking() {
	prepare_routes

	if [ -z "${VC_NETWORK_PUBLIC}" ] || [ "${PUBLIC_IP}" == "NONE" ]; then
		PUBLIC_IP=NONE
		PUBLIC_NODE_IP=NONE
		VC_NETWORK_PUBLIC_ENABLED=false
	elif [ "${PUBLIC_IP}" == "DHCP" ]; then
		PUBLIC_NODE_IP=${PUBLIC_IP}
	else
		IFS=/ read PUBLIC_NODE_IP PUBLIC_MASK_CIDR <<< "${PUBLIC_IP}"
		PUBLIC_NETMASK=$(cidr_to_netmask ${PUBLIC_MASK_CIDR})
	fi

	# No external elb, use keep alived
	if [ ${CLOUDSTACK_INTERNAL_NLB} = "cloud" ] || [ ${CLOUDSTACK_INTERNAL_NLB} = "keepalived" ]; then
		PRIVATE_ADDR_IPS[0]="${NODE_IP}"
		PRIVATE_DNS_NAMES[0]=""
		PUBLIC_ADDR_IPS[0]=${PUBLIC_NODE_IP}
		PRIVATE_VIP_ADDRESS=${NODE_IP}

		NODE_IP=$(nextip ${NODE_IP} false)
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP} true)

		if [ ${CLOUDSTACK_EXTERNAL_NLB} != "none" ]; then
			PUBLIC_VIP_ADDRESS=${PUBLIC_NODE_IP}
			PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP} true)

			if [ ${CLOUDSTACK_EXTERNAL_NLB} == "nginx" ]; then
				NODE_IP=$(nextip ${NODE_IP} false)
			fi
		fi

	elif [ ${CLOUDSTACK_EXTERNAL_NLB} == "nginx" ]; then
		PRIVATE_ADDR_IPS[0]="${NODE_IP}"
		PRIVATE_DNS_NAMES[0]=""
		PUBLIC_ADDR_IPS[0]=${PUBLIC_NODE_IP}
		PRIVATE_VIP_ADDRESS="${NODE_IP}"

		NODE_IP=$(nextip ${NODE_IP} false)
		PUBLIC_NODE_IP=$(nextip ${PUBLIC_NODE_IP} true)
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_internal_loadbalancer() {
	local NLB_NAME=$1
	local NLB_PORTS=$2
	local NLB_INSTANCEIDS=$3
	local NLB_VIP_ADDRESS=$4
	local NLB_PORT=
	local NLB_ID=
	local INSTANCE_ID=
	local INSTANCE_IDS=
	local SUFFIX=

	IFS=, read -a NLB_PORTS <<< "${NLB_PORTS}"

	for NLB_PORT in ${NLB_PORTS[@]}
	do
		NLB_ID=$(cloudmonkey create loadbalancer \
			name=${NLB_NAME}-${NLB_PORT} \
			sourceport=${NLB_PORT} \
			instanceport=${NLB_PORT} \
			sourceipaddress=${NLB_VIP_ADDRESS} \
			networkid=${CLOUDSTACK_NETWORK_ID} \
			sourceipaddressnetworkid=${CLOUDSTACK_NETWORK_ID} \
			scheme=internal \
			algorithm=roundrobin \
			| jq -r '.loadbalancer.id//""')

		if [ -z "${NLB_ID}" ]; then
			echo_red_bold "Unable to create internal loadbalancer: ${NLB_NAME}-${NLB_PORT}"
			exit 1
		fi

		SUCCESS=$(cloudmonkey create tags resourceids=${NLB_ID} tags[0].key=cluster tags[0].value=${NLB_NAME} resourcetype=loadbalancer)
		SUCCESS=$(cloudmonkey assign toloadbalancerrule id=${NLB_ID} virtualmachineids=${NLB_INSTANCEIDS})
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_public_loadbalancer() {
	local NLB_NAME=$1
	local NLB_PORTS=$2
	local NLB_INSTANCEIDS=$3
	local NLB_VIP_ADDRESS=$4
	local NLB_PORT=
	local NLB_ID=
	local NLB_RULE_ID=
	local NLB_DATAS=

	if [ "${NLB_VIP_ADDRESS}" == "DHCP" ] || [ "${NLB_VIP_ADDRESS}" == "NONE" ]; then
		NLB_VIP_ADDRESS=
	fi

	IFS=, read -a NLB_PORTS <<< "${NLB_PORTS}"
	NLB_DATAS=$(cloudmonkey associate ipaddress ipaddress=${NLB_VIP_ADDRESS} projectid=${CLOUDSTACK_PROJECT_ID} vpcid=${CLOUDSTACK_VPC_ID} networkid=${CLOUDSTACK_NETWORK_ID})
	NLB_VIP_ID=$(jq -r '.ipaddress.id//""' <<< "${NLB_DATAS}")
	NLB_VIP_ADDRESS=$(jq -r '.ipaddress.ipaddress//""' <<< "${NLB_DATAS}")

	if [ -z "${NLB_VIP_ID}" ]; then
		echo_red_bold "Unable to associate public address ip" > /dev/null
		exit 1
	fi

	SUCCESS=$(cloudmonkey create tags resourceids=${NLB_VIP_ID} tags[0].key=cluster tags[0].value=${NLB_NAME} resourcetype=publicipaddress)

	for NLB_PORT in ${NLB_PORTS[@]}
	do
		NLB_RULE_ID=$(cloudmonkey create loadbalancerrule \
			name=${NLB_NAME}-${NLB_PORT} \
			publicport=${NLB_PORT} \
			privateport=${NLB_PORT} \
			publicipid=${NLB_VIP_ID} \
			networkid=${CLOUDSTACK_NETWORK_ID} \
			zoneid=${CLOUDSTACK_ZONE_ID} \
			algorithm=roundrobin \
			protocol=tcp \
			cidrlist="0.0.0.0/0" | jq -r '.loadbalancer.id//""')

		if [ -z "${NLB_RULE_ID}" ]; then
			echo_red_bold "Unable to create loadbalancer rule: ${NLB_NAME}-${NLB_PORT}" > /dev/stderr
			exit 1
		fi

		SUCCESS=$(cloudmonkey create tags  resourceids=${NLB_RULE_ID} tags[0].key=cluster tags[0].value=${NLB_NAME} resourcetype=loadbalancer)
		SUCCESS=$(cloudmonkey assign toloadbalancerrule id=${NLB_RULE_ID} virtualmachineids=${NLB_INSTANCEIDS})
	done

	echo -n ${NLB_VIP_ADDRESS}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_plateform_nlb() {
	local NLB_TARGETS=${CLUSTER_NODES}
	local NLB_INSTANCE_IDS=
    local PUBLIC_NLB_DNS=${PUBLIC_ADDR_IPS[0]:=DHCP}
    local PRIVATE_NLB_DNS=
	local INDEX=
	local LISTEN_PORTS=

	if [ "${CLOUDSTACK_INTERNAL_NLB}" != "none" ]; then
		PRIVATE_NLB_DNS=${PRIVATE_ADDR_IPS[0]}
	else
		PRIVATE_NLB_DNS=${PRIVATE_ADDR_IPS[1]}
	fi

	LOAD_BALANCER_IP=${PRIVATE_NLB_DNS}

	for INDEX in $(seq ${CONTROLNODE_INDEX} $((CONTROLNODE_INDEX + ${CONTROLNODES} - 1)))
	do
		local SUFFIX=$(named_index_suffix $INDEX)
		local INSTANCE_ID=$(jq -r '.InstanceId//""' ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json)

		if [ -z "${NLB_INSTANCE_IDS}" ]; then
			NLB_INSTANCE_IDS="${INSTANCE_ID}"
		else
			NLB_INSTANCE_IDS="${NLB_INSTANCE_IDS},${INSTANCE_ID}"
		fi
	done

	if [ "${CLOUDSTACK_EXTERNAL_NLB}" != "none" ]; then		
		echo_title "Create external NLB ${MASTERKUBE} with target: ${NLB_INSTANCE_IDS} at: ${PUBLIC_NLB_DNS}"

		if [ ${CLOUDSTACK_EXTERNAL_NLB} == "cloud" ]; then
			if [ ${CONTROLPLANE_USE_PUBLICIP} == "true" ]; then
				PUBLIC_NLB_DNS=$(create_public_loadbalancer "nlb-${MASTERKUBE}" "${LOAD_BALANCER_PORT}" "${NLB_INSTANCE_IDS}" "${PUBLIC_NLB_DNS}")
			else
				PUBLIC_NLB_DNS=$(create_public_loadbalancer "nlb-${MASTERKUBE}" "${EXPOSE_PUBLIC_PORTS}" "${NLB_INSTANCE_IDS}" "${PUBLIC_NLB_DNS}")
			fi
		else
			create_nginx_gateway
		fi
	else
		PUBLIC_NLB_DNS=${PRIVATE_NLB_DNS}
	fi

	if [ "${CLOUDSTACK_INTERNAL_NLB}" != "none" ]; then
		echo_title "Create internal NLB ${MASTERKUBE} with target: ${NLB_INSTANCE_IDS} at: ${PRIVATE_NLB_DNS}"

		LOAD_BALANCER_IP=${PRIVATE_NLB_DNS}

		if [ "${CLOUDSTACK_INTERNAL_NLB}" == "cloud" ]; then
			create_internal_loadbalancer "nlb-${MASTERKUBE}" "${LOAD_BALANCER_PORT}" "${NLB_INSTANCE_IDS}" "${PRIVATE_NLB_DNS}"
		else
			create_keepalived
		fi
	fi

	register_nlb_dns A "${PRIVATE_NLB_DNS}" "${PUBLIC_NLB_DNS}" "" ""
}