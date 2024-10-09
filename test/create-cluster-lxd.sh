#!/bin/bash
set -e

LXD_REMOTE=lxdcluster:
OVNNETWORK=ovntest
ROOTNAME=lxdcluster
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
    local REMOTE=$1
    local NAME=$2
    local TARGET=$3
    local CONTAINER_IP=

    echo_blue_bold "Create instance ${NAME}"

    lxc launch ubuntu:noble ${NAME} --network=ovntest

    lxc exec ${REMOTE}:${NAME} -- apt update
    lxc exec ${REMOTE}:${NAME} -- bash -c 'DEBIAN_FRONTEND=noninteractive apt upgrade -y'
    lxc exec ${REMOTE}:${NAME} -- apt install nginx -y

    echo_blue_dot_title "Wait ip instance ${REMOTE}:${NAME}"

    while [ -z "${CONTAINER_IP}" ]; do
        CONTAINER_IP=$(lxc list ${REMOTE}: name=${NAME} --format=json | jq -r '.[0].state.network|.eth0.addresses[]|select(.family == "inet")|.address')
        sleep 1
        echo_blue_dot
    done
    echo
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function container_ip() {
    local REMOTE=$1
    local NAME=$2

    lxc list ${REMOTE}: name=${NAME} --format=json | jq -r '.[0].state.network|.eth0.addresses[]|select(.family == "inet")|.address'
}

#===========================================================================================================================================
# CREATE CONTAINERS
#===========================================================================================================================================
echo_blue_bold "Create all containers"

for INDEX in $(seq 0 2)
do
  CONTAINER_NAME=container-0${INDEX}
  launch_container ${ROOTNAME} ${CONTAINER_NAME} ${ROOTNAME}-0${INDEX}
  INSTANCE_IPS[${INDEX}]=$(container_ip ${ROOTNAME} ${CONTAINER_NAME})
done

echo_blue_bold "Create instance u3"
lxc launch ubuntu:noble ${ROOTNAME}:container-03 --network=lxdbr0

lxc ls ${ROOTNAME}:

#===========================================================================================================================================
# CREATE OVN LOAD BALANCER
#===========================================================================================================================================
NLB_VIP_ADDRESS=$(lxc network load-balancer create ${ROOTNAME}:ovntest --allocate=ipv4 | cut -d ' ' -f 4)

echo_blue_bold "NLB_VIP_ADDRESS=${NLB_VIP_ADDRESS}"

for INDEX in $(seq 0 2)
do
  lxc network load-balancer backend add ${ROOTNAME}:ovntest ${NLB_VIP_ADDRESS} backend-0${INDEX} ${INSTANCE_IPS[${INDEX}]} 80,443
done

lxc network load-balancer port add ovntest ${NLB_VIP_ADDRESS} tcp 80,443 backend-00,backend-01,backend-02


