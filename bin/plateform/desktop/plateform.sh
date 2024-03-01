if [ "${OSDISTRO}" == "Darwin" ]; then
    PATH=${HOME}/Library/DesktopAutoscalerUtility:${PATH}
else
    PATH=${HOME}/.local/vmware:${PATH}
fi

export TRACE_CURL=NO
export TRACE_FILE_CURL="utility-$(date +%s).log"

CMD_MANDATORIES="helm kubectl vmrun vmrest jq yq cfssl ovftool kubernetes-desktop-autoscaler-utility vmware-vdiskmanager"
CLOUD_PROVIDER=

AUTOSCALER_DESKTOP_UTILITY_TLS=$(kubernetes-desktop-autoscaler-utility certificate generate)
AUTOSCALER_DESKTOP_UTILITY_KEY="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientKey)"
AUTOSCALER_DESKTOP_UTILITY_CERT="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientCertificate)"
AUTOSCALER_DESKTOP_UTILITY_CACERT="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .Certificate)"
AUTOSCALER_DESKTOP_UTILITY_ADDR=${LOCAL_IPADDR}:5701

if [ "${LAUNCH_CA}" == YES ]; then
    AUTOSCALER_DESKTOP_UTILITY_CERT="/etc/ssl/certs/autoscaler-utility/$(basename ${AUTOSCALER_DESKTOP_UTILITY_CERT})"
    AUTOSCALER_DESKTOP_UTILITY_KEY="/etc/ssl/certs/autoscaler-utility/$(basename ${AUTOSCALER_DESKTOP_UTILITY_KEY})"
    AUTOSCALER_DESKTOP_UTILITY_CACERT="/etc/ssl/certs/autoscaler-utility/$(basename ${AUTOSCALER_DESKTOP_UTILITY_CACERT})"
fi

if [ "${OSDISTRO}" == "Darwin" ] && [ -z "$(command -v vmware-vdiskmanager)" ]; then
	sudo ln -s /Applications/VMware\ Fusion.app/Contents/Library/vmware-vdiskmanager /usr/local/bin/vmware-vdiskmanager
fi

