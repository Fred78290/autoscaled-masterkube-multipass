CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl kubernetes-desktop-autoscaler-utility packer qemu-img mkisofs"
PRIVATE_NET_INF=eth1 # eth0 is multipass interface
PUBLIC_NET_INF="eth0:1"
CLOUD_PROVIDER=
PRIVATE_GATEWAY_METRIC=250

source ${PLATEFORMDEFS}

AUTOSCALER_DESKTOP_UTILITY_TLS=$(kubernetes-desktop-autoscaler-utility certificate generate)
AUTOSCALER_DESKTOP_UTILITY_KEY="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientKey)"
AUTOSCALER_DESKTOP_UTILITY_CERT="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientCertificate)"
AUTOSCALER_DESKTOP_UTILITY_CACERT="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .Certificate)"
AUTOSCALER_DESKTOP_UTILITY_ADDR=${LOCAL_IPADDR}:5701

METALLB_IP_RANGE_START=$((PRIVATE_IP_START + 8))
METALLB_IP_RANGE_END=$((METALLB_IP_RANGE_START + 4))

if [ "${LAUNCH_CA}" == YES ]; then
    AUTOSCALER_DESKTOP_UTILITY_CERT="/etc/ssl/certs/autoscaler-utility/$(basename ${AUTOSCALER_DESKTOP_UTILITY_CERT})"
    AUTOSCALER_DESKTOP_UTILITY_KEY="/etc/ssl/certs/autoscaler-utility/$(basename ${AUTOSCALER_DESKTOP_UTILITY_KEY})"
    AUTOSCALER_DESKTOP_UTILITY_CACERT="/etc/ssl/certs/autoscaler-utility/$(basename ${AUTOSCALER_DESKTOP_UTILITY_CACERT})"
fi

if [ -n "${VC_NETWORK_PUBLIC}" ] && [ ${PUBLIC_IP} != "NONE" ]; then
	SUBNET=$(ipv4 ${VC_NETWORK_PUBLIC})
	SUBNET=${SUBNET%.*}

	if [ -z "${METALLB_IP_RANGE}" ]; then
		METALLB_IP_RANGE=${SUBNET}.${METALLB_IP_RANGE_START}-${SUBNET}.${METALLB_IP_RANGE_START}
	fi

	if [ ${PUBLIC_IP} != "DHCP" ]; then
		PUBLIC_IP=${SUBNET}.${PRIVATE_IP_START}/24
	fi
fi

if [ -n "${VC_NETWORK_PRIVATE}" ]; then
	SUBNET=$(ipv4 ${VC_NETWORK_PRIVATE})
	SUBNET=${SUBNET%.*}

	if [ -z "${METALLB_IP_RANGE}" ]; then
		METALLB_IP_RANGE=${SUBNET}.${METALLB_IP_RANGE_START}-${SUBNET}.${METALLB_IP_RANGE_START}
	fi

	PRIVATE_GATEWAY=${SUBNET}.1
	PRIVATE_DNS=${SUBNET}.1
	PRIVATE_IP=${SUBNET}.${PRIVATE_IP_START}
fi

#===========================================================================================================================================
#
#===========================================================================================================================================
function usage() {
	common_usage
	cat <<EOF
### Flags ${PLATEFORM} plateform specific

  # Flags to configure nfs client provisionner
--nfs-server-adress                            # The NFS server address, default: ${NFS_SERVER_ADDRESS}
--nfs-server-mount                             # The NFS server mount path, default: ${NFS_SERVER_PATH}
--nfs-storage-class                            # The storage class name to use, default: ${NFS_STORAGE_CLASS}

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
--private-domain=<value>                       # Override the domain name, default: ${PRIVATE_DOMAIN_NAME}

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
				--arg PRIVATE_NET_INF "${PRIVATE_NET_INF}"
				--arg NODE_IP "${PUBLIC_IP}/${PUBLIC_MASK_CIDR}" \
				'.|.network.ethernets += { $PRIVATE_NET_INF: { "dhcp4": true, "addresses": [{ ($NODE_IP): { "label": "eth0:1" } }]}}')

			if [ ${#NETWORK_PUBLIC_ROUTES[@]} -gt 0 ]; then
#				NETWORK_DEFS=$(echo ${NETWORK_DEFS} | jq --arg PRIVATE_NET_INF ${PRIVATE_NET_INF} --argjson ROUTES "${PUBLIC_ROUTES_DEFS}" '.network.ethernets.[$PRIVATE_NET_INF].routes = $ROUTES')
				NETWORK_DEFS=$(jq --argjson JSONPATH "[\"network\", \"ethernets\", \"$PRIVATE_NET_INF\", \"routes\"]" --argjson ROUTES "${PUBLIC_ROUTES_DEFS}" 'setpath($JSONPATH; $ROUTES)' <<< "${NETWORK_DEFS}")
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
function multipass_infos() {
	local INFOS=$(multipass info "$1" --format json 2>/dev/null)

	while [ -z "${INFOS}" ]
	do
		sleep 1
		INFOS=$(multipass info "$1" --format json 2>/dev/null)
	done

	echo ${INFOS}
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
	local IPV4=$(multipass_infos ${MASTERKUBE_NODE} | jq -r --arg NAME ${MASTERKUBE_NODE} '.info|.[$NAME].ipv4')
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