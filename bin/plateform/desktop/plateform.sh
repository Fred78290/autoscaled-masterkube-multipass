if [ "${OSDISTRO}" == "Darwin" ]; then
    PATH=${HOME}/Library/DesktopAutoscalerUtility:${PATH}
else
    PATH=${HOME}/.local/vmware:${PATH}
fi


CMD_MANDATORIES="helm kubectl vmrun vmrest jq yq cfssl ovftool kubernetes-desktop-autoscaler-utility vmware-vdiskmanager"
CLOUD_PROVIDER=
DEPLOY_MODE="$(hostname | cut -d '.' -f 1 | cut -d '-' -f 1)"

source ${CURDIR}/vmrest-utility.sh

AUTOSCALER_DESKTOP_UTILITY_ADDR=${LOCAL_IPADDR}:5701

if [ "${LAUNCH_CA}" == YES ]; then
    AUTOSCALER_DESKTOP_UTILITY_KEY="/etc/ssl/certs/autoscaler-utility/$(basename ${LOCAL_AUTOSCALER_DESKTOP_UTILITY_KEY})"
    AUTOSCALER_DESKTOP_UTILITY_CERT="/etc/ssl/certs/autoscaler-utility/$(basename ${LOCAL_AUTOSCALER_DESKTOP_UTILITY_CERT})"
    AUTOSCALER_DESKTOP_UTILITY_CACERT="/etc/ssl/certs/autoscaler-utility/$(basename ${LOCAL_AUTOSCALER_DESKTOP_UTILITY_CACERT})"
else
	AUTOSCALER_DESKTOP_UTILITY_KEY="${LOCAL_AUTOSCALER_DESKTOP_UTILITY_KEY}"
	AUTOSCALER_DESKTOP_UTILITY_CERT="${LOCAL_AUTOSCALER_DESKTOP_UTILITY_CERT}"
	AUTOSCALER_DESKTOP_UTILITY_CACERT="${LOCAL_AUTOSCALER_DESKTOP_UTILITY_CACERT})"
fi

if [ "${OSDISTRO}" == "Darwin" ] && [ -z "$(command -v vmware-vdiskmanager)" ]; then
	sudo ln -s /Applications/VMware\ Fusion.app/Contents/Library/vmware-vdiskmanager /usr/local/bin/vmware-vdiskmanager
fi

source ${PLATEFORMDEFS}

#===========================================================================================================================================
#
#===========================================================================================================================================
function parsed_arguments() {
	VPC_PUBLIC_SUBNET_IDS=(${VC_NETWORK_PUBLIC})
	VPC_PRIVATE_SUBNET_IDS=(${VC_NETWORK_PRIVATE})

	local METALLB_IP_RANGE_START=$((PRIVATE_IP_START + 8))
	local METALLB_IP_RANGE_END=$((METALLB_IP_RANGE_START + 1))

	if [ -n "${VC_NETWORK_PUBLIC}" ] && [ "${PUBLIC_IP}" != "NONE" ]; then
		VNET_HOSTONLY_SUBNET=$(get_vmnet_subnet ${VC_NETWORK_PUBLIC})

		if [ -z "${VNET_HOSTONLY_SUBNET}" ]; then
			echo_red_bold "Can't determine VNET_HOSTONLY_SUBNET for ${VC_NETWORK_PUBLIC}"
		fi

		if [ -z "${METALLB_IP_RANGE}" ]; then
			METALLB_IP_RANGE=${VNET_HOSTONLY_SUBNET}.78-${VNET_HOSTONLY_SUBNET}.79
		fi

		if [ "${PUBLIC_IP}" != "DHCP" ]; then
			PUBLIC_IP=${VNET_HOSTONLY_SUBNET}.${PRIVATE_IP_START}/24
		fi
	fi

	if [ -n ${VC_NETWORK_PRIVATE} ]; then
		VNET_HOSTONLY_SUBNET=$(get_vmnet_subnet ${VC_NETWORK_PRIVATE})

		if [ -z "${VNET_HOSTONLY_SUBNET}" ]; then
			echo_red_bold "Can't determine VNET_HOSTONLY_SUBNET for ${VC_NETWORK_PRIVATE}"
		fi

		if [ -z "${METALLB_IP_RANGE}" ]; then
			METALLB_IP_RANGE=${VNET_HOSTONLY_SUBNET}.${METALLB_IP_RANGE_START}-${VNET_HOSTONLY_SUBNET}.${METALLB_IP_RANGE_END}
		fi

		PRIVATE_GATEWAY=${VNET_HOSTONLY_SUBNET}.2
		PRIVATE_IP=${VNET_HOSTONLY_SUBNET}.${PRIVATE_IP_START}
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
			"hostname": "${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}",
			"network": {
				"version": 2,
				"ethernets": {
					"${PRIVATE_NET_INF}": {
						"addresses": [
							"${NODE_IP}/${PRIVATE_MASK_CIDR}"
						],
						"nameservers": {
							"addresses": [
								"${PRIVATE_DNS}"
							]
						}
					}
				}
			}
		}
