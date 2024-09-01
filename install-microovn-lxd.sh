#!/bin/bash
UBUNTU_DISTRIBUTION=$1
UBUNTU_DISTRIBUTION=jammy
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
VMNAME="lxd-microovn-${UBUNTU_DISTRIBUTION}-${RANDOM}"
VMNETWORK=mpbr1
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
            VMNAME="lxd-microovn-${UBUNTU_DISTRIBUTION}-${RANDOM}"
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

multipass launch -n ${VMNAME} -c ${VMCPU} -m ${VMMEMORY}G -d ${VMDISK}G --network name=${VMNETWORK} ${UBUNTU_DISTRIBUTION}
multipass exec ${VMNAME} -- bash -c "echo '${SSH_KEY}' >> ~/.ssh/authorized_keys"

ADDRESS=$(multipass info ${VMNAME} --format json | jq --arg VMNAME ${VMNAME} -r '.info|.[$VMNAME].ipv4|last')

echo "SSH address used: ${ADDRESS}"

multipass shell ${VMNAME} << 'EOF'

cat > create-lxd.sh <<'SHELL'
#!/bin/bash
NET_INF=$(ip route show default 0.0.0.0/0 | sed -n '1 p' | cut -d ' ' -f 5)
NET_CIDR=$(ip addr show ${NET_INF} | grep "inet\s" | awk '{print $2}')
NET_IP=$(echo ${NET_CIDR} | cut -d '/' -f 1)
INSTALL_BR_EX=NO

LISTEN_INF=$(ip route show default 0.0.0.0/0 | sed -n '2 p' |cut -d ' ' -f 5)
LISTEN_CIDR=$(ip addr show ${LISTEN_INF} | grep "inet\s" | awk '{print $2}')
LISTEN_IP=$(echo ${LISTEN_CIDR} | cut -d '/' -f 1)

PUBLIC_BRIDGE=br-ex

echo "Enter to configure MicroOVN"

read -p "Enter to configure MicroOVN"  TOTO

sudo snap install microovn --channel=24.03/beta
sudo microovn cluster bootstrap

if [ "${INSTALL_BR_EX}" == YES ]; then
    echo "Declare bridge ${PUBLIC_BRIDGE} with IP: ${NET_CIDR}"

    read -p "Declare bridge ${PUBLIC_BRIDGE} with IP: ${NET_CIDR}" TOTO

    sudo microovn.ovs-vsctl --no-wait -- --may-exist add-br ${PUBLIC_BRIDGE} -- set bridge ${PUBLIC_BRIDGE} protocols=OpenFlow13,OpenFlow15
    sudo microovn.ovs-vsctl --no-wait br-set-external-id ${PUBLIC_BRIDGE} bridge-id ${PUBLIC_BRIDGE}
    sudo microovn.ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:${PUBLIC_BRIDGE}
    sudo microovn.ovs-vsctl --may-exist add-br ${PUBLIC_BRIDGE} -- set bridge ${PUBLIC_BRIDGE} protocols=OpenFlow13,OpenFlow15
    sudo microovn.ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:${PUBLIC_BRIDGE}
    sudo microovn.ovs-vsctl --may-exist add-port ${PUBLIC_BRIDGE} ${NET_INF}
    sudo microovn.ovs-vsctl set Bridge ${PUBLIC_BRIDGE} other_config:disable-in-band=true

    echo "Set bridge ${PUBLIC_BRIDGE} to IP: ${NET_CIDR}"
    read -p "Set bridge ${PUBLIC_BRIDGE} to IP: ${NET_CIDR}"  TOTO

    sudo ip addr add ${NET_CIDR} dev ${PUBLIC_BRIDGE}
    sudo ip link set ${PUBLIC_BRIDGE} up
    sudo ip addr flush dev ${NET_INF}

    cat > restore-bridge.sh <<-LXDINIT
#!/bin/bash

microovn.ovs-vsctl --may-exist add-br ${PUBLIC_BRIDGE} -- set bridge ${PUBLIC_BRIDGE} protocols=OpenFlow13,OpenFlow15
microovn.ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:${PUBLIC_BRIDGE}

ip addr add ${NET_CIDR} dev ${PUBLIC_BRIDGE}
ip link set ${PUBLIC_BRIDGE} up
ip addr flush dev ${NET_INF}
ip route add 10.68.223.0/24 via 192.168.48.192

LXDINIT

else

    cat > restore-bridge.sh <<-LXDINIT
#!/bin/bash
ip route add 10.68.223.0/24 via 192.168.48.192
LXDINIT

fi

for CMD in /snap/bin/microovn.*
do
    LONGNAME=$(basename ${CMD})
    SHORTNAME=$(cut -d '.' -f 2 <<<${LONGNAME})
    sudo cat >>/usr/local/bin/${SHORTNAME}<<LXDINIT
#!/bin/sh
${LONGNAME} $@
LXDINIT
    echo ${SHORTNAME}
    sudo chmod +x /usr/local/bin/${SHORTNAME}
done

sudo cp restore-bridge.sh /usr/local/bin
sudo chmod +x /usr/local/bin/restore-bridge.sh

cat > restore-bridge.service <<-LXDINIT
[Install]
WantedBy = multi-user.target

[Unit]
After = microovn.ovn-northd.service lxd-agent.service
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

ip a

echo "Enter to configure LXD"

read -p "Enter to configure LXD"  TOTO

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

lxc config set network.ovn.ca_cert="$(sudo cat /var/snap/microovn/common/data/pki/cacert.pem)"
lxc config set network.ovn.client_cert="$(sudo cat /var/snap/microovn/common/data/pki/ovn-northd-cert.pem)"
lxc config set network.ovn.client_key="$(sudo cat /var/snap/microovn/common/data/pki/ovn-northd-privkey.pem)"
lxc config set network.ovn.northbound_connection=ssl:${LISTEN_IP}:6641

echo "Create ovntest"

lxc network create ovntest --type=ovn network=lxdbr0 ipv4.address=10.68.223.1/24 ipv4.nat=true volatile.network.ipv4.address=192.168.48.192

sudo ip route add 10.68.223.0/24 via 192.168.48.192

#echo "Create instance u1"
#lxc launch ubuntu:noble u1 --network=ovntest

SHELL

chmod +x create-lxd.sh
exit 0

EOF

ssh -o "StrictHostKeyChecking no" ubuntu@${ADDRESS} ./create-lxd.sh