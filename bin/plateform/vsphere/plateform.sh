CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl govc"
SEED_ARCH=amd64
FOLDER_OPTIONS=

source ${PLATEFORMDEFS}

export VSPHERE_START_DELAY=10
export VSPHERE_STOP_DELAY=10

if [ "${GOVC_INSECURE}" == "1" ]; then
	export INSECURE=true
else
	export INSECURE=false
fi

if [ "${GOVC_FOLDER}" ]; then
    if [ ! $(govc folder.info ${GOVC_FOLDER} | grep -m 1 Path | wc -l) -eq 1 ]; then
        FOLDER_OPTIONS="-folder=/${GOVC_DATACENTER}/vm/${GOVC_FOLDER}"
    fi
fi

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

  # Flags to configure network in ${PLATEFORM}
--use-nlb=[none|keepalived|nginx]              # Use keepalived or NGINX as load balancer
--vm-private-network=<value>                   # Override the name of the private network in ${PLATEFORM}, default: ${VC_NETWORK_PRIVATE}
--vm-public-network=<value>                    # Override the name of the public network in ${PLATEFORM}, empty for none second interface, default: ${VC_NETWORK_PUBLIC}
--no-dhcp-autoscaled-node                      # Autoscaled node don't use DHCP, default: ${SCALEDNODES_DHCP}
--dhcp-autoscaled-node                         # Autoscaled node use DHCP, default: ${SCALEDNODES_DHCP}
--net-address=<ipv4/cidr>                      # Override the IP of the kubernetes control plane node, default: ${PRIVATE_IP}/${PRIVATE_MASK_CIDR}
--net-gateway=<value>                          # Override the IP gateway, default: ${PRIVATE_GATEWAY}
--net-gateway-metric=<value>                   # Override the IP gateway metric, default: ${PRIVATE_GATEWAY_METRIC}
--net-dns=<value>                              # Override the IP DNS, default: ${PRIVATE_DNS}

--public-address=<value>                       # The public address to expose kubernetes endpoint[ipv4/cidr, DHCP, NONE], default: ${PUBLIC_IP}
--metallb-ip-range                             # Override the metalb ip range, default: ${METALLB_IP_RANGE}
--dont-use-dhcp-routes-private                 # Tell if we don't use DHCP routes in private network, default: ${USE_DHCP_ROUTES_PRIVATE}
--dont-use-dhcp-routes-public                  # Tell if we don't use DHCP routes in public network, default: ${USE_DHCP_ROUTES_PUBLIC}
--add-route-private                            # Add route to private network syntax is --add-route-private=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-private=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default: ${NETWORK_PRIVATE_ROUTES[@]}
--add-route-public                             # Add route to public network syntax is --add-route-public=to=X.X.X.X/YY,via=X.X.X.X,metric=100 --add-route-public=to=Y.Y.Y.Y/ZZ,via=X.X.X.X,metric=100, default: ${NETWORK_PUBLIC_ROUTES[@]}

