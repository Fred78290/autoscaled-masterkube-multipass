export VMREST_URL=http://localhost:8697
export VMREST_USERNAME=
export VMREST_PASSWORD=
export VMREST_INSECURE=true

if [ "$(uname -s)" == "Darwin" ]; then
	VMREST_FOLDER="${HOME}/Virtual Machines.localized"
else
	VMREST_FOLDER="${HOME}/vmware"
fi

export AUTOSCALER_DESKTOP_UTILITY_TLS=$(kubernetes-desktop-autoscaler-utility certificate generate)

export LOCAL_AUTOSCALER_DESKTOP_UTILITY_KEY="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientKey)"
export LOCAL_AUTOSCALER_DESKTOP_UTILITY_CERT="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientCertificate)"
export LOCAL_AUTOSCALER_DESKTOP_UTILITY_CACERT="$(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .Certificate)"
export LOCAL_AUTOSCALER_DESKTOP_UTILITY_REST_URL="https://localhost:5700"

rm -f *.log

function url_encode() {
    echo -n "$@" \
    | sed \
        -e 's/%/%25/g' \
        -e 's/ /%20/g' \
        -e 's/!/%21/g' \
        -e 's/"/%22/g' \
        -e "s/'/%27/g" \
        -e 's/#/%23/g' \
        -e 's/(/%28/g' \
        -e 's/)/%29/g' \
        -e 's/+/%2b/g' \
        -e 's/,/%2c/g' \
        -e 's/-/%2d/g' \
        -e 's/:/%3a/g' \
        -e 's/;/%3b/g' \
        -e 's/?/%3f/g' \
        -e 's/@/%40/g' \
        -e 's/\$/%24/g' \
        -e 's/\&/%26/g' \
        -e 's/\*/%2a/g' \
        -e 's/\./%2e/g' \
        -e 's/\//%2f/g' \
        -e 's/\[/%5b/g' \
        -e 's/\\/%5c/g' \
        -e 's/\]/%5d/g' \
        -e 's/\^/%5e/g' \
        -e 's/_/%5f/g' \
        -e 's/`/%60/g' \
        -e 's/{/%7b/g' \
        -e 's/|/%7c/g' \
        -e 's/}/%7d/g' \
        -e 's/~/%7e/g'
}

