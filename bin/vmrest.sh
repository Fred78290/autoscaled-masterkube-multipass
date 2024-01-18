VMPATH_BY_UUID=()

if [ -z "$(do_get ${VMREST_URL})" ]; then
    ${CURDIR}/install-vmrest.sh
fi

function vnet_to_inet() {
	local VNET=$1

	if [ "${OSDISTRO}" = "Darwin" ]; then
		sudo /Applications/VMware\ Fusion.app/Contents/Library/vmnet-cfgcli gethostadapterlist \
			| sed -E 's/vmnet\ -\ ([0-9])/vmnet\1/g' \
			| sed -e '1,2d' -e 's/[,:-]//g' -e 's/Host Adapter: name //g' -e 's/Host Adapter name  //g' -e 's/printName//g' -e 's/drivername//g' -e 's/ \+/ /g' \
			| grep "$VNET" \
			| cut -d ' ' -f 1
	else
		case $VNET in
			vmnet0|vmnet1|vmnet8)
				VNET=
				;;
			*)
				VNET=$(cat /etc/vmware/networking| sed -e /-1/d | sed -E 's/([0-9]+)$/vmnet\1/g' | grep $VNET | cut -d ' ' -f 2)
				;;
		esac

		echo -n $VNET
	fi
}

function inet_to_name() {
	local INET=$1

	if [ "${OSDISTRO}" = "Darwin" ]; then
		networksetup -listallhardwareports | gsed -e '/Parent Device:/d' -e 's/ ("Hardware" Port)//g' | gsed -n "/^Device: ${INET}/{x;p;d;}; x" | awk 'NF>1{print $NF}'
	else
		nmcli c show | grep "$INET" | cut -d ' ' -f 1
	fi
}

function vmrest_listHostNetworks() {
	do_get "${VMREST_URL}/api/vmnet"
}

function do_curl() {
	local METHOD=$1
	local URL=$2
	local BODY=$3
	local AUTHENT=

	if [ -n "${VMREST_USERNAME}" ] && [ -n "${VMREST_PASSWORD}" ]; then
		AUTHENT="-u ${VMREST_USERNAME}:${VMREST_PASSWORD}"
	fi

	if [ ${METHOD} == "POST" ] || [ ${METHOD} == "PUT" ]; then
		curl -X${METHOD} -sk -H 'Accept: application/vnd.vmware.vmw.rest-v1+json' -H 'Content-Type: application/vnd.vmware.vmw.rest-v1+json' ${AUTHENT} ${URL} -d "${BODY}" || echo "{}"
	else
		curl -X${METHOD} -sk -H 'Accept: application/vnd.vmware.vmw.rest-v1+json' -H 'Content-Type: application/vnd.vmware.vmw.rest-v1+json' ${AUTHENT} ${URL} || echo "{}"
	fi
}

function do_post() {
	do_curl POST "${1}" "${2}"
}

function do_put() {
	do_curl PUT "${1}" "${2}"
}

function do_delete() {
	do_curl DELETE "${1}" "${2}"
}

function do_get() {
	do_curl GET "${1}" "${2}"
}

function vmrest_get_vmpath() {
	local VMUUID=$1
	local STRUUID="A${VMUUID}"
	local VMPATH="${VMPATH_BY_UUID[${STRUUID}]}"

	if [ -z "${VMPATH}" ]; then
		VMPATH=$(do_get "${VMREST_URL}/api/vms" | jq --arg VMID "${VMUUID}" -r '.[] | select(.id == $VMID)|.path // ""')

		if [ -n "${VMPATH}" ]; then
			VMPATH_BY_UUID[${STRUUID}]="${VMPATH}"
		fi
	fi

	echo -n "${VMPATH}"
}

# Return vmuuid for a name
function vmrest_get_vmuuid() {
	local VMNAME=$1
	local VMIDS=$(do_get "${VMREST_URL}/api/vms" | jq -r '.[]|.id // ""')
	local VMID=

	for VMID in $VMIDS
	do
		NAME=$(do_get "${VMREST_URL}/api/vms/${VMID}/params/vmname" | jq -r '.value // ""')

		if [ "${NAME}" = "${VMNAME}" ]; then
			echo -n $VMID
			break
		fi
	done
}

