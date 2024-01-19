if [ -z "${PLATEFORM}" ]; then
    echo "env PLATEFORM= [ aws | vsphere | multipass | desktop ] not defined!"
    exit 1
fi

export SSH_OPTIONS="-o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
export SCP_OPTIONS="${SSH_OPTIONS} -p -r"
export OSDISTRO=$(uname -s)
export CONTROLNODES=3
export WORKERNODES=3
export NODEGROUP_NAME="${PLATEFORM}-ca-k8s"
export MASTERKUBE=${NODEGROUP_NAME}-masterkube
export DASHBOARD_HOSTNAME=masterkube-${PLATEFORM}-dashboard
export PLATEFORMDEFS=${CURDIR}/plateform/${PLATEFORM}/vars.defs
export VERBOSE=NO

#===========================================================================================================================================
#
#===========================================================================================================================================
function add_host() {
	local LINE=

	for ARG in $@
	do
		if [ -n "${LINE}" ]; then
			LINE="${LINE} ${ARG}"
		else
			LINE="${ARG}     "
		fi
	done

	sudo bash -c "echo '${LINE}' >> /etc/hosts"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function verbose() {
	if [ ${VERBOSE} = "YES" ]; then
		eval "$1"
	else
		eval "$1 &> /dev/null"
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_jobs_finish() {
	wait $(jobs -p)
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_dot() {
	>&2 echo -n -e "\x1B[90m\x1B[39m\x1B[1m\x1B[34m.\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_dot_title() {
	# echo message in blue and bold
	>&2 echo -n -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[39m\x1B[1m\x1B[34m$1\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_bold() {
	# echo message in blue and bold
	>&2 echo -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[39m\x1B[1m\x1B[34m$1\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_title() {
	# echo message in blue and bold
	echo
	echo_line
	echo_blue_bold "$1"
	echo_line
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_grey() {
	# echo message in light grey
	>&2 echo -e "\x1B[90m$1\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_red() {
	# echo message in red
	>&2 echo -e "\x1B[31m$1\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_red_bold() {
	# echo message in blue and bold
	>&2 echo -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[31m\x1B[1m\x1B[31m$1\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_separator() {
	echo_line
	>&2 echo
	>&2 echo
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_line() {
	echo_grey "============================================================================================================================="
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_ssh_ready() {
	while :
	do
		ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=1 $1 'exit 0' && break
 
		sleep 5
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function nextip()
{
	IP=$1
	IP_HEX=$(printf '%.2X%.2X%.2X%.2X\n' `echo ${IP} | tr '.' ' '`)
	NEXT_IP_HEX=$(printf %.8X `echo $(( 0x${IP_HEX} + 1 ))`)
	NEXT_IP=$(printf '%d.%d.%d.%d\n' `echo ${NEXT_IP_HEX} | sed -r 's/(..)/0x\1\ /g'`)
	echo "${NEXT_IP}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function build_routes() {
	local ROUTES="[]"
	local ROUTE=

	for ROUTE in $@
	do
		local TO=
		local VIA=
		local METRIC=500

		IFS=, read -a DEFS <<< "${ROUTE}"

		for DEF in ${DEFS[@]}
		do
			IFS== read KEY VALUE <<< "${DEF}"
			case ${KEY} in
				to)
					TO=${VALUE}
					;;
				via)
					VIA=${VALUE}
					;;
				metric)
					METRIC=${VALUE}
					;;
			esac
		done

		if [ -n "${TO}" ] && [ -n "${VIA}" ]; then
			ROUTES=$(echo ${ROUTES} | jq --arg TO ${TO} --arg VIA ${VIA} --argjson METRIC ${METRIC} '. += [{ "to": $TO, "via": $VIA, "metric": $METRIC }]')
		fi
	done

	echo -n ${ROUTES}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function collect_cert_sans() {
	local LOAD_BALANCER_IP=$1
	local CLUSTER_NODES=$2
	local CERT_EXTRA_SANS=$3

	local LB_IP=
	local CERT_EXTRA=
	local CLUSTER_NODE=
	local CLUSTER_IP=
	local CLUSTER_HOST=
	local TLS_SNA=(
		"${LOAD_BALANCER_IP}"
	)

	for CERT_EXTRA in $(echo ${CERT_EXTRA_SANS} | tr ',' ' ')
	do
		if [[ ! ${TLS_SNA[*]} =~ "${CERT_EXTRA}" ]]; then
			TLS_SNA+=("${CERT_EXTRA}")
		fi
	done

	for CLUSTER_NODE in $(echo ${CLUSTER_NODES} | tr ',' ' ')
	do
		IFS=: read CLUSTER_HOST CLUSTER_IP <<< "$CLUSTER_NODE"

		if [ -n ${CLUSTER_IP} ] && [[ ! ${TLS_SNA[*]} =~ "${CLUSTER_IP}" ]]; then
			TLS_SNA+=("${CLUSTER_IP}")
		fi

		if [ -n "${CLUSTER_HOST}" ]; then
			if [[ ! ${TLS_SNA[*]} =~ "${CLUSTER_HOST}" ]]; then
				TLS_SNA+=("${CLUSTER_HOST}")
				TLS_SNA+=("${CLUSTER_HOST%%.*}")
			fi
		fi
	done

	echo -n "${TLS_SNA[*]}" | tr ' ' ','
}

#===========================================================================================================================================
#
#===========================================================================================================================================
if [ "${OSDISTRO}" == "Darwin" ]; then
	if [ -z "$(command -v cfssl)" ]; then
		echo_red_bold "You must install gnu cfssl with brew (brew install cfssl)"
		exit 1
	fi

	if [ -z "$(command -v gsed)" ]; then
		echo_red_bold "You must install gnu sed with brew (brew install gsed), this script is not compatible with the native macos sed"
		exit 1
	fi

	if [ -z "$(command -v gbase64)" ]; then
		echo_red_bold "You must install gnu base64 with brew (brew install coreutils), this script is not compatible with the native macos base64"
		exit 1
	fi

	if [ ! -e /usr/local/opt/gnu-getopt/bin/getopt ] && [ ! -e /opt/homebrew/opt/gnu-getopt/bin/getopt ]; then
		echo_red_bold "You must install gnu gnu-getopt with brew (brew install coreutils), this script is not compatible with the native macos base64"
		exit 1
	fi

	if [ -z "$(command -v jq)" ]; then
		echo_red_bold "You must install gnu jq with brew (brew install jq)"
		exit 1
	fi

	shopt -s expand_aliases

	alias base64=gbase64
	alias sed=gsed

	if [ -e /usr/local/opt/gnu-getopt/bin/getopt ]; then
		alias getopt=/usr/local/opt/gnu-getopt/bin/getopt
	else
		alias getopt=/opt/homebrew/opt/gnu-getopt/bin/getopt
	fi

	function delete_host() {
		sudo gsed -i "/$1/d" /etc/hosts
	}

	TZ=$(sudo systemsetup -gettimezone | awk -F: '{print $2}' | tr -d ' ')
	TRANSPORT_IF=$(route get 1 | grep -m 1 interface | awk '{print $2}')
	LOCAL_IPADDR=$(ifconfig ${TRANSPORT_IF} | grep -m 1 "inet\s" | sed -n 1p | awk '{print $2}')
else
	TZ=$(cat /etc/timezone)
	TRANSPORT_IF=$(ip route get 1 | awk '{print $5;exit}')
	LOCAL_IPADDR=$(ip addr show ${TRANSPORT_IF} | grep -m 1 "inet\s" | tr '/' ' ' | awk '{print $2}')

	function delete_host() {
		sudo sed -i "/$1/d" /etc/hosts
	}
fi

#===========================================================================================================================================
#
#===========================================================================================================================================

source ${CURDIR}/plateform/${PLATEFORM}/plateform.sh

source ${PLATEFORMDEFS}

#===========================================================================================================================================
#
#===========================================================================================================================================
for MANDATORY in ${CMD_MANDATORIES}
do
	if [ -z "$(command -v $MANDATORY)" ]; then
		echo_red "The command $MANDATORY is missing"
		exit 1
	fi
done

