CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl kubernetes-desktop-autoscaler-utility packer qemu-img"
PRIVATE_NET_INF=eth1 # eth0 is multipass interface
CLOUD_PROVIDER=
PRIVATE_GATEWAY_METRIC=250

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

if [ -n "${VC_NETWORK_PRIVATE}" ]; then
	SUBNET=$(ipv4 ${VC_NETWORK_PRIVATE})
	SUBNET=${SUBNET%.*}

	METALLB_IP_RANGE=${SUBNET}.20-${SUBNET}.24
	PRIVATE_GATEWAY=${SUBNET}.1
	PRIVATE_IP=${SUBNET}.10
fi

if [ -n "${VC_NETWORK_PUBLIC}" ] && [ ${PUBLIC_IP} != "NONE" ]; then
	SUBNET=$(ipv4 ${VC_NETWORK_PUBLIC})
	SUBNET=${SUBNET%.*}

	METALLB_IP_RANGE=${SUBNET}.20-${SUBNET}.24

	if [ ${PUBLIC_IP} != "DHCP" ]; then
		PUBLIC_IP=${SUBNET}.10/24
	fi
fi

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
	local SUFFIX=

	MACHINE_TYPE=$(get_machine_type ${INDEX})
	MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})
	SUFFIX=$(named_index_suffix $1)

	if [ -z "${MASTERKUBE_NODE_UUID}" ]; then
		NETWORK_DEFS=$(cat <<EOF
		{
			"network": {
				"version": 2,
				"ethernets": {
					"eth1": {
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
			NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --argjson ROUTES "${PRIVATE_ROUTES_DEFS}" '.network.ethernets.eth1.routes = $ROUTES')
		fi

		if [ ${PUBLIC_IP} != "DHCP" ] && [ ${PUBLIC_IP} != "NONE" ]; then
			NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
				--arg NODE_IP "${PUBLIC_IP}/${PUBLIC_MASK_CIDR}" \
				'.|.network.ethernets += { "eth0": { "dhcp4": true, "addresses": [{ ($NODE_IP): { "label": "eth0:1" } }]}}')

			if [ ${#NETWORK_PUBLIC_ROUTES[@]} -gt 0 ]; then
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --argjson ROUTES "${PUBLIC_ROUTES_DEFS}" '.network.ethernets.eth0.routes = $ROUTES')
			fi
		fi

		echo ${NETWORK_DEFS} | jq . > ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.json

		# Cloud init meta-data
		NETWORKCONFIG=$(echo ${NETWORK_DEFS} | yq -p json -P | tee ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.yaml | gzip -c9 | base64 -w 0 | tee ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.base64)

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
write_files:
- encoding: gzip+base64
  content: ${NETWORKCONFIG}
  owner: root:root
  path: /etc/netplan/10-custom.yaml
  permissions: '0644'
runcmd:
- hostnamectl set-hostname ${MASTERKUBE_NODE}
- netplan apply
- echo "Create ${MASTERKUBE_NODE}" > /var/log/masterkube.log
EOF

		read MEMSIZE NUM_VCPUS DISK_SIZE <<<"$(jq -r --arg MACHINE ${MACHINE_TYPE} '.[$MACHINE]|.memsize,.vcpus,.disksize' templates/setup/${PLATEFORM}/machines.json | tr '\n' ' ')"

		if [ -z "${MEMSIZE}" ] || [ -z "${NUM_VCPUS}" ] || [ -z "${DISK_SIZE}" ]; then
			echo_red_bold "MACHINE_TYPE=${MACHINE_TYPE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE} not correctly defined"
			exit 1
		fi

		echo_line
		echo_blue_bold "Clone ${TARGET_IMAGE} to ${MASTERKUBE_NODE} TARGET_IMAGE=${TARGET_IMAGE} MASTERKUBE_NODE=${MASTERKUBE_NODE} MEMSIZE=${MEMSIZE} NUM_VCPUS=${NUM_VCPUS} DISK_SIZE=${DISK_SIZE}M"
		echo_line

		# Clone my template
		echo_title "Launch ${MASTERKUBE_NODE}"
		multipass launch \
			-n ${MASTERKUBE_NODE} \
			-c ${NUM_VCPUS} \
			-m "${MEMSIZE}M" \
			-d "${DISK_SIZE}M" \
			--network name=${VC_NETWORK_PRIVATE},mode=manual \
			--cloud-init ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.yaml \
			file://${TARGET_IMAGE}
	else
		echo_title "Already running ${MASTERKUBE_NODE} instance"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_info_vm() {
	local INDEX=$1
	local PUBLIC_IP=$2
	local NODE_IP=$3
	local MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	local MASTERKUBE_NODE_UUID=$(get_vmuuid ${MASTERKUBE_NODE})
	local SUFFIX=$(named_index_suffix $1)
	local IPV4=$(multipass info "${MASTERKUBE_NODE}" --format json | jq -r --arg NAME ${MASTERKUBE_NODE} '.info|.[$NAME].ipv4')
	local PRIVATE_IP=$(echo ${IPV4} | jq -r '.|last')

	if [ ${PUBLIC_IP} == "DHCP" ] || [ ${PUBLIC_IP} == "NONE" ]; then
		PUBLIC_IP=$(echo ${IPV4} | jq -r '.|first')
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

    if [ "$(multipass info ${VMNAME} 2>/dev/null)" ]; then
        echo_blue_bold "Delete VM: ${VMNAME}"
		multipass exec ${VMNAME} -- sudo shutdown now
        multipass delete ${VMNAME} -p
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

    echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE "file://${TARGET_IMAGE}" '.template-name = $TARGET_IMAGE' > ${TARGET_CONFIG_LOCATION}/provider.json
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vmuuid() {
    local VMNAME=$1
    
    if [ -z "$(multipass info $1 2>/dev/null)" ]; then
        echo -n
    else
        echo -n $1
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_net_type() {
    echo -n "custom"
}