# Return vmname for a vmuuid
function vmrest_get_vmname() {
	local VMUUID=$1
	
	do_get "${VMREST_URL}/api/vms/${VMUUID}/params/vmname" | jq -r '.value // ""'
}

# Register a VM and return vmuuid
function vmrest_vm_register() {
	local VMNAME=$1
	local VMPATH=$2
	local BODY=$(echo '{}' | jq --arg VMNAME "${VMNAME}" --arg VMPATH "${VMPATH}" '.name = $VMNAME|.path = $VMPATH')

	do_post "${VMREST_URL}/api/vms/registration" "${BODY}" | jq -r '.id // ""'
}

function vmrest_vm_create() {
	local TEMPLATEUUID=$1
	local VMNAME=$2
	local BODY=$(echo '{}' | jq --arg TEMPLATEUUID "${TEMPLATEUUID}" --arg VMNAME "${VMNAME}" '.name = $VMNAME|.parentId = $TEMPLATEUUID')

	do_post "${VMREST_URL}/api/vms" "${BODY}" | jq -r '.id // ""'
}

function vmrest_get_net_type() {
	local VNET=$1

	TYPE=$(do_get "${VMREST_URL}/api/vmnet" | jq --arg VNET ${VNET} -r '.vmnets[]|select(.name == $VNET)|.type // ""')

	if [ "${TYPE}" = "bridged" ] && [ "${VNET}" != "vmnet0" ]; then
		TYPE="custom"
	fi

	echo -n "${TYPE}"
}

function set_vmx_custom_network_vmx() {
	local VMUUID=$1
	local VNET=$2
	local NIC=$3
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"
	local INET_INDEX=$((NIC - 1))
	local ADDRESSTYPE=$(grep "\bethernet${INET_INDEX}.addressType\b" "${VMPATH}" | cut -d '"' -f 2)
	local MACADDRESS=$(grep "\bethernet${INET_INDEX}.generatedAddress\b" "${VMPATH}" | cut -d '"' -f 2)
	local OFFSET=$(grep "\bethernet${INET_INDEX}.generatedAddressOffset\b" "${VMPATH}" | cut -d '"' -f 2)
	local SLOTNUMBER=$(grep "\bethernet${INET_INDEX}.pciSlotNumber\b" "${VMPATH}" | cut -d '"' -f 2)

	sed -i "/ethernet${INET_INDEX}/d" "${VMPATH}"

	if [ "${OSDISTRO}" = "Darwin" ]; then
		local INET=$(vnet_to_inet ${VNET})

		cat > "${VMPATH}" <<-EOF
			ethernet${INET_INDEX}.bsdName = "${INET}"
			ethernet${INET_INDEX}.connectionType = "custom"
			ethernet${INET_INDEX}.displayName = "$(inet_to_name ${INET})"
			ethernet${INET_INDEX}.linkStatePropagation.enable = "TRUE"
			ethernet${INET_INDEX}.present = "TRUE"
			ethernet${INET_INDEX}.virtualDev = "vmxnet3"
			ethernet${INET_INDEX}.vnet = "${VNET}"
EOF
else
		cat > "${VMPATH}" <<-EOF
			ethernet${INET_INDEX}.connectionType = "custom"
			ethernet${INET_INDEX}.linkStatePropagation.enable = "TRUE"
			ethernet${INET_INDEX}.present = "TRUE"
			ethernet${INET_INDEX}.virtualDev = "vmxnet3"
			ethernet${INET_INDEX}.vnet = "/dev/${VNET}"
EOF
fi

	if [ -n "${ADDRESSTYPE}" ]; then
		echo "ethernet${INET_INDEX}.addressType = \"${ADDRESSTYPE}\"" >> "${VMPATH}"
	fi

	if [ -n "${MACADDRESS}" ]; then
		echo "ethernet${INET_INDEX}.generatedAddress = \"${MACADDRESS}\"" >> "${VMPATH}"
	fi

	if [ -n "${OFFSET}" ]; then
		echo "ethernet${INET_INDEX}.generatedAddressOffset = \"${OFFSET}\"" >> "${VMPATH}"
	fi

	if [ -n "${SLOTNUMBER}" ]; then
		echo "ethernet${INET_INDEX}.pciSlotNumber = \"${SLOTNUMBER}\"" >> "${VMPATH}"
	fi

	echo -n $NIC
}