EOF
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
function last_startorder() {
	local LASTORDER=$(govc host.autostart.info -host=$1 -json | jq -r '.config.powerInfo[]|.startOrder' | sort -u | tail -n 1)

	LASTORDER=${LASTORDER:=0}

	if [ ${LASTORDER} -lt 0 ]; then
		LASTORDER=0
	fi

	echo -n "${LASTORDER}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_autostart_ordered() {
	local FIRSTNODE=$1
	local LASTNODE=$2
	local INDEX=

	for INDEX in $(seq ${FIRSTNODE} ${LASTNODE})
	do
		local VMNAME=$(get_vm_name ${INDEX})
		local VMHOST=$(govc vm.info "${VMNAME}" | grep 'Host:' | awk '{print $2}')
		local VMORDER=$(($(last_startorder ${VMHOST}) + 1))

		echo_blue_bold "Set autostart order for VM: ${VMNAME} to: ${VMORDER}"
		eval govc host.autostart.add -start-order=${VMORDER} -start-delay=${VSPHERE_START_DELAY} -stop-delay=${VSPHERE_STOP_DELAY} -host="${VMHOST}" "${VMNAME}" ${SILENT}
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
			elif [ -z "${PUBLIC_GATEWAY}" ] && [ -z "${PUBLIC_DNS}" ]; then
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
					--arg NODE_IP "${PUBLIC_IP}/${PUBLIC_MASK_CIDR}" \
					'.|.network.ethernets += { "eth1": { "addresses": [ $NODE_IP ] }}')
			else
				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq \
					--arg NODE_IP "${PUBLIC_IP}/${PUBLIC_MASK_CIDR}" \
					--arg PUBLIC_DNS ${PUBLIC_DNS} \
					'.|.network.ethernets += { "eth1": { "addresses": [ $NODE_IP ], "nameservers": { "addresses": [ $PUBLIC_DNS ] } }}')
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
		govc vm.clone -link=false -on=false ${FOLDER_OPTIONS} -c=${NUM_VCPUS} -m=${MEMSIZE} -vm=${TARGET_IMAGE} ${MASTERKUBE_NODE} > /dev/null
		govc vm.disk.change ${FOLDER_OPTIONS} -vm ${MASTERKUBE_NODE} -size="${DISK_SIZE}MB" > /dev/null

		echo_title "Set cloud-init settings for ${MASTERKUBE_NODE}"

		# Inject cloud-init elements
		eval govc vm.change -vm "${MASTERKUBE_NODE}" \
			-e guestinfo.metadata="$(cat ${TARGET_CONFIG_LOCATION}/metadata-${INDEX}.base64)" \
			-e guestinfo.metadata.encoding="gzip+base64" \
			-e guestinfo.userdata="$(cat ${TARGET_CONFIG_LOCATION}/userdata-${INDEX}.base64)" \
			-e guestinfo.userdata.encoding="gzip+base64" \
			-e guestinfo.vendordata="$(cat ${TARGET_CONFIG_LOCATION}/vendordata.base64)" \
			-e guestinfo.vendordata.encoding="gzip+base64" ${SILENT}

		govc vm.network.change -vm "${MASTERKUBE_NODE}" -net="${VC_NETWORK_PRIVATE}" -net.adapter="vmxnet3" ethernet-0

		NUM_ETHERNET=$(govc device.info -vm ${MASTERKUBE_NODE} -json | jq '[.devices[]|select(.backing.network.type == "Network")]|length')

		if [ -n "${VC_NETWORK_PUBLIC}" ]; then
			if [ ${NUM_ETHERNET} -lt 2 ]; then
				echo_blue_bold "Add second network ${VC_NETWORK_PUBLIC} on ${MASTERKUBE_NODE}"
				govc vm.network.add -vm "${MASTERKUBE_NODE}" -net="${VC_NETWORK_PUBLIC}" -net.adapter="vmxnet3"
			else
				echo_blue_bold "Change second network interface to ${VC_NETWORK_PUBLIC} on ${MASTERKUBE_NODE}"
				govc vm.network.change -vm "${MASTERKUBE_NODE}" -net="${VC_NETWORK_PUBLIC}" -net.adapter="vmxnet3" ethernet-1
			fi
		elif [ ${NUM_ETHERNET} -gt 1 ]; then
			govc device.remove "${MASTERKUBE_NODE}" ethernet-1
		fi

		echo_title "Power On ${MASTERKUBE_NODE}"

		eval govc vm.power -on "${MASTERKUBE_NODE}" ${SILENT}

		echo_title "Wait for IP from ${MASTERKUBE_NODE}"

		PRIVATE_IP=$(govc vm.ip -wait 5m "${MASTERKUBE_NODE}")
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
	local MASTERKUBE_NODE_UUID=$(get_vmuuid "${MASTERKUBE_NODE}")
	local PRIVATE_IP=$(govc vm.info -json "${MASTERKUBE_NODE}" | jq -r --arg NETWORK "${VC_NETWORK_PRIVATE}" '.virtualMachines[0].guest.net[]|select(.network == $NETWORK)|.ipConfig.ipAddress[]|select(.prefixLength == 24)|.ipAddress')
	local SUFFIX=$(named_index_suffix ${INDEX})

	if [ ${PUBLIC_IP} == "NONE" ]; then
		PUBLIC_IP=${PRIVATE_IP}
	elif [ ${PUBLIC_IP} == "DHCP" ]; then
		PUBLIC_IP=$(govc vm.info -json "${MASTERKUBE_NODE}" | jq -r --arg NETWORK "${VC_NETWORK_PUBLIC}" '.virtualMachines[0].guest.net[]|select(.network == $NETWORK)|.ipConfig.ipAddress[]|select(.prefixLength == 24)|.ipAddress')
	fi

	PRIVATE_ADDR_IPS[${INDEX}]=${PRIVATE_IP}
    PUBLIC_ADDR_IPS[${INDEX}]=${PUBLIC_IP}
    PRIVATE_DNS_NAMES[${INDEX}]=${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}

	cat > ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json <<EOF
{
	"Index": ${INDEX},
	"InstanceName": "${MASTERKUBE_NODE}",
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

    if [ "$(govc vm.info ${VMNAME} 2>&1)" ]; then
        echo_blue_bold "Delete VM: ${VMNAME}"
        govc vm.power -persist-session=false -s ${VMNAME} || echo_blue_bold "Already power off"
        govc vm.destroy ${VMNAME}
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

    echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE "${TARGET_IMAGE}" '.template-name = $TARGET_IMAGE' > ${TARGET_CONFIG_LOCATION}/provider.json
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vmuuid() {
    local VMNAME=$1

    echo -n $(govc vm.info -json ${VMNAME} 2>/dev/null | jq -r '.virtualMachines[0].config.uuid//""')
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_net_type() {
    echo -n "custom"
}