EOF
)

		if [ ${#NETWORK_PRIVATE_ROUTES[@]} -gt 0 ]; then
#			NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --arg PRIVATE_NET_INF "${PRIVATE_NET_INF}" --argjson ROUTES "${PRIVATE_ROUTES_DEFS}" '.network.ethernets.[$PRIVATE_NET_INF].routes = $ROUTES')
			NETWORK_DEFS=$(jq --argjson JSONPATH "[\"network\", \"ethernets\", \"$PRIVATE_NET_INF\", \"routes\"]" --argjson ROUTES "${PRIVATE_ROUTES_DEFS}" 'setpath($JSONPATH; $ROUTES)' <<< "${NETWORK_DEFS}")
		fi

		if [ ${PUBLIC_IP} != "NONE" ]; then
			if [ "${PUBLIC_IP}" = "DHCP" ]; then
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
					--arg USE_DHCP_ROUTES_PUBLIC "${USE_DHCP_ROUTES_PUBLIC}" \
					'.|.network.ethernets += { "eth1": { "dhcp4": true, "dhcp4-overrides": { "use-routes": $USE_DHCP_ROUTES_PUBLIC } } }')
			else
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
					--arg NODE_IP "${PUBLIC_IP}/${PUBLIC_MASK_CIDR}" \
					--arg PRIVATE_DNS ${PRIVATE_DNS} \
					'.|.network.ethernets += { "eth1": { "addresses": [ $NODE_IP ], "nameservers": { "addresses": [ $PRIVATE_DNS ] } }}')
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
		echo_blue_bold "Clone ${TARGET_IMAGE}:${TARGET_IMAGE_UUID} to ${MASTERKUBE_NODE} TARGET_IMAGE=${TARGET_IMAGE} MASTERKUBE_NODE=${MASTERKUBE_NODE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE}M"
		echo_line

		# Clone my template
		MASTERKUBE_NODE_UUID=$(vmrest_create \
			${TARGET_IMAGE_UUID} \
			${NUM_VCPUS} \
			${MEMSIZE} \
			${MASTERKUBE_NODE} \
			${DISK_SIZE} \
			"${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.base64" \
			"${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.base64" \
			"${TARGET_CONFIG_LOCATION}/vendordata.base64" \
			false \
			${AUTOSTART})

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
			fi
		fi
	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"

		IPADDR=$(vmrest_waitip "${MASTERKUBE_NODE_UUID}")
	fi

	PRIVATE_ADDR_IPS[${INDEX}]=${NODE_IP}
	#echo_separator
}
#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_info_vm() {
	local INDEX=$1
	local PUBLIC_IP=$2
	local NODE_IP=$3
	local MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	local MASTERKUBE_NODE_UUID=$(vmrest_get_vmuuid ${MASTERKUBE_NODE})
	local SUFFIX=$(named_index_suffix $1)
	local VMNIC=$(vmrest_get_vmnic ${MASTERKUBE_NODE_UUID})
	local VMNICIPS=$(vmrest_get_vmnicips ${MASTERKUBE_NODE_UUID})
	local MACADDRESS=$(echo ${VMNIC} | jq -r --arg NETWORK "${VC_NETWORK_PRIVATE}" '.nics[]|select(.vmnet == $NETWORK)|.macAddress')
	local PRIVATE_IP=$(echo ${VMNICIPS} | jq -r --arg MACADDRESS "${MACADDRESS}" '.nics[]|select(.mac == $MACADDRESS)|.ip|first' | cut -d '/' -f 1)

	if [ ${PUBLIC_IP} == "NONE" ]; then
		PUBLIC_IP=${PRIVATE_IP}
	elif [ ${PUBLIC_IP} == "DHCP" ]; then
		MACADDRESS=$(echo ${VMNIC} | jq -r --arg NETWORK "${VC_NETWORK_PUBLIC}" '.nics[]|select(.vmnet == $NETWORK)|.macAddress')
		PUBLIC_IP=$(echo ${VMNICIPS} | jq -r --arg MACADDRESS "${MACADDRESS}" '.nics[]|select(.mac == $MACADDRESS)|.ip|first' | cut -d '/' -f 1)
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
function update_build_env() {
	save_buildenv
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
	local LOCAL_IPADDR=

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