source ${CURDIR}/vmrest-utility.sh

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_vm() {
	local INDEX=$1
	local PUBLIC_NODE_IP=$2
	local NODE_IP=$3
	local MACHINE_TYPE=
	local MASTERKUBE_NODE=
	local MASTERKUBE_NODE_UUID=
	local IPADDR=
	local VMHOST=
	local DISK_SIZE=
	local NUM_VCPUS=
	local MEMSIZE=

	MACHINE_TYPE=$(get_machine_type ${INDEX})
	MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})

	if [ -z "${MASTERKUBE_NODE_UUID}" ]; then
		NETWORK_DEFS=$(cat <<EOF
		{
			"instance-id": "$(uuidgen)",
			"local-hostname": "${MASTERKUBE_NODE}",
			"hostname": "${MASTERKUBE_NODE}.${NET_DOMAIN}",
			"network": {
				"version": 2,
				"ethernets": {
					"eth0": {
						"gateway4": "${NET_GATEWAY}",
						"addresses": [
							"${NODE_IP}/${NET_MASK_CIDR}"
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

		if [ ${#NETWORK_PRIVATE_ROUTES[@]} -gt 0 ]; then
			NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --argjson ROUTES "${PRIVATE_ROUTES_DEFS}" '.network.ethernets.eth0.routes = $ROUTES')
		fi

		if [ ${PUBLIC_NODE_IP} != "NONE" ]; then
			if [ "${PUBLIC_NODE_IP}" = "DHCP" ]; then
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
					--arg USE_DHCP_ROUTES_PUBLIC "${USE_DHCP_ROUTES_PUBLIC}" \
					'.|.network.ethernets += { "eth1": { "dhcp4": true, "dhcp4-overrides": { "use-routes": $USE_DHCP_ROUTES_PUBLIC } } }')
			else
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
					--arg NET_GATEWAY ${NET_GATEWAY} \
					--arg NODE_IP "${PUBLIC_NODE_IP}/${PUBLIC_MASK_CIDR}" \
					--arg NET_DNS ${NET_DNS} \
					'.|.network.ethernets += { "eth1": { "gateway4": $NET_GATEWAY, "addresses": [ $NODE_IP ], "nameservers": { "addresses": [ $NET_DNS ] } }}')
			fi

			if [ ${#NETWORK_PUBLIC_ROUTES[@]} -gt 0 ]; then
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --argjson ROUTES "${PUBLIC_ROUTES_DEFS}" '.network.ethernets.eth1.routes = $ROUTES')
			fi
		fi

		echo ${NETWORK_DEFS} | jq . > ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.json

		# Cloud init meta-data
		echo "#cloud-config" > ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.yaml
		echo ${NETWORK_DEFS} | yq -p json -P | tee ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.yaml > /dev/null

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
runcmd:
- echo "Create ${MASTERKUBE_NODE}" > /var/log/masterkube.log
EOF

		gzip -c9 <${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.json | base64 -w 0 | tee > ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.base64
		gzip -c9 <${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.yaml | base64 -w 0 | tee > ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.base64

		read MEMSIZE NUM_VCPUS DISK_SIZE <<<"$(jq -r --arg MACHINE ${MACHINE_TYPE} '.[$MACHINE]|.memsize,.vcpus,.disksize' templates/setup/${PLATEFORM}/machines.json | tr '\n' ' ')"

		if [ -z "${MEMSIZE}" ] || [ -z "${NUM_VCPUS}" ] || [ -z "${DISK_SIZE}" ]; then
			echo_red_bold "MACHINE_TYPE=${MACHINE_TYPE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE} not correctly defined"
			exit 1
		fi

		echo_line
		echo_blue_bold "Clone ${TARGET_IMAGE} to ${MASTERKUBE_NODE} TARGET_IMAGE=${TARGET_IMAGE} MASTERKUBE_NODE=${MASTERKUBE_NODE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE}M"
		echo_line

		# Clone my template
		MASTERKUBE_NODE_UUID=$(vmrest_create ${TARGET_IMAGE_UUID} ${NUM_VCPUS} ${MEMSIZE} ${MASTERKUBE_NODE} ${DISK_SIZE} "${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.base64" "${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.base64" "${TARGET_CONFIG_LOCATION}/vendordata.base64" false ${AUTOSTART})

		if [ -z "${MASTERKUBE_NODE_UUID}" ] || [ "${MASTERKUBE_NODE_UUID}" == "ERROR" ]; then
			echo_red_bold "Failed to clone ${TARGET_IMAGE} to ${MASTERKUBE_NODE}"
			exit 1
		else
			if [ -n "${VC_NETWORK_PUBLIC}" ]; then
				echo_blue_bold "Add second network card ${VC_NETWORK_PUBLIC} on ${MASTERKUBE_NODE}"
				vmrest_network_add ${MASTERKUBE_NODE_UUID} ${VC_NETWORK_PUBLIC} > /dev/null
			fi

			echo_title "Power On ${MASTERKUBE_NODE}"

			POWER_STATE=$(vmrest_wait_for_poweron "${MASTERKUBE_NODE_UUID}")

			if [ "${POWER_STATE}" != "poweredOn" ]; then
				echo_red_bold "Fail to start ${MASTERKUBE_NODE}: ${POWER_STATE}"
				exit 1
			else
				echo_title "Wait for IP from ${MASTERKUBE_NODE}"

				IPADDR=$(vmrest_waitip "${MASTERKUBE_NODE_UUID}")

				if [ ${IPADDR} == "ERROR" ]; then
					echo_red_bold "Failed to get ip for ${MASTERKUBE_NODE}"
					exit 1
				fi

				echo_title "Wait ssh ready on ${KUBERNETES_USER}@${IPADDR}"
				wait_ssh_ready ${KUBERNETES_USER}@${IPADDR}

				echo_title "Prepare ${MASTERKUBE_NODE} instance with IP:${IPADDR}"
				eval scp ${SCP_OPTIONS} tools ${KUBERNETES_USER}@${IPADDR}:~ ${SILENT}
				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} mkdir -p /home/${KUBERNETES_USER}/cluster ${SILENT}
				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo chown -R root:adm /home/${KUBERNETES_USER}/tools ${SILENT}
				eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo cp /home/${KUBERNETES_USER}/tools/* /usr/local/bin ${SILENT}

				# Update /etc/hosts
				delete_host "${MASTERKUBE_NODE}"
				add_host ${NODE_IP} ${MASTERKUBE_NODE} ${MASTERKUBE_NODE}.${DOMAIN_NAME}
			fi
		fi
	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"
	fi

	#echo_separator
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_vm_by_name() {
    local VMNAME=$1
    local VMUUID=$(vmrest_get_vmuuid ${VMNAME})

    if [ -n "${VMUUID}" ]; then
		echo_blue_bold "Delete VM: ${VMNAME}"
		vmrest_poweroff ${VMUUID} hard &> /dev/null
		vmrest_wait_for_powerstate ${VMUUID} "poweredOff" &> /dev/null
		vmrest_destroy ${VMUUID} &> /dev/null
	fi

    delete_host "${VMNAME}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function unregister_dns() {
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
export DASHBOARD_HOSTNAME=${DASHBOARD_HOSTNAME}
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
export NET_DNS=${NET_DNS}
export NET_DOMAIN=${NET_DOMAIN}
export NET_GATEWAY=${NET_GATEWAY}
export NET_IF=${NET_IF}
export NET_IP=${NET_IP}
export NET_MASK_CIDR=${NET_MASK_CIDR}
export NET_MASK=${NET_MASK}
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

	echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE ${TARGET_IMAGE_UUID} "template-name = $TARGET_IMAGE" > ${TARGET_CONFIG_LOCATION}/provider.json
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vmuuid() {
    echo -n $(vmrest_get_vmuuid $1)
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_net_type() {
    echo -n $(vmrest_get_net_type $1)
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vmnet_subnet() {
	local VMNETNUM=$1
	local OSDISTRO="$(uname -s)"

	VMNETNUM=${VMNETNUM:5}

	if [ "${OSDISTRO}" == "Darwin" ]; then
		NETWORKING_CONF="/Library/Preferences/VMware Fusion/networking"
	else
		NETWORKING_CONF="/etc/vmware/networking"
	fi

	set +u

	$(grep VNET "${NETWORKING_CONF}" | sed -e 's/ /=/g' -e 's/answer=/export /g')

	VNET_HOSTONLY_SUBNET=VNET_${VMNETNUM}_HOSTONLY_SUBNET
	eval VNET_HOSTONLY_SUBNET=\$$VNET_HOSTONLY_SUBNET

	VNET_DHCP=VNET_${VMNETNUM}_DHCP
	eval VNET_DHCP=\$$VNET_DHCP

	if [ "${VNET_DHCP}" == "yes" ]; then
		VNET_HOSTONLY_SUBNET=${VNET_HOSTONLY_SUBNET%.*}
	else
		local INF=$(grep add_bridge_mapping "${NETWORKING_CONF}" | grep " ${VMNETNUM}" | cut -d ' ' -f 2)

		if [ "${OSDISTRO}" == "Darwin" ]; then
			read -a LOCAL_IPADDR <<< "$(ifconfig ${INF} | grep -m 1 "inet\s" | sed -n 1p)"
		else
			read -a LOCAL_IPADDR <<< "$(ip addr show ${INF} | grep -m 1 "inet\s" | tr '/' ' ')"
		fi
		
		VNET_HOSTONLY_SUBNET="${LOCAL_IPADDR[1]}"
		VNET_HOSTONLY_SUBNET=${VNET_HOSTONLY_SUBNET%.*}
	fi

	set -u

	echo -n ${VNET_HOSTONLY_SUBNET}
}
