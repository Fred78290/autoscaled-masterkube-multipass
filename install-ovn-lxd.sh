#!/bin/bash
UBUNTU_DISTRIBUTION=$1
UBUNTU_DISTRIBUTION=jammy
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
VMNAME="lxd-ovn-${UBUNTU_DISTRIBUTION}-${RANDOM}"
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

ADDRESS=$(multipass info ${VMNAME} --format=json | jq -r --arg VMNAME ${VMNAME}  '.info|.[$VMNAME].ipv4|last')

echo "SSH address used: ${ADDRESS}"

multipass shell ${VMNAME} << 'EOF'

cat > create-lxd.sh <<'SHELL'
#!/bin/bash
NET_INF=${NET_INF:=$(ip route show default 0.0.0.0/0 | sed -n '1 p' | cut -d ' ' -f 5)}
NET_CIDR=$(ip addr show ${NET_INF} | grep "inet\s" | awk '{print $2}')
NET_IP=$(echo ${NET_CIDR} | cut -d '/' -f 1)
INSTALL_BR_EX=NO

LISTEN_INF=${LISTEN_INF:=$(ip route show default 0.0.0.0/0 | sed -n '2 p' |cut -d ' ' -f 5)}
LISTEN_CIDR=$(ip addr show ${LISTEN_INF} | grep "inet\s" | awk '{print $2}')
LISTEN_IP=$(echo ${LISTEN_CIDR} | cut -d '/' -f 1)

PUBLIC_BRIDGE=br-ex
DATA_DIR=${DATA_DIR:=~/etc/lxd/ssl}
LXD_HOSTNAME=$(hostname -f)
LXD_CERT_NAME=${LXD_CERT_NAME:=lxd-cert}
LXD_CERT=${DATA_DIR}/${LXD_CERT_NAME}.pem
SSL_BUNDLE_FILE=${DATA_DIR}/ca-bundle.pem

# CA configuration
ROOT_CA_DIR=${ROOT_CA_DIR:-${DATA_DIR}/CA/root-ca}
INT_CA_DIR=${INT_CA_DIR:-${DATA_DIR}/CA/int-ca}

ORG_NAME="Aldune"
ORG_UNIT_NAME="lxd"

# Check if this is a valid ipv4 address string
function is_ipv4_address {
    local address=$1
    local regex='([0-9]{1,3}\.){3}[0-9]{1,3}'
    # TODO(clarkb) make this more robust
    if [[ "$address" =~ $regex ]] ; then
        return 0
    else
        return 1
    fi
}

# CA Functions
# ============

# Creates a new CA directory structure
# create_CA_base ca-dir
function create_CA_base {
    local ca_dir=$1

    if [[ -d ${ca_dir} ]]; then
        # Bail out it exists
        return 0
    fi

    local i

    for i in certs crl newcerts private; do
        mkdir -p ${ca_dir}/${i}
    done

    chmod 710 ${ca_dir}/private
    echo "01" >${ca_dir}/serial

    cp /dev/null ${ca_dir}/index.txt
}

# Create a new CA configuration file
# create_CA_config ca-dir common-name
function create_CA_config {
    local ca_dir=$1
    local common_name=$2

    echo "
[ ca ]
default_ca = CA_default

[ CA_default ]
dir                     = ${ca_dir}
policy                  = policy_match
database                = \$dir/index.txt
serial                  = \$dir/serial
certs                   = \$dir/certs
crl_dir                 = \$dir/crl
new_certs_dir           = \$dir/newcerts
certificate             = \$dir/cacert.pem
private_key             = \$dir/private/cacert.key
RANDFILE                = \$dir/private/.rand
default_md              = sha256

[ req ]
default_bits            = 2048
default_md              = sha256

prompt                  = no
distinguished_name      = ca_distinguished_name

x509_extensions         = ca_extensions

[ ca_distinguished_name ]
organizationName        = ${ORG_NAME}
organizationalUnitName  = ${ORG_UNIT_NAME} Certificate Authority
commonName              = ${common_name}

[ policy_match ]
countryName             = optional
stateOrProvinceName     = optional
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied

[ ca_extensions ]
basicConstraints        = critical,CA:true
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always, issuer
keyUsage                = cRLSign, keyCertSign

" >${ca_dir}/ca.conf
}