function vmrest_vnet_custom() {
	local VMUUID=$1
	local VNET=$2
	local NIC=$3
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"
	local INET_INDEX=$((NIC - 1))
	local ADDRESSTYPE=$(vmrest_get_params $VMUUID "ethernet${INET_INDEX}.addressType")
	local MACADDRESS=$(vmrest_get_params $VMUUID "ethernet${INET_INDEX}.generatedAddress")
	local OFFSET=$(vmrest_get_params $VMUUID "ethernet${INET_INDEX}.generatedAddressOffset")
	local SLOTNUMBER=$(vmrest_get_params $VMUUID "ethernet${INET_INDEX}.pciSlotNumber")
	local PARAMS=

	sed -i "/ethernet${INET_INDEX}/d" "${VMPATH}"

	if [ "${OSDISTRO}" = "Darwin" ]; then
		local INET=$(vnet_to_inet ${VNET})

		PARAMS=(
			"ethernet${INET_INDEX}.addressType=${ADDRESSTYPE}"
			"ethernet${INET_INDEX}.bsdName=${INET}"
			"ethernet${INET_INDEX}.connectionType=custom"
			"ethernet${INET_INDEX}.displayName=$(inet_to_name ${INET})"
			"ethernet${INET_INDEX}.generatedAddress=${MACADDRESS}"
			"ethernet${INET_INDEX}.generatedAddressOffset=${OFFSET}"
			"ethernet${INET_INDEX}.linkStatePropagation.enable=TRUE"
			"ethernet${INET_INDEX}.pciSlotNumber=${SLOTNUMBER}"
			"ethernet${INET_INDEX}.present=TRUE"
			"ethernet${INET_INDEX}.virtualDev=vmxnet3"
			"ethernet${INET_INDEX}.vnet=${VNET}"
		)
	else
		PARAMS=(
			"ethernet${INET_INDEX}.addressType=${ADDRESSTYPE}"
			"ethernet${INET_INDEX}.connectionType=custom"
			"ethernet${INET_INDEX}.generatedAddress=${MACADDRESS}"
			"ethernet${INET_INDEX}.generatedAddressOffset=${OFFSET}"
			"ethernet${INET_INDEX}.linkStatePropagation.enable=TRUE"
			"ethernet${INET_INDEX}.pciSlotNumber=${SLOTNUMBER}"
			"ethernet${INET_INDEX}.present=TRUE"
			"ethernet${INET_INDEX}.virtualDev=vmxnet3"
			"ethernet${INET_INDEX}.vnet=/dev/${VNET}"
		)
	fi

	for PARAM in ${PARAMS[@]}
	do
		IFS== read KEY VALUE <<< "$PARAM"
		if [ -n "${VALUE}" ]; then
			vmrest_set_params ${VMUUID} "${KEY}" "${VALUE}"
		fi
	done

	echo -n $NIC
}

# Change network adapter
function vmrest_network_change() {
	local VMUUID=$1
	local VNET=$2
	local NIC=$3
	local VNET_TYPE=$(vmrest_get_net_type ${VNET})

	if [ "${VNET_TYPE}" == "custom" ]; then
		vmrest_vnet_custom $VMUUID $VNET $NIC
	elif [ -n "${VNET_TYPE}" ]; then
		local BODY=$(echo '{}' | jq --arg VNET_TYPE "${VNET_TYPE}" '.type = $VNET_TYPE')
		local INET_INDEX=$((NIC - 1))

		do_put "${VMREST_URL}/api/vms/${VMUUID}/nic/${NIC}" "${BODY}" | jq -r '.index // ""'

		vmrest_set_params ${VMUUID} "ethernet${INET_INDEX}.virtualDev" "vmxnet3"
	fi
}

# Add a network adapter
function vmrest_network_add() {
	local VMUUID=$1
	local VNET=$2

	local VNET_TYPE=$(vmrest_get_net_type ${VNET})

	if [ "${VNET_TYPE}" == "custom" ]; then
		local NIC=$(do_get "${VMREST_URL}/api/vms/${VMUUID}/nic" | jq -r '.num // "0"')
		vmrest_vnet_custom $VMUUID $VNET $((NIC + 1))
	elif [ -n "${VNET_TYPE}" ]; then
		local BODY=$(echo '{}' | jq --arg VNET_TYPE ${VNET_TYPE} '.type = $VNET_TYPE')
		local NIC=$(do_post "${VMREST_URL}/api/vms/${VMUUID}/nic" "${BODY}" | jq -r '.index // ""')
		local INET_INDEX=$((NIC - 1))

		vmrest_set_params ${VMUUID} "ethernet${INET_INDEX}.virtualDev" "vmxnet3"
	fi
}

