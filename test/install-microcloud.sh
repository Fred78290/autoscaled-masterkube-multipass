#!/bin/bash
set -e

UBUNTU_DISTRIBUTION=jammy
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
ROOTNAME="lxd-microcloud-${UBUNTU_DISTRIBUTION}-${RANDOM}"
VMCPU=2
VMMEMORY=4
VMDISK=10
NODE_IPS=()
INSTANCE_IPS=()
OVNNAME=default
export PRIMARY_INF=enp5s0
export SECONDARY_INF=enp6s0

OPTIONS=(
    "cpu:"
    "disk:"
    "memory:"
    "ssh-key:"
    "ubuntu:"
)

PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o u:d:c:m:k: --long "${PARAMS}"  -n "$0" -- "$@")

eval set -- "${TEMP}"

while true ; do
	#echo "1:$1"
	case "$1" in
		-u|--ubuntu)
			UBUNTU_DISTRIBUTION="$2"
      ROOTNAME="lxd-microcloud-${UBUNTU_DISTRIBUTION}-${RANDOM}"
			shift 2
			;;
		-d|--disk)
			VMDISK="$2"
			shift 2
			;;
		-c|--cpu)
			VMCPU="$2"
			shift 2
			;;
		-m|--memory)
			VMMEMORY="$2"
			shift 2
			;;
		-k|--ssh-key)
			SSH_KEY="$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo_red "$1 - Internal error!"
			exit 1
			;;
    esac
