CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl kubernetes-desktop-autoscaler-utility packer"
PRIVATE_NET_INF=eth1 # eth0 is multipass interface
VC_NETWORK_PRIVATE="private"
VC_NETWORK_PUBLIC="public"
NGINX_MACHINE="k8s.tiny"
CONTROL_PLANE_MACHINE="k8s.small"
WORKER_NODE_MACHINE="k8s.medium"
AUTOSCALE_MACHINE="k8s.medium"

#===========================================================================================================================================
#
#===========================================================================================================================================
function use_floating_ip() {
	local INDEX=$1

	if [ ${HA_CLUSTER} = "true" ]; then
		if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
			echo -n ${EXPOSE_PUBLIC_CLUSTER}
		elif [ ${INDEX} -lt ${WORKERNODE_INDEX} ]; then
			echo -n ${CONTROLPLANE_USE_PUBLICIP}
		else
			echo -n ${WORKERNODE_USE_PUBLICIP}
		fi
	elif [ ${INDEX} -lt ${WORKERNODE_INDEX} ]; then
		echo -n ${CONTROLPLANE_USE_PUBLICIP}
	else
		echo -n ${WORKERNODE_USE_PUBLICIP}
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_vm() {
	local INDEX=$1
	local NODE_IP=$2
	local SECURITY_GROUP=$3
	local FLOATING_IP=$(use_floating_ip ${INDEX})
	local MACHINE_TYPE=
	local MASTERKUBE_NODE=
	local IPADDR=
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
		echo_blue_bold "Launch ${TARGET_IMAGE} to ${MASTERKUBE_NODE} TARGET_IMAGE=${TARGET_IMAGE} MASTERKUBE_NODE=${MASTERKUBE_NODE}"
		echo_line

		if [ ${FLOATING_IP} == "YES" ]; then
			IPADDR=$(openstack floating ip list --tags ${MASTERKUBE_NODE} -f json 2>/dev/null | jq -r '.[0]."Floating IP Address"//""')

			if [ -z "${IPADDR}" ]; then
				IPADDR=$(openstack floating ip create --tag ${MASTERKUBE_NODE} -f json ${VC_NETWORK_PUBLIC} | jq -r '.floating_ip_address // ""')

				echo_blue_bold "Create floating ip: ${IPADDR} for ${MASTERKUBE_NODE} on network ${VC_NETWORK_PUBLIC}"
			else
				echo_blue_bold "Use floating ip: ${IPADDR} for ${MASTERKUBE_NODE} on network ${VC_NETWORK_PUBLIC}"
			fi
		fi

		if [ ${NODE_IP} == "AUTO" ]; then
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

		if [ ${FLOATING_IP} == "YES" ]; then
			openstack server add floating ip ${MASTERKUBE_NODE} ${IPADDR}
		fi

		echo_title "Wait ssh ready on ${KUBERNETES_USER}@${LOCALIP}"
		wait_ssh_ready ${KUBERNETES_USER}@${LOCALIP}

		echo_title "Prepare ${MASTERKUBE_NODE} instance with IP:${LOCALIP}"
		eval scp ${SCP_OPTIONS} tools ${KUBERNETES_USER}@${LOCALIP}:~ ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${LOCALIP} mkdir -p /home/${KUBERNETES_USER}/cluster ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${LOCALIP} sudo chown -R root:adm /home/${KUBERNETES_USER}/tools ${SILENT}
		eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${LOCALIP} sudo cp /home/${KUBERNETES_USER}/tools/* /usr/local/bin ${SILENT}

		# Update /etc/hosts
		delete_host "${MASTERKUBE_NODE}"
		add_host ${LOCALIP} ${MASTERKUBE_NODE} ${MASTERKUBE_NODE}.${DOMAIN_NAME}

		if [ -n "${OS_DNS_ZONEID}" ]; then
			echo_blue_bold "Register ${MASTERKUBE_NODE} address: ${LOCALIP} into dns zone ${PRIVATE_DOMAIN_NAME} id: ${OS_DNS_ZONEID}"
			DNS_ENTRY=$(openstack recordset create -f json --record ${LOCALIP} --type A "${PRIVATE_DOMAIN_NAME}." ${MASTERKUBE_NODE} 2>/dev/null | jq -r '.id // ""')
			cat > ${TARGET_CONFIG_LOCATION}/dns-${MASTERKUBE_NODE}.json <<EOF
			{
				"id": "${DNS_ENTRY}",
				"zone_id": "${OS_DNS_ZONEID}",
				"name": "${MASTERKUBE_NODE}"
			}
EOF
		fi

	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_vm_by_name() {
    local VMNAME=$1

    if [ "$(openstack server show "${VMNAME}" 2>/dev/null)" ]; then
        echo_blue_bold "Delete VM: ${VMNAME}"
		openstack server delete --force --wait ${VMNAME} #2>/dev/null
	fi

    delete_host "${VMNAME}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function unregister_dns() {
	# Delete DNS entries
	for FILE in ${TARGET_CONFIG_LOCATION}/dns-*.json
	do
        if [ -f ${FILE} ]; then
			DNS_ENTRY_ID=$(cat ${FILE} | jq -r '.id // ""')
			ZONEID=$(cat ${FILE} | jq -r '.zone_id // ""')

			if [ -n "${DNS_ENTRY_ID}" ]; then
				openstack recordset delete ${ZONEID} ${DNS_ENTRY_ID} 2>/dev/null
			fi
		fi
	done

    echo
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function update_build_env() {
    set +u
cat ${PLATEFORMDEFS} > ${TARGET_CONFIG_LOCATION}/buildenv

cat > ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
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
export CONTROLNODES=${CONTROLNODES}
export CORESTOTAL="${CORESTOTAL}"
export DOMAIN_NAME=${DOMAIN_NAME}
export EXTERNAL_ETCD=${EXTERNAL_ETCD}
export FIRSTNODE=${FIRSTNODE}
export GRPC_PROVIDER=${GRPC_PROVIDER}
export HA_CLUSTER=${HA_CLUSTER}
export KUBECONFIG=${KUBECONFIG}
export KUBERNETES_DISTRO=${KUBERNETES_DISTRO}
export KUBERNETES_PASSWORD=${KUBERNETES_PASSWORD}
export KUBERNETES_USER=${KUBERNETES_USER}
export KUBERNETES_VERSION=${KUBERNETES_VERSION}
export LAUNCH_CA=${LAUNCH_CA}
export MASTER_NODE_ALLOW_DEPLOYMENT=${MASTER_NODE_ALLOW_DEPLOYMENT}
export MASTERKUBE="${MASTERKUBE}"
export MAXAUTOPROVISIONNEDNODEGROUPCOUNT=${MAXAUTOPROVISIONNEDNODEGROUPCOUNT}
export MAXNODES=${MAXNODES}
export MAXTOTALNODES=${MAXTOTALNODES}
export MEMORYTOTAL="${MEMORYTOTAL}"
export METALLB_IP_RANGE=${METALLB_IP_RANGE}
export MINNODES=${MINNODES}
export PRIVATE_DNS=${PRIVATE_DNS}
export PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}
export PRIVATE_GATEWAY=${PRIVATE_GATEWAY}
export PRIVATE_NET_INF=${PRIVATE_NET_INF}
export PRIVATE_IP=${PRIVATE_IP}
export PRIVATE_MASK_CIDR=${PRIVATE_MASK_CIDR}
export PRIVATE_NETMASK=${PRIVATE_NETMASK}
export NETWORK_PRIVATE_ROUTES=(${NETWORK_PRIVATE_ROUTES[@]})
export NETWORK_PUBLIC_ROUTES=(${NETWORK_PUBLIC_ROUTES[@]})
export NFS_SERVER_ADDRESS=${NFS_SERVER_ADDRESS}
export NFS_SERVER_PATH=${NFS_SERVER_PATH}
export NFS_STORAGE_CLASS=${NFS_STORAGE_CLASS}
export NGINX_MACHINE=${NGINX_MACHINE}
export NODEGROUP_NAME="${NODEGROUP_NAME}"
export OSDISTRO=${OSDISTRO}
export PLATEFORM="${PLATEFORM}"
export PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
export PUBLIC_IP="${PUBLIC_IP}"
export REGION=${REGION}
export REGISTRY=${REGISTRY}
export RESUME=${RESUME}
export ROOT_IMG_NAME=${ROOT_IMG_NAME}
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
export USE_KEEPALIVED=${USE_KEEPALIVED}
export USE_ZEROSSL=${USE_ZEROSSL}
export VC_NETWORK_PRIVATE=${VC_NETWORK_PRIVATE}
export VC_NETWORK_PUBLIC=${VC_NETWORK_PUBLIC}
export WORKERNODES=${WORKERNODES}
export ZONEID=${ZONEID}
EOF
    set -u
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