# Create a new signing configuration file
# create_signing_config ca-dir
function create_signing_config {
    local ca_dir=$1

    echo "
[ ca ]
default_ca = CA_default

[ CA_default ]
dir                     = ${ca_dir}
policy                  = policy_match
database                = \$dir/index.txt
serial                  = \$dir/serial
certs                   = \$dir/certs
crl_dir                 = \$dir/crl
new_certs_dir           = \$dir/newcerts
certificate             = \$dir/cacert.pem
private_key             = \$dir/private/cacert.key
RANDFILE                = \$dir/private/.rand
default_md              = default

[ req ]
default_bits            = 1024
default_md              = sha256

prompt                  = no
distinguished_name      = req_distinguished_name

x509_extensions         = req_extensions

[ req_distinguished_name ]
organizationName        = ${ORG_NAME}
organizationalUnitName  = ${ORG_UNIT_NAME} Server Farm

[ policy_match ]
countryName             = optional
stateOrProvinceName     = optional
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied

[ req_extensions ]
basicConstraints        = CA:false
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always, issuer
keyUsage                = digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage        = serverAuth, clientAuth
subjectAltName          = \$ENV::SUBJECT_ALT_NAME

" >${ca_dir}/signing.conf
}

# Create root and intermediate CAs
# init_CA
function init_CA {
    # Ensure CAs are built
    make_root_CA ${ROOT_CA_DIR}
    make_int_CA ${INT_CA_DIR} ${ROOT_CA_DIR}

    # Create the CA bundle
    cat ${ROOT_CA_DIR}/cacert.pem ${INT_CA_DIR}/cacert.pem >>${INT_CA_DIR}/ca-chain.pem
    cat ${INT_CA_DIR}/ca-chain.pem >> ${SSL_BUNDLE_FILE}

    sudo cp ${INT_CA_DIR}/ca-chain.pem /usr/local/share/ca-certificates/lxd-int.crt
    sudo cp ${ROOT_CA_DIR}/cacert.pem /usr/local/share/ca-certificates/lxd-root.crt
    sudo update-ca-certificates
}

# Create an initial server cert
# init_cert
function init_cert {
    if [[ ! -r ${LXD_CERT} ]]; then
        make_cert ${INT_CA_DIR} ${LXD_CERT_NAME} ${LXD_HOSTNAME} "${LISTEN_IP}"

        # Create a cert bundle
        cat ${INT_CA_DIR}/private/${LXD_CERT_NAME}.key ${INT_CA_DIR}/${LXD_CERT_NAME}.crt ${INT_CA_DIR}/cacert.pem >${LXD_CERT}
    fi
}

# make_cert creates and signs a new certificate with the given commonName and CA
# make_cert ca-dir cert-name "common-name" ["alt-name" ...]
function make_cert {
    local ca_dir=$1
    local cert_name=$2
    local common_name=$3
    local alt_names=$4

    if [ "${common_name}" != "${LISTEN_IP}" ]; then
        if is_ipv4_address "${LISTEN_IP}" ; then
            if [[ -z "${alt_names}" ]]; then
                alt_names="IP:0:0:0:0:0:0:0:1,IP:127.0.0.1,IP:${LISTEN_IP}"
            else
                alt_names="${alt_names},IP:0:0:0:0:0:0:0:1,IP:127.0.0.1,IP:${LISTEN_IP}"
            fi
        fi
    fi

    # Only generate the certificate if it doesn't exist yet on the disk
    if [ ! -r "${ca_dir}/${cert_name}.crt" ]; then
        # Generate a signing request
        openssl req \
            -sha256 \
            -newkey rsa \
            -nodes \
            -keyout ${ca_dir}/private/${cert_name}.key \
            -out ${ca_dir}/${cert_name}.csr \
            -subj "/O=${ORG_NAME}/OU=${ORG_UNIT_NAME} Servers/CN=${common_name}"

        if [[ -z "${alt_names}" ]]; then
            alt_names="DNS:${common_name}"
        else
            alt_names="DNS:${common_name},${alt_names}"
        fi

		echo SUBJECT_ALT_NAME=${alt_names}

        # Sign the request valid for 10 year
        SUBJECT_ALT_NAME="${alt_names}" \
        openssl ca -config ${ca_dir}/signing.conf \
            -extensions req_extensions \
            -days 3650 \
            -notext \
            -in ${ca_dir}/${cert_name}.csr \
            -out ${ca_dir}/${cert_name}.crt \
            -subj "/O=${ORG_NAME}/OU=${ORG_UNIT_NAME} Servers/CN=${common_name}" \
            -batch
    fi
}