# Power on a VM
function vmrest_poweron() {
	local VMUUID=$1
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"

	if [ -n "${VMPATH}" ]; then
		vmrun start "${VMPATH}" nogui &> /dev/null
	fi
}

# Shutdown a VM
function vmrest_poweroff() {
	local VMUUID=$1
	local MODE=$2
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"

	if [ -n "${VMPATH}" ]; then
		vmrun stop "${VMPATH}" ${MODE} &> /dev/null
	fi
}

# Return IP of a VM
function vmrest_getip() {
	local VMUUID=$1

	do_get "${VMREST_URL}/api/vms/${VMUUID}/ip" | jq -r '.ip // ""'
}

# Wait for IP
function vmrest_waitip() {
	local VMUUID=$1
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"
	local IPADDR=

	if [ -n "${VMPATH}" ]; then
		IPADDR=$(vmrun getGuestIPAddress "${VMPATH}" -wait)
		if [[ "${IPADDR}" =~ Error ]]; then
			IPADDR=""
		fi
	fi

	echo -n ${IPADDR}
}

# Return power state of a VM
function vmrest_power_state() {
	local VMUUID=$1
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"
	local STATE="poweredOff"

	while read -r VMX
	do
		if [ "${VMX}" = "${VMPATH}" ]; then
			STATE=poweredOn
			break
		fi
	done <<< "$(vmrun list | grep -v Total)"

	echo -n ${STATE}
}

# Wait for a reached power state
function vmrest_wait_for_powerstate() {
	local VMUUID=$1
	local STATE=$2
	local POWER_STATE=$(vmrest_power_state $VMUUID)

	while [ "${POWER_STATE}" != "${STATE}" ] && [ -n "${POWER_STATE}" ] && [ "${POWER_STATE}" != "ERROR" ];
	do
		sleep 1
		POWER_STATE=$(vmrest_power_state $VMUUID)
	done

	echo -n ${POWER_STATE}
}

# Wait for vm powered on
function vmrest_wait_for_poweron() {
	local VMUUID=$1

	vmrest_poweron $VMUUID &> /dev/null
	vmrest_wait_for_powerstate $VMUUID poweredOn
}

# Wait for vm off
function vmrest_wait_for_poweroff() {
	local VMUUID=$1

	vmrest_poweroff $VMUUID &> /dev/null
	vmrest_wait_for_powerstate $VMUUID poweredOff
}

# Clone VM
function vmrest_clone() {
	local VMUUID=$1
	local VMCPUS=$2
	local VMMEM=$3
	local NEWVM_NAME=$4
	local REGISTER_VM=$5
	local AUTOSTART=$6

	if [ "${REGISTER_VM}" == "true" ]; then
		local VMPATH="$(vmrest_get_vmpath $VMUUID)"

		vmrun clone "${VMPATH}" "${NEWVM_PATH}" full -cloneName=${NEWVM_NAME}

		vmrest_vm_register ${NEWVM_NAME} "${NEWVM_PATH}"
	else
		vmrest_vm_create ${VMUUID} ${NEWVM_NAME}
	fi

	local NEWVM_PATH="${VMREST_FOLDER}/${NEWVM_NAME}${VMWAREWM}/${NEWVM_NAME}.vmx"

	sed -i -e '/displayname/Id' \
		-e '/autostart/Id' \
		-e '/memsize/Id' \
		-e '/numvcpus/Id' \
		-e '/guestinfo/Id' \
		-e '/instance-id/Id' \
		-e '/hostname/Id' \
		-e '/seedfrom/Id' \
		-e '/public-keys/Id' \
		-e '/user-data/Id' \
		-e '/password/Id' "${NEWVM_PATH}"

	cat >> "${NEWVM_PATH}" <<EOF
autostart = "${AUTOSTART}"
displayname = "${NEWVM_NAME}"
memsize = "${VMMEM}"
numvcpus = "${VMCPUS}"
EOF

}

