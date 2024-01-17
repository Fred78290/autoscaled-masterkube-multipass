export SSH_OPTIONS="-o BatchMode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
export SCP_OPTIONS="${SSH_OPTIONS} -p -r"
export OSDISTRO=$(uname -s)
export SCHEME="multipass"
export NODEGROUP_NAME="${SCHEME}-ca-k8s"
export MASTERKUBE=${NODEGROUP_NAME}-masterkube
export DASHBOARD_HOSTNAME=masterkube-${SCHEME}-dashboard
export CONTROLNODES=3
export WORKERNODES=3
export SCHEMEDEFS=${CURDIR}/vars.defs

source ${SCHEMEDEFS}

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

function verbose() {
    if [ ${VERBOSE} = "YES" ]; then
        eval "$1"
    else
        eval "$1 &> /dev/null"
    fi
}

function wait_jobs_finish() {
    wait $(jobs -p)
}

function echo_blue_dot() {
    >&2 echo -n -e "\x1B[90m\x1B[39m\x1B[1m\x1B[34m.\x1B[0m\x1B[39m"
}

function echo_blue_dot_title() {
    # echo message in blue and bold
    >&2 echo -n -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[39m\x1B[1m\x1B[34m$1\x1B[0m\x1B[39m"
}

function echo_blue_bold() {
    # echo message in blue and bold
    >&2 echo -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[39m\x1B[1m\x1B[34m$1\x1B[0m\x1B[39m"
}

function echo_title() {
    # echo message in blue and bold
    echo
    echo_line
    echo_blue_bold "$1"
    echo_line
}

function echo_grey() {
    # echo message in light grey
    >&2 echo -e "\x1B[90m$1\x1B[39m"
}

function echo_red() {
    # echo message in red
    >&2 echo -e "\x1B[31m$1\x1B[39m"
}

function echo_red_bold() {
    # echo message in blue and bold
    >&2 echo -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[31m\x1B[1m\x1B[31m$1\x1B[0m\x1B[39m"
}

function echo_separator() {
    echo_line
    >&2 echo
    >&2 echo
}

function echo_line() {
    echo_grey "============================================================================================================================="
}

if [ "${OSDISTRO}" == "Darwin" ]; then
    VMWAREWM=".vmwarevm"

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
	PATH=${HOME}/Library/DesktopAutoscalerUtility:${PATH}
else
    TZ=$(cat /etc/timezone)
    VMWAREWM=""
	PATH=${HOME}/.local/vmware:${PATH}

    function delete_host() {
        sudo sed -i "/$1/d" /etc/hosts
    }
fi

function delete_vm_by_name() {
	local VMNAME=$1

    if [ "$(multipass info ${VMNAME} 2>/dev/null)" ]; then
        echo_blue_bold "Delete VM: $VMNAME"
        multipass delete $VMNAME -p
	fi

    delete_host "${VMNAME}"
}

function wait_ssh_ready() {
    while :
    do
        ssh -q -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=1 $1 'exit 0' && break
 
        sleep 5
    done
}

for MANDATORY in envsubst helm kubectl jq yq cfssl kubernetes-desktop-autoscaler-utility packer qemu-img
do
    if [ -z "$(command -v $MANDATORY)" ]; then
        echo_red "The command $MANDATORY is missing"
        exit 1
    fi
done