function do_curl() {
	local METHOD=$1
	local URL=$2

	if [ "${TRACE_CURL}" == "YES" ]; then
		echo "--------------------------------------------------------------------" >> ${TRACE_FILE_CURL}
		echo "# - $(date '+%Y-%m-%d %T') - ${METHOD} ${URL}" >> ${TRACE_FILE_CURL}
		echo "--------------------------------------------------------------------" >> ${TRACE_FILE_CURL}
	fi

	if [ ${METHOD} == "POST" ] || [ ${METHOD} == "PUT" ]; then
		local BODY=

		if [ $# -eq 3 ]; then
			BODY=$3

			if [ "${TRACE_CURL}" == "YES" ]; then
				echo "${BODY}" | jq . >> ${TRACE_FILE_CURL}
				echo "--------------------------------------------------------------------" >> ${TRACE_FILE_CURL}
			fi
		fi

		curl -X${METHOD} -sk -H "Accept: application/vnd.vmware.vmw.rest-v1+json" \
			-H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
			--key "${LOCAL_AUTOSCALER_DESKTOP_UTILITY_KEY}" \
			--cert "${LOCAL_AUTOSCALER_DESKTOP_UTILITY_CERT}" \
			"${LOCAL_AUTOSCALER_DESKTOP_UTILITY_REST_URL}${URL}" -d "${BODY}" || echo "{}"
	else
		curl -X${METHOD} -sk -H "Accept: application/vnd.vmware.vmw.rest-v1+json" \
			-H "Content-Type: application/vnd.vmware.vmw.rest-v1+json" \
			--key "${LOCAL_AUTOSCALER_DESKTOP_UTILITY_KEY}" \
			--cert "${LOCAL_AUTOSCALER_DESKTOP_UTILITY_CERT}" \
			"${LOCAL_AUTOSCALER_DESKTOP_UTILITY_REST_URL}${URL}" || echo "{}"
	fi
}

function do_post() {
	if [ "${TRACE_CURL}" == "YES" ]; then
		if [ $# -eq 2 ]; then
			do_curl POST "${1}" "${2}" | jq . | tee -a ${TRACE_FILE_CURL}
		else
			do_curl POST "${1}" | jq . | tee -a ${TRACE_FILE_CURL}
		fi
	elif [ $# -eq 2 ]; then
		do_curl POST "${1}" "${2}"
	else
		do_curl POST "${1}"
	fi
}

function do_put() {
	if [ "${TRACE_CURL}" == "YES" ]; then
		if [ $# -eq 2 ]; then
			do_curl PUT "${1}" "${2}" | jq . | tee -a ${TRACE_FILE_CURL}
		else
			do_curl PUT "${1}" | jq . | tee -a ${TRACE_FILE_CURL}
		fi
	elif [ $# -eq 2 ]; then
		do_curl PUT "${1}" "${2}"
	else
		do_curl PUT "${1}"
	fi
}

function do_delete() {
	if [ "${TRACE_CURL}" == "YES" ]; then
		do_curl DELETE "${1}" | jq . | tee -a ${TRACE_FILE_CURL}
	else
		do_curl DELETE "${1}"
	fi
}

function do_get() {
	if [ "${TRACE_CURL}" == "YES" ]; then
		do_curl GET "${1}" | jq . | tee -a ${TRACE_FILE_CURL}
	else
		do_curl GET "${1}"
	fi
}

function vmrest_utility_running() {
	do_get "/version" | jq -r '.result.version // "ERROR"'
}

function vmrest_get_net_type() {
	local VNET=$1

	TYPE=$(do_get "/api/vmnet" | jq --arg VNET ${VNET} -r '.vmnets[]|select(.name == $VNET)|.type // ""')

	if [ "${TYPE}" = "bridged" ] && [ "${VNET}" != "vmnet0" ]; then
		TYPE="custom"
	fi

	echo -n "${TYPE}"
}

function vmrest_get_vmnic() {
	local VMUUID=$1

	do_get "/api/vms/${VMUUID}/nic"
}

function vmrest_get_vmnicips() {
	local VMUUID=$1

	do_get "/api/vms/${VMUUID}/nicips"
}

function vmrest_get_vmname() {
	local VMUUID=$1

	VMNAME=$(do_get "/vm/byuuid/${VMUUID}" | jq -r '.result.name // ""')

	echo -n ${VMNAME}
}

# Return vmuuid for a name
function vmrest_get_vmuuid() {
	local VMNAME=$(url_encode $1)

	VMUUID=$(do_get "/vm/byname/${VMNAME}" | jq -r '.result.uuid // ""')

	echo -n ${VMUUID}
}

# Register a VM and return vmuuid
function vmrest_vm_register() {
	local VMNAME=$1
	local VMPATH=$2
	local BODY=$(echo '{}' | jq --arg VMNAME "${VMNAME}" --arg VMPATH "${VMPATH}" '.name = $VMNAME|.path = $VMPATH')

	do_post "/vm/registration" "${BODY}" | jq -r '.result.uuid // "ERROR"'
}

# Add a network adapter
function vmrest_network_add() {
	local VMUUID=$1
	local VNET=$2
	local BODY=$(echo '{}' | jq --arg VNET "${VNET}" '.vnet = $VNET')

	do_post "/vm/nic/${VMUUID}" "${BODY}" | jq -r '.result.done // "ERROR"'
}

# Change network adapter
function vmrest_network_change() {
	local VMUUID=$1
	local VNET=$2
	local NIC=$3
	local BODY=$(echo '{}' | jq --arg VNET "${VNET}" --argjson NIC "${NIC}" '.vnet = $VNET|.nic = $NIC')

	do_put "/vm/nic/${VMUUID}" "${BODY}" | jq -r '.result.done // "ERROR"'
}

# Power on a VM
function vmrest_poweron() {
	local VMUUID=$1

	do_put "/vm/poweron/${VMUUID}" | jq -r '.result.done // "ERROR"'
}

# Shutdown a VM
function vmrest_poweroff() {
	local VMUUID=$1
	local MODE=$2
	local BODY=$(echo '{}' | jq --arg MODE ${MODE} '.mode = $MODE')

	do_put "/vm/poweroff/${VMUUID}" "${BODY}" | jq -r '.result.done // "ERROR"'
}

# Return power state of a VM
function vmrest_power_state() {
	local VMUUID=$1
	local STATE=$(do_get "/vm/powerstate/${VMUUID}" | jq -r '.result.powered')

	if [ ${STATE} == "true" ]; then
		echo -n "poweredOn"
	elif [ ${STATE} == "false" ]; then
		echo -n "poweredOff"
	else
		echo -n "ERROR"
	fi
}

# Wait for a reached power state
function vmrest_wait_for_powerstate() {
	local VMUUID=$1
	local STATE=$2
	local POWER_STATE=$(vmrest_power_state ${VMUUID})

	while [ "${POWER_STATE}" != "${STATE}" ] && [ -n "${POWER_STATE}" ] && [ "${POWER_STATE}" != "ERROR" ];
	do
		sleep 1
		POWER_STATE=$(vmrest_power_state ${VMUUID})
	done

	echo -n ${POWER_STATE}
}

# Wait for vm powered on
function vmrest_wait_for_poweron() {
	local VMUUID=$1

	vmrest_poweron ${VMUUID} &> /dev/null
	vmrest_wait_for_powerstate ${VMUUID} poweredOn
}

# Wait for vm off
function vmrest_wait_for_poweroff() {
	local VMUUID=$1

	vmrest_poweroff ${VMUUID} "soft" &> /dev/null
	vmrest_wait_for_powerstate ${VMUUID} poweredOff
}

# Wait for IP
function vmrest_waitip() {
	local VMUUID=$1
	
	do_get "/vm/waitforip/${VMUUID}?timeout=600" | jq -r '.result.address // "ERROR"'
}

function vmrest_destroy() {
	local VMUUID=$1

	do_delete "/vm/delete/${VMUUID}" | jq -r '.result.done // "ERROR"'
}

function vmrest_create() {
	local TARGET_IMAGE_UUID=$1
	local NUM_VCPUS=$2
	local MEMSIZE=$3
	local VMNAME=$4
	local DISK_SIZE_MB=$5
	local GUESTINFO_METADATA=$6
	local GUESTINFO_USERDATA=$7
	local GUESTINFO_VENDORDATA=$8
	local REGISTER_VM=$9

	shift

	local AUTOSTART=$9

	local BODY=$(cat << EOF
{
	"template": "${TARGET_IMAGE_UUID}",
	"name": "${VMNAME}",
	"vcpus": ${NUM_VCPUS},
	"memory": ${MEMSIZE},
	"diskSizeInMB": ${DISK_SIZE_MB},
	"linked": false,
	"register": ${REGISTER_VM},
	"autostart": ${AUTOSTART},
	"guestInfos": {
		"metadata":            "$(cat ${GUESTINFO_METADATA})",
		"metadata.encoding":   "gzip+base64",
		"userdata":            "$(cat ${GUESTINFO_USERDATA})",
		"userdata.encoding":   "gzip+base64",
		"vendordata":          "$(cat ${GUESTINFO_VENDORDATA})",
		"vendordata.encoding": "gzip+base64"
	}
}
EOF
)

	do_post "/vm/create" "${BODY}" | jq -r '.result.uuid // "ERROR"'
}

if [ "$(vmrest_utility_running)" == "ERROR" ]; then
	echo_red_bold "kubernetes-desktop-autoscaler-utility not running"
	exit 1
fi