# Make an intermediate CA to sign everything else
# make_int_CA ca-dir signing-ca-dir
function make_int_CA {
    local ca_dir=$1
    local signing_ca_dir=$2

    # Create the root CA
    create_CA_base ${ca_dir}
    create_CA_config ${ca_dir} 'Intermediate CA'
    create_signing_config ${ca_dir}

    if [ ! -r "${ca_dir}/cacert.pem" ]; then
        # Create a signing certificate request
        openssl req -config ${ca_dir}/ca.conf \
            -sha256 \
            -newkey rsa \
            -nodes \
            -keyout ${ca_dir}/private/cacert.key \
            -out ${ca_dir}/cacert.csr \
            -outform PEM

        # Sign the intermediate request valid for 1 year
        openssl ca -config ${signing_ca_dir}/ca.conf \
            -extensions ca_extensions \
            -days 365 \
            -notext \
            -in ${ca_dir}/cacert.csr \
            -out ${ca_dir}/cacert.pem \
            -batch
    fi
}

# Make a root CA to sign other CAs
# make_root_CA ca-dir
function make_root_CA {
    local ca_dir=$1

    # Create the root CA
    create_CA_base ${ca_dir}
    create_CA_config ${ca_dir} 'Root CA'

    if [ ! -r "${ca_dir}/cacert.pem" ]; then
        # Create a self-signed certificate valid for 5 years
        openssl req -config ${ca_dir}/ca.conf \
            -x509 \
            -nodes \
            -newkey rsa \
            -days 21360 \
            -keyout ${ca_dir}/private/cacert.key \
            -out ${ca_dir}/cacert.pem \
            -outform PEM
    fi
}

# Deploy the service cert & key to a service specific
# location
function deploy_int_cert {
    local cert_target_file=$1
    local key_target_file=$2

    sudo cp "${INT_CA_DIR}/${LXD_CERT_NAME}.crt" "${cert_target_file}"
    sudo cp "${INT_CA_DIR}/private/${LXD_CERT_NAME}.key" "${key_target_file}"
}

# Deploy the intermediate CA cert bundle file to a service
# specific location
function deploy_int_CA {
    local ca_target_file=$1

    sudo cp "${INT_CA_DIR}/ca-chain.pem" "${ca_target_file}"
}

# Certificate Input Configuration
# ===============================

# Ensure that the certificates for a service are in place. This function does
# not check that a service is SSL enabled, this should already have been
# completed.
#
# The function expects to find a certificate, key and CA certificate in the
# variables ``{service}_SSL_CERT``, ``{service}_SSL_KEY`` and ``{service}_SSL_CA``. For
# example for keystone this would be ``KEYSTONE_SSL_CERT``, ``KEYSTONE_SSL_KEY`` and
# ``KEYSTONE_SSL_CA``.
#
# If it does not find these certificates then the DevStack-issued server
# certificate, key and CA certificate will be associated with the service.
#
# If only some of the variables are provided then the function will quit.
function ensure_certificates {
    local service=$1

    local cert_var="${service}_SSL_CERT"
    local key_var="${service}_SSL_KEY"
    local ca_var="${service}_SSL_CA"

    local cert=${!cert_var}
    local key=${!key_var}
    local ca=${!ca_var}

    if [[ -z "${cert}" && -z "${key}" && -z "${ca}" ]]; then
        local cert="${INT_CA_DIR}/${LXD_CERT_NAME}.crt"
        local key="${INT_CA_DIR}/private/${LXD_CERT_NAME}.key"
        local ca="${INT_CA_DIR}/ca-chain.pem"

        eval ${service}_SSL_CERT=\${cert}
        eval ${service}_SSL_KEY=\${key}
        eval ${service}_SSL_CA=\${ca}

        return # the CA certificate is already in the bundle
    elif [[ -z "${cert}" || -z "${key}" || -z "${ca}" ]]; then
        die ${LINENO} "Missing either the ${cert_var} ${key_var} or ${ca_var}" "variable to enable SSL for ${service}"
    fi

    cat ${ca} >> ${SSL_BUNDLE_FILE}
}

