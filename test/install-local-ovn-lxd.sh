#!/bin/bash
set -e

UBUNTU_DISTRIBUTION=noble
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
VMNAME="lxd-ovn-${UBUNTU_DISTRIBUTION}-${RANDOM}"
VMNETWORK=
VMCPU=4
VMMEMORY=8
VMDISK=40

OPTIONS=(
    "cpu:"
    "disk:"
    "memory:"
    "network:"
    "ssh-key:"
    "ubuntu:"
)

PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o u:d:c:m:n:k: --long "${PARAMS}"  -n "$0" -- "$@")

eval set -- "${TEMP}"

while true ; do
	#echo "1:$1"
	case "$1" in
		-u|--ubuntu)
			UBUNTU_DISTRIBUTION="$2"
            VMNAME="lxd-ovn-${UBUNTU_DISTRIBUTION}-${RANDOM}"
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
		-n|--network)
			VMNETWORK="$2"
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

for PREVIOUS in $(multipass ls | grep '\-ovn-' | cut -d ' ' -f 1)
do
    multipass delete ${PREVIOUS} -p
done

if [ -n "${VMNETWORK}" ]; then
    VMNETWORK="--network name=${VMNETWORK}"
fi

multipass launch -n ${VMNAME} -c ${VMCPU} -m ${VMMEMORY}G -d ${VMDISK}G ${VMNETWORK} ${UBUNTU_DISTRIBUTION}
multipass exec ${VMNAME} -- bash -c "echo '${SSH_KEY}' >> ~/.ssh/authorized_keys"
multipass exec ${VMNAME} -- sudo bash -c "apt update"
multipass exec ${VMNAME} -- sudo bash -c "DEBIAN_FRONTEND=noninteractive apt upgrade -y"
multipass restart ${VMNAME}

sleep 2

multipass shell ${VMNAME} << 'EOF'

cat > create-lxd.sh <<'SHELL'
#!/bin/bash
set -e

export INSTALL_BR_EX=NO
export DEBIAN_FRONTEND=noninteractive

LISTEN_INF=${LISTEN_INF:=$(ip route show default 0.0.0.0/0 | sed -n '2 p' |cut -d ' ' -f 5)}
LISTEN_CIDR=$(ip addr show ${LISTEN_INF} | grep "inet\s" | awk '{print $2}')
LISTEN_IP=$(echo ${LISTEN_CIDR} | cut -d '/' -f 1)

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
    local CONTAINER_IP=

    echo_blue_bold "Create instance ${NAME}"

    lxc launch ubuntu:noble ${NAME} --network=ovntest

    start_console_green_italic
    lxc exec ${NAME} -- apt update
    lxc exec ${NAME} -- bash -c 'DEBIAN_FRONTEND=noninteractive apt upgrade -y'
    lxc exec ${NAME} -- apt install nginx -y
    stop_console_green_italic

    echo_blue_dot_title "Wait ip instance ${NAME}"

    while [ -z "${CONTAINER_IP}" ]; do
        CONTAINER_IP=$(lxc list name=${NAME} --format=json | jq -r '.[0].state.network|.eth0.addresses[]|select(.family == "inet")|.address')
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

    lxc list name=${NAME} --format=json | jq -r '.[0].state.network|.eth0.addresses[]|select(.family == "inet")|.address'
}

#===========================================================================================================================================
# INSTALL PACKAGES
#===========================================================================================================================================
sudo apt update
sudo apt upgrade -y
sudo apt install jq socat conntrack net-tools traceroute nfs-common unzip -y
sudo snap install yq

#===========================================================================================================================================
# CONFIGURE OVN
#===========================================================================================================================================
sudo apt install ovn-host ovn-central -y
sudo ovs-vsctl set open_vswitch . \
   external_ids:ovn-remote=unix:/var/run/ovn/ovnsb_db.sock \
   external_ids:ovn-encap-type=geneve \
   external_ids:ovn-encap-ip=127.0.0.1

cat > restore-bridge.sh <<-LXDINIT
#!/bin/bash
ip route add 10.68.223.0/24 via 192.168.48.192
LXDINIT

sudo cp restore-bridge.sh /usr/local/bin
sudo chmod +x /usr/local/bin/restore-bridge.sh