done

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
function start_console_green_italic() {
    echo -e "\x1B[3m\x1B[32m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function stop_console_green_italic() {
    echo -e "\x1B[23m\x1B[39m"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function launch_container() {
    local NAME=$1
    local TARGET=$2
    local NETINF=${3:-eth0}

    echo_blue_bold "Create instance ${NAME}"

    lxc launch ubuntu:noble ${NAME}

    start_console_green_italic
    lxc exec ${NAME} -- apt update
    lxc exec ${NAME} -- bash -c 'DEBIAN_FRONTEND=noninteractive apt upgrade -y'
    lxc exec ${NAME} -- apt install nginx -y
    stop_console_green_italic

    wait_container_ip ${NAME} ${NETINF}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_container_ip() {
    local NAME=$1
    local NETINF=${2:-eth0}
    local CONTAINER_IP=

    echo_blue_dot_title "Wait ip instance ${NAME}"

    while [ -z "${CONTAINER_IP}" ]; do
        CONTAINER_IP=$(lxc list ${NAME} --format=json | (jq -r --arg NETINF ${NETINF} '.[0].state.network|.[$NETINF].addresses[]|select(.family == "inet")|.address' 2>/dev/null || :))
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
    local NETINF=${2:-eth0}

    lxc list ${NAME} --format=json | jq -r --arg NETINF ${NETINF} '.[0].state.network|.[$NETINF].addresses[]|select(.family == "inet")|.address'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
for PREVIOUS in $(lxc ls -f json | jq -r '.[].name' | grep '\-microcloud-')
do
    lxc stop ${PREVIOUS} --force || :
    lxc delete ${PREVIOUS} || :
done

#===========================================================================================================================================
# INSTALL PACKAGES
#===========================================================================================================================================
HOST_ROUTEINFOS=$(ip route get 1)
HOST_NETINF=$(awk '{print $5;exit}' <<<"${HOST_ROUTEINFOS}")
HOST_DNS=$(resolvectl status ${HOST_NETINF} | grep 'Current DNS Server:' | awk '{print $4}')

lxc storage create disks dir 2>/dev/null || :
lxc storage set disks volume.size ${VMDISK}GiB 2>/dev/null || :
lxc network create microbr0 2>/dev/null || :

for INDEX in $(seq 1 4)
do
    VMNAME=${ROOTNAME}-0${INDEX}
    LOCALSTORAGE=local-0${INDEX}
    REMOTESTORAGE=remote-0${INDEX}

    echo_blue_bold "Start VM: ${VMNAME}"

    if [ -n "$(lxc storage volume list disks | grep ${LOCALSTORAGE})" ]; then
      lxc storage volume delete disks ${LOCALSTORAGE}
    fi

    if [ -n "$(lxc storage volume list disks | grep ${REMOTESTORAGE})" ]; then
      lxc storage volume delete disks ${REMOTESTORAGE}
    fi

    lxc init ubuntu:${UBUNTU_DISTRIBUTION} ${VMNAME} --vm --config limits.cpu=${VMCPU} --config limits.memory=${VMMEMORY}GiB
    lxc storage volume create disks local-0${INDEX} --type block size=${VMDISK}GiB
    lxc storage volume attach disks local-0${INDEX} ${VMNAME}
    lxc config device add ${VMNAME} eth1 nic network=microbr0 name=eth1

    lxc storage volume create disks ${REMOTESTORAGE} --type block size=$((VMDISK*2))GiB
    lxc storage volume attach disks ${REMOTESTORAGE} ${VMNAME}

    lxc start ${VMNAME}
    
    wait_container_ip ${VMNAME} ${PRIMARY_INF}

    lxc exec ${VMNAME} -- apt update
    lxc exec ${VMNAME} -- bash -c 'DEBIAN_FRONTEND=noninteractive apt upgrade -y'
    lxc exec ${VMNAME} -- apt install jq bridge-utils net-tools traceroute unzip -y

    echo_blue_bold "Configure VM: ${VMNAME}"

    lxc shell ${VMNAME} <<SHELL

#cat >> /etc/sysctl.d/99-disable-ipv6.conf <<EOF
# Disable ipv6
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv6.conf.default.disable_ipv6 = 1
#net.ipv6.conf.lo.disable_ipv6 = 1
#EOF

#sysctl -p

#sed -i 's/#MulticastDNS=no/MulticastDNS=yes/' /etc/systemd/resolved.conf
#mkdir -p /etc/systemd/network/10-netplan-${PRIMARY_INF}.network.d

#cat << EOF > /etc/systemd/network/10-netplan-${PRIMARY_INF}.network.d/override.conf
#[Network]
#MulticastDNS=yes
#EOF

cat << EOF > /etc/netplan/99-microcloud.yaml
network:
  version: 2
  ethernets:
    ${SECONDARY_INF}:
      accept-ra: false
      dhcp4: false
      link-local: []
EOF

chmod 0600 /etc/netplan/99-microcloud.yaml
netplan apply
SHELL

    lxc exec ${VMNAME} -- snap install yq

    if [ -z "$(snap list|grep lxd)" ]; then
      lxc exec ${VMNAME} -- snap install lxd --channel=6.1/stable --cohort="+"
    else
      lxc exec ${VMNAME} -- snap refresh lxd --channel=6.1/stable  --cohort="+"
    fi

    lxc exec ${VMNAME} -- snap install microceph --channel=quincy/stable --cohort="+"
    lxc exec ${VMNAME} -- snap install microovn --channel=22.03/stable --cohort="+"
    lxc exec ${VMNAME} -- snap install microcloud --channel=latest/stable --cohort="+"
    lxc exec ${VMNAME} -- microcloud waitready

#    lxc exec ${VMNAME} -- mkdir -p /var/snap/microovn/common/state/certificates
#    lxc exec ${VMNAME} -- mkdir -p /var/snap/microceph/common/state/certificates
#    lxc exec ${VMNAME} -- snap start microceph
#    lxc exec ${VMNAME} -- snap start microovn

    echo_blue_bold "Restart VM: ${VMNAME}"
    lxc restart ${VMNAME}

    wait_container_ip ${VMNAME} ${PRIMARY_INF}

    NODE_IPS[${INDEX}]=$(container_ip ${VMNAME} ${PRIMARY_INF})
done

#===========================================================================================================================================
# MICROCLOUD INIT
#===========================================================================================================================================
LEADER_NAME=${ROOTNAME}-01

lxc shell ${LEADER_NAME} <<SHELL
cat > microcloud-init.yaml <<EOF
lookup_subnet: \$(ip addr show ${PRIMARY_INF} | grep 'inet ' | awk '{print \$2}')
lookup_interface: ${PRIMARY_INF}
systems:
- name: ${ROOTNAME}-01
  ovn_uplink_interface: ${SECONDARY_INF}
#  ovn_underlay_ip: 10.0.2.101
  storage:
    local:
      path: /dev/sdb
      wipe: true
    ceph:
      - path: /dev/sdc
        wipe: true
        encrypt: false
- name: ${ROOTNAME}-02
  ovn_uplink_interface: ${SECONDARY_INF}
#  ovn_underlay_ip: 10.0.2.102
  storage:
    local:
      path: /dev/sdb
      wipe: true
    ceph:
      - path: /dev/sdc
        wipe: true
        encrypt: false
- name: ${ROOTNAME}-03
  ovn_uplink_interface: ${SECONDARY_INF}
#  ovn_underlay_ip: 10.0.2.103
  storage:
    local:
      path: /dev/sdb
      wipe: true
    ceph:
      - path: /dev/sdc
        wipe: true
        encrypt: false
- name: ${ROOTNAME}-04
  ovn_uplink_interface: ${SECONDARY_INF}
#  ovn_underlay_ip: 10.0.2.104
  storage:
    local:
      path: /dev/sdb
      wipe: true
    ceph:
      - path: /dev/sdc
        wipe: true
        encrypt: false
ceph:
  cephfs: true
#  internal_network: 10.0.1.0/24
ovn:
  ipv4_gateway: 192.0.2.1/24
  ipv4_range: 192.0.2.100-192.0.2.254
  dns_servers: ${HOST_DNS}
EOF
#cat microcloud-init.yaml | microcloud init --preseed
SHELL
exit
#===========================================================================================================================================
# CREATE ADD REMOTE
#===========================================================================================================================================
echo_blue_bold "Add remote: ${ROOTNAME}"

LXD_TOKEN=$(lxc exec ${ROOTNAME}-01 -- lxc config trust add --name ${ROOTNAME} | sed -n '2 p')
lxc remote add ${ROOTNAME} ${NODE_IPS[1]} --token ${LXD_TOKEN} --accept-certificate

#===========================================================================================================================================
# CREATE CONTAINERS
#===========================================================================================================================================
echo_blue_bold "Create all containers"

for INDEX in $(seq 1 4)
do
  CONTAINER_NAME=container-0${INDEX}

  launch_container ${ROOTNAME}:${CONTAINER_NAME} ${ROOTNAME}-0${INDEX}

  INSTANCE_IPS[${INDEX}]=$(container_ip ${ROOTNAME}:${CONTAINER_NAME})
done

#echo_blue_bold "Create instance container-03"
#lxc launch ubuntu:noble ${ROOTNAME}:container-03 --network=lxdbr0

lxc ls ${ROOTNAME}:

exit
#===========================================================================================================================================
# CREATE OVN LOAD BALANCER
#===========================================================================================================================================
NLB_VIP_ADDRESS=$(lxc network load-balancer create ${ROOTNAME}:${OVNNAME} --allocate=ipv4 | cut -d ' ' -f 4)

echo_blue_bold "NLB_VIP_ADDRESS=${NLB_VIP_ADDRESS}"

for INDEX in $(seq 0 2)
do
  lxc network load-balancer backend add ${ROOTNAME}:${OVNNAME} ${NLB_VIP_ADDRESS} backend-0${INDEX} ${INSTANCE_IPS[${INDEX}]} 80,443
done

lxc network load-balancer port add ${ROOTNAME}:${OVNNAME} ${NLB_VIP_ADDRESS} tcp 80,443 backend-00,backend-01,backend-02

sudo bash -c "cat > /etc/nginx/tcpconf.d/lxdcluster.conf <<EOF
server {
  listen 0.0.0.0:8443;
  proxy_pass ${INSTANCE_IPS[0]}:8443;
}
EOF
"

sudo systemctl restart nginx