# Clean up the CA files
# cleanup_CA
function cleanup_CA {
    sudo rm -f /usr/local/share/ca-certificates/lxd-int.crt
    sudo rm -f /usr/local/share/ca-certificates/lxd-root.crt

    sudo update-ca-certificates

    rm -rf "${INT_CA_DIR}" "${ROOT_CA_DIR}" "${LXD_CERT}"
}

export DEBIAN_FRONTEND=noninteractive

sudo apt update
sudo apt upgrade -y

init_CA

# Create the server cert
make_cert ${INT_CA_DIR} ${LXD_CERT_NAME} ${LXD_HOSTNAME}

# Create a cert bundle
cat ${INT_CA_DIR}/private/${LXD_CERT_NAME}.key ${INT_CA_DIR}/${LXD_CERT_NAME}.crt ${INT_CA_DIR}/cacert.pem >$LXD_CERT

sudo mkdir -p /etc/ovn

cat ${INT_CA_DIR}/private/${LXD_CERT_NAME}.key | sudo tee /etc/ovn/key_host
cat ${INT_CA_DIR}/${LXD_CERT_NAME}.crt | sudo tee /etc/ovn/cert_host
cat ${INT_CA_DIR}/ca-chain.pem | sudo tee /etc/ovn/ovn-central.crt

echo "Enter to configure OVN"

read -p "Enter to configure OVN"  TOTO

if [ $(cat /etc/os-release | grep VERSION_ID | tr -d '"' | cut -d '=' -f 2 | cut -d '.' -f 1) -lt 24 ]; then
    ARCH=$([[ "$(uname -m)" =~ arm64|aarch64 ]] && echo -n arm64 || echo -n amd64)
push /tmp
    #wget https://launchpad.net/ubuntu/+source/ovn/24.03.2-0ubuntu0.24.04.1/+build/28559446/+files/ovn-central_24.03.2-0ubuntu0.24.04.1_amd64.deb -O ovn-central.deb
    #wget https://launchpad.net/ubuntu/+source/ovn/24.03.2-0ubuntu0.24.04.1/+build/28559446/+files/ovn-common_24.03.2-0ubuntu0.24.04.1_amd64.deb -O  ovn-common.deb
    #wget https://launchpad.net/ubuntu/+source/ovn/24.03.2-0ubuntu0.24.04.1/+build/28559446/+files/ovn-controller-vtep_24.03.2-0ubuntu0.24.04.1_amd64.deb -O  ovn-controller-vtep.deb
    #wget https://launchpad.net/ubuntu/+source/ovn/24.03.2-0ubuntu0.24.04.1/+build/28559446/+files/ovn-host_24.03.2-0ubuntu0.24.04.1_amd64.deb -O  ovn-host.deb

openvswitch-switch_3.3.0-1ubuntu3_amd64.deb

    wget http://10.81.38.166/debian/python3-openvswitch_3.3.0-1ubuntu3_amd64.deb -O python3-openvswitch.deb
    wget http://10.81.38.166/debian/openvswitch-switch_3.3.0-1ubuntu3_amd64.deb -O openvswitch-switch.deb
    wget http://10.81.38.166/debian/openvswitch-common_3.3.0-1ubuntu3_amd64.deb -O openvswitch-common.deb
    wget http://10.81.38.166/debian/ovn-central_24.03.1-2ubuntu3_amd64.deb -O ovn-central.deb
    wget http://10.81.38.166/debian/ovn-common_24.03.1-2ubuntu3_amd64.deb -O  ovn-common.deb
    wget http://10.81.38.166/debian/ovn-controller-vtep_24.03.1-2ubuntu3_amd64.deb -O  ovn-controller-vtep.deb
    wget http://10.81.38.166/debian/ovn-host_24.03.1-2ubuntu3_amd64.deb -O  ovn-host.deb

    sudo apt install ./python3-openvswitch.deb ./openvswitch-switch.deb ./openvswitch-common.deb ./ovn-common.deb ./ovn-controller-vtep.deb ./ovn-central.deb ./ovn-host.deb
popd
else
    sudo apt install ovn-host ovn-central -y
fi

sudo ovs-vsctl --no-wait set-ssl /etc/ovn/key_host /etc/ovn/cert_host /etc/ovn/ovn-central.crt

