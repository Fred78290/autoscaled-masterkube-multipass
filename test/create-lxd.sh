#!/bin/bash
set -e

LXD_REMOTE=lxdcluster:
OVNNETWORK=ovntest

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_bold() {
	# echo message in blue and bold
	echo -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[39m\x1B[1m\x1B[34m$@\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_dot_title() {
	# echo message in blue and bold
	echo -n -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[39m\x1B[1m\x1B[34m$@\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_blue_dot() {
	echo -n -e "\x1B[90m\x1B[39m\x1B[1m\x1B[34m.\x1B[0m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function launch_container() {
    local NAME=$1
    local TARGET=$2
    local CONTAINER_IP=

    echo_blue_bold "Create instance ${NAME}"

    lxc launch ubuntu:noble ${LXD_REMOTE}${NAME} --network=${OVNNETWORK}

    lxc exec ${LXD_REMOTE}${NAME} -- apt update
    lxc exec ${LXD_REMOTE}${NAME} -- bash -c 'DEBIAN_FRONTEND=noninteractive apt upgrade -y'
    lxc exec ${LXD_REMOTE}${NAME} -- apt install nginx -y

    echo_blue_dot_title "Wait ip instance ${LXD_REMOTE}${NAME}"

    while [ -z "${CONTAINER_IP}" ]; do
        CONTAINER_IP=$(lxc list ${LXD_REMOTE} name=${NAME} --format=json | jq -r '.[0].state.network|.eth0.addresses[]|select(.family == "inet")|.address')
        sleep 1
        echo_blue_dot
    done
    echo
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function container_ip() {
    local NAME=$1

    lxc list ${LXD_REMOTE} name=${NAME} --format=json | jq -r '.[0].state.network|.eth0.addresses[]|select(.family == "inet")|.address'
}

#===========================================================================================================================================
# CREATE CONTAINERS
#===========================================================================================================================================

launch_container u1
launch_container u2

U1_IP=$(container_ip u1)
U2_IP=$(container_ip u2)

#===========================================================================================================================================
# CREATE OVN LOAD BALANCER
#===========================================================================================================================================

NLB_VIP_ADDRESS=$(lxc network load-balancer create ${LXD_REMOTE}${OVNNETWORK} --allocate=ipv4 | cut -d ' ' -f 4)

echo_blue_bold "NLB_VIP_ADDRESS=${NLB_VIP_ADDRESS}"

lxc network load-balancer backend add ${LXD_REMOTE}${OVNNETWORK} ${NLB_VIP_ADDRESS} u1 ${U1_IP} 80,443
lxc network load-balancer backend add ${LXD_REMOTE}${OVNNETWORK} ${NLB_VIP_ADDRESS} u2 ${U2_IP} 80,443
lxc network load-balancer port add ${LXD_REMOTE}${OVNNETWORK} ${NLB_VIP_ADDRESS} tcp 80,443 u1,u2

lxc ls

curl http://${NLB_VIP_ADDRESS}

