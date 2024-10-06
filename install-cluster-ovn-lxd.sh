#!/bin/bash
set -e

UBUNTU_DISTRIBUTION=noble
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
ROOTNAME="lxd-cluster-ovn-${UBUNTU_DISTRIBUTION}-${RANDOM}"
VMNETWORK=
VMCPU=2
VMMEMORY=3
VMDISK=10
NODE_IPS=()
INSTANCE_IPS=()
CREATE_LXDBR0=physical #main|bridged|physical

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
      ROOTNAME="lxd-cluster-ovn-${UBUNTU_DISTRIBUTION}-${RANDOM}"
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
function launch_container() {
    local REMOTE=$1
    local NAME=$2
    local TARGET=$3
    local CONTAINER_IP=

    echo_blue_bold "Create instance ${NAME}"

    lxc launch ubuntu:noble ${REMOTE}:${NAME} --network=ovntest

    start_console_green_italic
    lxc exec ${REMOTE}:${NAME} -- apt update
    lxc exec ${REMOTE}:${NAME} -- bash -c 'DEBIAN_FRONTEND=noninteractive apt upgrade -y'
    lxc exec ${REMOTE}:${NAME} -- apt install nginx -y
    stop_console_green_italic

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
# CREATE BRIDGED LXDBR0 NETWORK
#===========================================================================================================================================
function create_bridge_lxdbr0() {
  echo_blue_bold "Create bridged lxdbr0 network"

  NETWORK_OPTIONS="ipv4.address=192.168.48.1/24 ipv4.dhcp.ranges=192.168.48.128-192.168.48.159 ipv4.ovn.ranges=192.168.48.192-192.168.48.253 ipv4.routes=192.168.50.0/24 ipv4.nat=true"

  for INDEX in $(seq 0 2)
  do
      VMNAME=${ROOTNAME}-0${INDEX}

      lxc network create ${ROOTNAME}:lxdbr0 --type=bridge --target ${VMNAME}
  done

  lxc network create ${ROOTNAME}:lxdbr0 --type=bridge ${NETWORK_OPTIONS}
}

#===========================================================================================================================================
# CREATE LXDBR0 NETWORK ON PHYSICAL BR0
#===========================================================================================================================================
function create_physical_lxdbr0() {
  echo_blue_bold "Create physical lxdbr0 network"

  DNSSERVER="${NODE_IPS[0]%.*}.1"
  NETWORK_OPTIONS="dns.nameservers=${DNSSERVER} ipv4.ovn.ranges=192.168.48.192-192.168.48.253 ipv4.routes=192.168.50.0/24 ipv4.gateway=${NODE_IPS}/24"

  for INDEX in $(seq 0 2)
  do
      VMNAME=${ROOTNAME}-0${INDEX}

      lxc network create ${ROOTNAME}:lxdbr0 --type=physical --target ${VMNAME} parent=br0
  done

  lxc network create ${ROOTNAME}:lxdbr0 --type=physical ${NETWORK_OPTIONS}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
for PREVIOUS in $(multipass ls | grep '\-cluster-ovn-' | cut -d ' ' -f 1)
do
    multipass stop ${PREVIOUS} --force
    multipass delete ${PREVIOUS} -p
done

#===========================================================================================================================================
# INSTALL PACKAGES
#===========================================================================================================================================
if [ -n "${VMNETWORK}" ]; then
    VMNETWORK="--network name=${VMNETWORK}"
fi

for INDEX in $(seq 0 2)
do
    VMNAME=${ROOTNAME}-0${INDEX}

    if [ -z "$(multipass info ${VMNAME} --format json 2>/dev/null)" ]; then
      echo_blue_bold "Start VM: ${VMNAME}"

      multipass launch -n ${VMNAME} -c ${VMCPU} -m ${VMMEMORY}G -d ${VMDISK}G ${VMNETWORK} ${UBUNTU_DISTRIBUTION}
      multipass exec ${VMNAME} -- bash -c "echo '${SSH_KEY}' >> ~/.ssh/authorized_keys"
      multipass exec ${VMNAME} -- sudo bash -c "apt update"
      multipass exec ${VMNAME} -- sudo bash -c "DEBIAN_FRONTEND=noninteractive apt upgrade -y"
      multipass exec ${VMNAME} -- sudo bash -c "apt install jq bridge-utils net-tools traceroute unzip ovn-host ovn-central -y"

      ROUTEINFOS=$(multipass exec ${VMNAME} -- bash -c "ip route get 1")
      GATEWAY=$(awk '{print $3;exit}' <<<"${ROUTEINFOS}")
      ADDRESS=$(awk '{print $7;exit}' <<<"${ROUTEINFOS}")

      NETINF=$(awk '{print $5;exit}' <<<"${ROUTEINFOS}")
      MACADDRESS=$(multipass exec ${VMNAME} -- bash -c "ip addr show ${NETINF}" | grep ether | awk '{print $2}')
      DOMAIN=$(multipass exec ${VMNAME} -- resolvectl status ${NETINF} | grep 'DNS Domain:' | awk '{print $3}')

      multipass shell ${VMNAME} <<SHELL
      cat > 60-br0.yaml <<EOF
network:
  version: 2
  renderer: networkd
  bridges:
    br0:
      dhcp4: false
      dhcp6: false
      addresses:
      - ${ADDRESS}/24
      routes:
      - to: default
        via: ${GATEWAY}
        metric: 100
      nameservers:
        addresses:
        - ${GATEWAY}
        search:
        - ${DOMAIN}
      interfaces:
      - ${NETINF}
EOF

sudo cp 60-br0.yaml /etc/netplan
sudo chmod 600 /etc/netplan/60-br0.yaml
SHELL
      echo_blue_bold "Restart VM: ${VMNAME}"
      multipass restart ${VMNAME}

      sleep 2
    
      echo_blue_bold "Configure VM: ${VMNAME}"
      multipass exec ${VMNAME} -- sudo bash -c "snap install yq"
      multipass exec ${VMNAME} -- sudo bash -c "snap install lxd --channel=6.1/stable"
      multipass exec ${VMNAME} -- lxd waitready
  fi

    echo_blue_bold "Get IP VM: ${VMNAME}"
    NODE_IPS[${INDEX}]=$(multipass_infos ${VMNAME} | jq -r --arg NAME ${VMNAME} '.info|.[$NAME].ipv4|first')

done

echo ${NODE_IPS[@]@K}

#===========================================================================================================================================
# CONFIGURE OVN
#===========================================================================================================================================
for INDEX in $(seq 0 2)
do
    VMNAME=${ROOTNAME}-0${INDEX}
    ADDR=${NODE_IPS[${INDEX}]}
    OVN_CTL_OPTS="--db-nb-addr=${ADDR} \
        --db-nb-create-insecure-remote=yes \
        --db-sb-addr=${ADDR} \
        --db-sb-create-insecure-remote=yes \
        --db-nb-cluster-local-addr=${ADDR} \
        --db-sb-cluster-local-addr=${ADDR} \
        --ovn-northd-nb-db=tcp:${NODE_IPS[0]}:6641,tcp:${NODE_IPS[1]}:6641,tcp:${NODE_IPS[2]}:6641 \
        --ovn-northd-sb-db=tcp:${NODE_IPS[0]}:6642,tcp:${NODE_IPS[1]}:6642,tcp:${NODE_IPS[2]}:6642"

    echo_blue_bold "Configure OVN on: ${VMNAME}"

    multipass shell ${VMNAME} <<EOF
cat > create-ovn.sh <<'SHELL'
#!/bin/bash
set -e

systemctl enable ovn-host

systemctl stop ovn-central
systemctl stop ovn-host

echo "OVN_CTL_OPTS=${OVN_CTL_OPTS}" >> /etc/default/ovn-central

if [ ${INDEX} -eq 0 ]; then
    systemctl enable ovn-central
    systemctl restart ovn-central
    systemctl restart ovn-host
else
    systemctl disable ovn-central
    systemctl restart ovn-host
fi

    ovs-vsctl set open_vswitch . \
        external_ids:ovn-remote=tcp:${NODE_IPS[0]}:6642,tcp:${NODE_IPS[1]}:6642,tcp:${NODE_IPS[2]}:6642 \
        external_ids:ovn-encap-type=geneve \
        external_ids:ovn-encap-ip=${ADDR}
SHELL
    chmod +x create-ovn.sh
EOF

    multipass exec ${VMNAME} -- sudo ./create-ovn.sh
done

#===========================================================================================================================================
# INSTALL LXD
#===========================================================================================================================================
for INDEX in $(seq 0 2)
do
    VMNAME=${ROOTNAME}-0${INDEX}
    ADDR=${NODE_IPS[${INDEX}]}

    echo_blue_bold "Configure LXD on: ${VMNAME}"

    if [ ${INDEX} -eq 0 ]; then
      if [ "${CREATE_LXDBR0}" == "main" ]; then
        multipass shell ${VMNAME} <<EOF
cat > config.yaml << SHELL
config:
  core.https_address: '${NODE_IPS[${INDEX}]}:8443'
  network.ovn.northbound_connection: "tcp:${NODE_IPS[0]}:6641,tcp:${NODE_IPS[1]}:6641,tcp:${NODE_IPS[2]}:6641"
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
- name: local
  driver: dir
profiles:
- name: default
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: local
      type: disk
cluster:
  server_name: ${VMNAME}
  enabled: true
SHELL
EOF
      else
        multipass shell ${VMNAME} <<EOF
cat > config.yaml << SHELL
config:
  core.https_address: '${NODE_IPS[${INDEX}]}:8443'
  network.ovn.northbound_connection: "tcp:${NODE_IPS[0]}:6641,tcp:${NODE_IPS[1]}:6641,tcp:${NODE_IPS[2]}:6641"
networks:
- config:
    bridge.mode: fan
    fan.underlay_subnet: auto
  name: lxdfan0
  project: default
storage_pools:
- name: local
  driver: dir
profiles:
- name: default
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdfan0
      type: nic
    root:
      path: /
      pool: local
      type: disk
cluster:
  server_name: ${VMNAME}
  enabled: true
SHELL
EOF
      fi
    else
      TOKEN=$(multipass exec ${ROOTNAME}-00 -- lxc cluster add ${VMNAME} | sed -n 2p)

      multipass shell ${VMNAME} <<EOF
cat > config.yaml << SHELL
cluster:
  server_name: ${VMNAME}
  enabled: true
  member_config:
  - entity: storage-pool
    name: local
    key: source
    value: ""
  - entity: storage-pool
    name: local
    key: driver
    value: dir
  cluster_address: ${NODE_IPS[0]}:8443
  server_address: ${ADDR}:8443
  cluster_token: "${TOKEN}"
SHELL

EOF
    fi

    multipass exec "${VMNAME}" -- bash -c "cat config.yaml | lxd init --preseed"
done

#===========================================================================================================================================
# CREATE ADD REMOTE
#===========================================================================================================================================
echo_blue_bold "Add remote: ${ROOTNAME}"

LXD_TOKEN=$(multipass exec ${ROOTNAME}-00 -- lxc config trust add --name ${ROOTNAME} | sed -n '2 p')
lxc remote add ${ROOTNAME} ${NODE_IPS[0]} --token ${LXD_TOKEN} --accept-certificate

#===========================================================================================================================================
# CREATE LXD NETWORK
#===========================================================================================================================================
if [ "${CREATE_LXDBR0}" == "bridged" ]; then
  create_bridge_lxdbr0
elif [ "${CREATE_LXDBR0}" == "physical" ]; then
  create_physical_lxdbr0
fi

#===========================================================================================================================================
# CREATE OVN NETWORK
#===========================================================================================================================================
echo_blue_bold "Create ovntest network"
lxc network create ${ROOTNAME}:ovntest --type=ovn network=lxdbr0 ipv4.address=10.68.223.1/24 ipv4.nat=true volatile.network.ipv4.address=192.168.48.192

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

lxc network load-balancer port add ${ROOTNAME}:ovntest ${NLB_VIP_ADDRESS} tcp 80,443 backend-00,backend-01,backend-02

sudo bash -c "cat > /etc/nginx/tcpconf.d/lxdcluster.conf <<EOF
server {
  listen 0.0.0.0:8443;
  proxy_pass ${INSTANCE_IPS[0]}:8443;
}
EOF
"

sudo systemctl restart nginx
