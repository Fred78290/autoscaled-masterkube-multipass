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
function plateform_create_vm() {
	local INDEX=$1
	local EXTERNAL_IP=$2
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
					"eth0": {
						"gateway4": "${PRIVATE_GATEWAY}",
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
			NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --argjson ROUTES "${PRIVATE_ROUTES_DEFS}" '.network.ethernets.eth0.routes = $ROUTES')
		fi

		if [ ${EXTERNAL_IP} != "NONE" ]; then
			if [ "${EXTERNAL_IP}" = "DHCP" ]; then
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
					--arg USE_DHCP_ROUTES_PUBLIC "${USE_DHCP_ROUTES_PUBLIC}" \
					'.|.network.ethernets += { "eth1": { "dhcp4": true, "dhcp4-overrides": { "use-routes": $USE_DHCP_ROUTES_PUBLIC } } }')
			else
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
					--arg PRIVATE_GATEWAY ${PRIVATE_GATEWAY} \
					--arg NODE_IP "${EXTERNAL_IP}/${PUBLIC_MASK_CIDR}" \
					--arg PRIVATE_DNS ${PRIVATE_DNS} \
					'.|.network.ethernets += { "eth1": { "gateway4": $PRIVATE_GATEWAY, "addresses": [ $NODE_IP ], "nameservers": { "addresses": [ $PRIVATE_DNS ] } }}')
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
				register_dns ${INDEX} ${NODE_IP} ${MASTERKUBE_NODE}
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

	cat >> ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
export AUTOSCALER_DESKTOP_UTILITY_ADDR=${AUTOSCALER_DESKTOP_UTILITY_ADDR}
export AUTOSCALER_DESKTOP_UTILITY_CACERT=${AUTOSCALER_DESKTOP_UTILITY_CACERT}
export AUTOSCALER_DESKTOP_UTILITY_CERT=${AUTOSCALER_DESKTOP_UTILITY_CERT}
export AUTOSCALER_DESKTOP_UTILITY_KEY=${AUTOSCALER_DESKTOP_UTILITY_CERT}
export AUTOSCALER_DESKTOP_UTILITY_TLS=${AUTOSCALER_DESKTOP_UTILITY_TLS}
EOF
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