sudo ovs-vsctl --no-wait set-manager ptcp:6640:127.0.0.1
sudo ovs-vsctl --no-wait set open_vswitch . system-type=lxd \
		external-ids:system-id=$(uuidgen) \
		external-ids:ovn-remote=ssl:${LISTEN_IP}:6642 \
		external-ids:ovn-bridge=br-int \
		external-ids:ovn-encap-type=geneve \
		external-ids:ovn-encap-ip=${LISTEN_IP} \
		external-ids:hostname=$(hostname -f) \
		external-ids:ovn-cms-options=enable-chassis-as-gw

sudo ovn-nbctl --db=unix:/var/run/ovn/ovnnb_db.sock set-ssl /etc/ovn/key_host /etc/ovn/cert_host /etc/ovn/ovn-central.crt
sudo ovn-sbctl --db=unix:/var/run/ovn/ovnsb_db.sock set-ssl /etc/ovn/key_host /etc/ovn/cert_host /etc/ovn/ovn-central.crt

sudo ovn-nbctl --db=unix:/var/run/ovn/ovnnb_db.sock set-connection pssl:6641:0.0.0.0 -- set connection . inactivity_probe=60000
sudo ovn-sbctl --db=unix:/var/run/ovn/ovnsb_db.sock set-connection pssl:6642:0.0.0.0 -- set connection . inactivity_probe=60000

sudo ovs-appctl -t /var/run/ovn/ovnnb_db.ctl vlog/set console:off syslog:info file:info
sudo ovs-appctl -t /var/run/ovn/ovnsb_db.ctl vlog/set console:off syslog:info file:info

if [ "${INSTALL_BR_EX}" == YES ]; then
    echo "Declare bridge ${PUBLIC_BRIDGE} with IP: ${NET_CIDR}"

    read -p "Declare bridge ${PUBLIC_BRIDGE} with IP: ${NET_CIDR}" TOTO

    sudo ovs-vsctl --no-wait -- --may-exist add-br ${PUBLIC_BRIDGE} -- set bridge ${PUBLIC_BRIDGE} protocols=OpenFlow13,OpenFlow15
    sudo ovs-vsctl --no-wait br-set-external-id ${PUBLIC_BRIDGE} bridge-id ${PUBLIC_BRIDGE}
    sudo ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:${PUBLIC_BRIDGE}
    sudo ovs-vsctl --may-exist add-br ${PUBLIC_BRIDGE} -- set bridge ${PUBLIC_BRIDGE} protocols=OpenFlow13,OpenFlow15
    sudo ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:${PUBLIC_BRIDGE}
    sudo ovs-vsctl --may-exist add-port ${PUBLIC_BRIDGE} ${NET_INF}
    sudo ovs-vsctl set Bridge ${PUBLIC_BRIDGE} other_config:disable-in-band=true

    echo "Set bridge ${PUBLIC_BRIDGE} to IP: ${NET_CIDR}"
    read -p "Set bridge ${PUBLIC_BRIDGE} to IP: ${NET_CIDR}"  TOTO

    sudo ip addr add ${NET_CIDR} dev ${PUBLIC_BRIDGE}
    sudo ip link set ${PUBLIC_BRIDGE} up
    sudo ip addr flush dev ${NET_INF}

    cat > restore-bridge.sh <<-LXDINIT
#!/bin/bash

ovs-vsctl --may-exist add-br ${PUBLIC_BRIDGE} -- set bridge ${PUBLIC_BRIDGE} protocols=OpenFlow13,OpenFlow15
ovs-vsctl set open . external-ids:ovn-bridge-mappings=public:${PUBLIC_BRIDGE}

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

sudo cp restore-bridge.sh /usr/local/bin
sudo chmod +x /usr/local/bin/restore-bridge.sh

cat > restore-bridge.service <<-LXDINIT
[Install]
WantedBy = multi-user.target

[Unit]
After = ovn-northd.service lxd-agent.service
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

lxc config set network.ovn.ca_cert="$(cat ${INT_CA_DIR}/ca-chain.pem)"
lxc config set network.ovn.client_cert="$(cat ${INT_CA_DIR}/${LXD_CERT_NAME}.crt)"
lxc config set network.ovn.client_key="$(cat ${INT_CA_DIR}/private/${LXD_CERT_NAME}.key)"
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