function vmrest_set_settings() {
	local VMUUID=$1
	local CPUS=$2
	local MEM=$3
	local BODY=$(echo '{}' | jq --argjson CPUS ${CPUS} --argjson MEM ${MEM} '.processors = $CPUS|.memory = $MEM')

	do_put "${VMREST_URL}/api/vms/${VMUUID}" "${BODY}" | jq -r '.id // "ERROR"'
}

function vmrest_set_params() {
	local VMUUID=$1
	local KEY=$2
	local VALUE=$3
	local BODY=$(echo '{}' | jq --arg KEY "${KEY}" --arg VALUE "${VALUE}" '.name = $KEY|.value = $VALUE')

	do_put ${VMREST_URL}/api/vms/${VMUUID}/params "${BODY}" | jq -r '.id // "ERROR"'
}

function vmrest_get_params() {
	local VMUUID=$1
	local KEY=$2

	do_get "${VMREST_URL}/api/vms/${VMUUID}/params/${KEY}" | jq -r '.value // "ERROR"'
}

# Set guestinfo for a VM
function vmrest_set_guestinfos() {
	local VMUUID=$1
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"

	shift

	while [ $# -gt 0 ];
	do
		KEY=$1
		VALUE=$2
		shift 2
		echo "${KEY} = \"${VALUE}\"" >> "${VMPATH}"
	done
}

# Destroy a VM
function vmrest_destroy() {
	local VMUUID=$1
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"

	if [ $(vmrest_power_state $VMUUID) == "poweredOff" ]; then
		vmrun deleteVM "${VMPATH}"
	else
		echo_red "Unable to delete running VM: ${VMPATH}"
	fi
}

function vmrest_resize_disk() {
	local VMUUID=$1
	local DISK_SIZE=$2
	local VMPATH="$(vmrest_get_vmpath $VMUUID)"
	local VMDK=

	if [ -n "${VMPATH}" ]; then
		for DISK in "nvme0:0" "scsi0:0" "sata0:0"
		do
			if [ "$(vmrest_get_params ${VMUUID} ${DISK}.present | tr '[:upper:]' '[:lower:]')" = "true" ]; then
				VMDK=$(vmrest_get_params ${VMUUID} "${DISK}.fileName")
				if [ -n "${VMDK}" ]; then
					echo_blue_bold "Resize VMD: ${VMPATH} to ${DISK_SIZE}"
					pushd $(dirname ${VMPATH}) > /dev/null
					vmware-vdiskmanager -x ${DISK_SIZE} ${VMDK}
					popd > /dev/null
					return
				fi
			fi
		done
	fi
}

function vmrest_create() {
	local TARGET_IMAGE_UUID=$1
	local NUM_VCPUS=$2
	local MEMSIZE=$3
	local VMNAME=$4
	local DISK_SIZE_GB=$5
	local GUESTINFO_METADATA=$6
	local GUESTINFO_USERDATA=$7
	local GUESTINFO_VENDORDATA=$8
	local REGISTER_VM=$9
shift
	local AUTOSTART=$9

    local VM_UUID=$(vmrest_clone ${TARGET_IMAGE_UUID} ${NUM_VCPUS} ${MEMSIZE} ${VMNAME} ${REGISTER_VM} ${AUTOSTART})

	if [ -n "${VM_UUID}" ]; then
		if [ ${DISK_SIZE} -gt 0 ]; then
			vmrest_resize_disk ${VM_UUID} "${DISK_SIZE}G" > /dev/null
		fi

		vmrest_set_guestinfos "${VM_UUID}" \
			"guestinfo.metadata" "$(cat ${GUESTINFO_METADATA})" \
			"guestinfo.metadata.encoding" "gzip+base64" \
			"guestinfo.userdata" "$(cat ${GUESTINFO_USERDATA})" \
			"guestinfo.userdata.encoding" "gzip+base64" \
			"guestinfo.vendordata" "$(cat ${GUESTINFO_VENDORDATA})" \
			"guestinfo.vendordata.encoding" "gzip+base64" > /dev/null
	else
		echo -n "ERROR"
	fi

	echo -n ${VM_UUID}
}