#!/bin/bash
set -e

export INSTALL_BR_EX=NO
export DEBIAN_FRONTEND=noninteractive

LISTEN_INF=${LISTEN_INF:=$(ip route show default 0.0.0.0/0 | sed -n '2 p' |cut -d ' ' -f 5)}
LISTEN_CIDR=$(ip addr show ${LISTEN_INF} | grep "inet\s" | awk '{print $2}')
LISTEN_IP=$(echo ${LISTEN_CIDR} | cut -d '/' -f 1)

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
# Check if this is a valid ipv4 address string
#===========================================================================================================================================
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

#===========================================================================================================================================
# Creates a new CA directory structure
# create_CA_base ca-dir
#===========================================================================================================================================
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

#===========================================================================================================================================
# Create root and intermediate CAs
# init_CA
#===========================================================================================================================================
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

#===========================================================================================================================================
# Create an initial server cert
# init_cert
#===========================================================================================================================================
function init_cert {
    if [[ ! -r ${LXD_CERT} ]]; then
        make_cert ${INT_CA_DIR} ${LXD_CERT_NAME} ${LXD_HOSTNAME} "${LISTEN_IP}"

        # Create a cert bundle
        cat ${INT_CA_DIR}/private/${LXD_CERT_NAME}.key ${INT_CA_DIR}/${LXD_CERT_NAME}.crt ${INT_CA_DIR}/cacert.pem >${LXD_CERT}
    fi
}

#===========================================================================================================================================
# make_cert creates and signs a new certificate with the given commonName and CA
# make_cert ca-dir cert-name "common-name" ["alt-name" ...]
#===========================================================================================================================================
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

#===========================================================================================================================================
# Make an intermediate CA to sign everything else
# make_int_CA ca-dir signing-ca-dir
#===========================================================================================================================================
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

#===========================================================================================================================================
# Make a root CA to sign other CAs
# make_root_CA ca-dir
#===========================================================================================================================================
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

#===========================================================================================================================================
# Deploy the service cert & key to a service specific location
#===========================================================================================================================================
function deploy_int_cert {
    local cert_target_file=$1
    local key_target_file=$2

    sudo cp "${INT_CA_DIR}/${LXD_CERT_NAME}.crt" "${cert_target_file}"
    sudo cp "${INT_CA_DIR}/private/${LXD_CERT_NAME}.key" "${key_target_file}"
}

#===========================================================================================================================================
# Deploy the intermediate CA cert bundle file to a service specific location
#===========================================================================================================================================
function deploy_int_CA {
    local ca_target_file=$1

    sudo cp "${INT_CA_DIR}/ca-chain.pem" "${ca_target_file}"
}

#===========================================================================================================================================
# Certificate Input Configuration
#===========================================================================================================================================
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

#===========================================================================================================================================
# Clean up the CA files
# cleanup_CA
#===========================================================================================================================================
function cleanup_CA {
    sudo rm -f /usr/local/share/ca-certificates/lxd-int.crt
    sudo rm -f /usr/local/share/ca-certificates/lxd-root.crt

    sudo update-ca-certificates

    rm -rf "${INT_CA_DIR}" "${ROOT_CA_DIR}" "${LXD_CERT}"
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
init_CA

# Create the server cert
make_cert ${INT_CA_DIR} ${LXD_CERT_NAME} ${LXD_HOSTNAME}

# Create a cert bundle
cat ${INT_CA_DIR}/private/${LXD_CERT_NAME}.key ${INT_CA_DIR}/${LXD_CERT_NAME}.crt ${INT_CA_DIR}/cacert.pem >$LXD_CERT

sudo mkdir -p /etc/ovn

cat ${INT_CA_DIR}/private/${LXD_CERT_NAME}.key | sudo tee /etc/ovn/key_host
cat ${INT_CA_DIR}/${LXD_CERT_NAME}.crt | sudo tee /etc/ovn/cert_host
cat ${INT_CA_DIR}/ca-chain.pem | sudo tee /etc/ovn/ovn-central.crt

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

lxc config set network.ovn.ca_cert="$(cat ${INT_CA_DIR}/ca-chain.pem)"
lxc config set network.ovn.client_cert="$(cat ${INT_CA_DIR}/${LXD_CERT_NAME}.crt)"
lxc config set network.ovn.client_key="$(cat ${INT_CA_DIR}/private/${LXD_CERT_NAME}.key)"
lxc config set network.ovn.northbound_connection=ssl:${LISTEN_IP}:6641

lxc network create ovntest --type=ovn network=lxdbr0 ipv4.address=10.68.223.1/24 ipv4.nat=true volatile.network.ipv4.address=192.168.48.192

sudo ip route add 10.68.223.0/24 via 192.168.48.192

cat > /tmp/ovn-routes.service <<EOF
[Install]
WantedBy = multi-user.target

[Unit]
After = snap.lxd.activate.service
Description = Service for routes to lxd ovn network

[Service]
Type = oneshot
TimeoutStopSec = 30
Restart = on-failure
SyslogIdentifier = restore-ovn-routes
ExecStart = sudo ip route add 10.68.223.0/24 via 192.168.48.192
EOF

sudo cp /tmp/ovn-routes.service /etc/systemd/system/ovn-routes.service
sudo systemctl daemon-reload
sudo systemctl enable ovn-routes.service