#===========================================================================================================================================
# INSTALL SERVICE RESTORE ROUTE
#===========================================================================================================================================
cat > restore-bridge.service <<-LXDINIT
[Install]
WantedBy = multi-user.target

[Unit]
After = ovn-northd.service snap.lxd.daemon.service
Description = Service for adding physical ip to ovn bridge

[Service]
Type = oneshot
TimeoutStopSec = 30
Restart = no
SyslogIdentifier = restore-devstack
ExecStart = /usr/local/bin/restore-bridge.sh
LXDINIT

sudo cp restore-bridge.service /etc/systemd/system 
sudo systemctl enable restore-bridge.service

#===========================================================================================================================================
# INSTALL LXD
#===========================================================================================================================================
if [ -z "$(snap list | grep lxd)" ]; then
    sudo snap install lxd --channel=6.1/stable
elif [[ "$(snap list | grep lxd)" != *6.1* ]]; then
    sudo snap refresh lxd --channel=6.1/stable
fi

lxd init --preseed <<< $(cat << LXDINIT
config:
  core.https_address: '[::]:8443'
networks:
- config:
    ipv4.address: 192.168.48.1/24
    ipv4.dhcp.ranges: 192.168.48.128-192.168.48.159
    ipv4.ovn.ranges: 192.168.48.192-192.168.48.253
    ipv4.routes: 192.168.50.0/24
    ipv4.nat: true
  description: ""
  name: lxdbr0
  type: ""
  project: default
storage_pools:
- config: {}
  description: ""
  name: default
  driver: dir
storage_volumes: []
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
projects: []
cluster: null
LXDINIT
)

#===========================================================================================================================================
# CREATE OVN NETWORK
#===========================================================================================================================================
echo_blue_bold "Create ovntest"

lxc network create ovntest --type=ovn network=lxdbr0 ipv4.address=10.68.223.1/24 ipv4.nat=true volatile.network.ipv4.address=192.168.48.192

sudo ip route add 10.68.223.0/24 via 192.168.48.192

#===========================================================================================================================================
# CREATE CONTAINERS
#===========================================================================================================================================
launch_container u1
launch_container u2

U1_IP=$(container_ip u1)
U2_IP=$(container_ip u2)

echo_blue_bold "Create instance u3"
lxc launch ubuntu:noble u3 --network=lxdbr0

lxc ls

#===========================================================================================================================================
# CREATE OVN LOAD BALANCER
#===========================================================================================================================================
NLB_VIP_ADDRESS=$(lxc network load-balancer create ovntest --allocate=ipv4 | cut -d ' ' -f 4)

echo_blue_bold "NLB_VIP_ADDRESS=${NLB_VIP_ADDRESS}"

lxc network load-balancer backend add ovntest ${NLB_VIP_ADDRESS} u1 ${U1_IP} 80,443
lxc network load-balancer backend add ovntest ${NLB_VIP_ADDRESS} u2 ${U2_IP} 80,443
lxc network load-balancer port add ovntest ${NLB_VIP_ADDRESS} tcp 80,443 u1,u2

#===========================================================================================================================================
# PATCH OVN LOAD BALANCER
#===========================================================================================================================================
OVN_CHASSIS_UUID=$(sudo ovn-sbctl show | grep Chassis | cut -d ' ' -f 2 | tr -d '"')
OVN_NLB_NAME=$(sudo ovn-nbctl find load_balancer | grep "lb-${NLB_VIP_ADDRESS}-tcp" | awk '{print $3}')
OVN_ROUTER_NAME="${OVN_NLB_NAME%-lb*}-lr"

sudo ovn-nbctl --wait=hv set logical_router ${OVN_ROUTER_NAME} options:chassis=${OVN_CHASSIS_UUID}
sleep 2

#===========================================================================================================================================
# TEST OVN LOAD BALANCER
#===========================================================================================================================================
#echo_blue_bold "Check load balancer on host"
curl http://${NLB_VIP_ADDRESS}

echo_blue_bold "Check load balancer on u3"
lxc exec u3 -- curl http://${NLB_VIP_ADDRESS}

echo_blue_bold "Check load balancer on u1"
lxc exec u1 -- curl http://${NLB_VIP_ADDRESS}

SHELL

chmod +x create-lxd.sh
exit 0

EOF

multipass exec ${VMNAME} -- ./create-lxd.sh

echo "multipass shell ${VMNAME}"