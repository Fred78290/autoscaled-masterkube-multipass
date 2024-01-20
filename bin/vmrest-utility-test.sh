#!/bin/bash
set -e

CURDIR=$(dirname $0)

pushd ${CURDIR}
CURDIR=${PWD}
popd

source ${CURDIR}/common.sh

rm -f *.log

SEED_ARCH=$([[ "$(uname -m)" =~ arm64|aarch64 ]] && echo -n arm64 || echo -n amd64)
TRACE_CURL=YES
TEMPLATE_NAME=jammy-server-cloudimg-seed-${SEED_ARCH}
TEMPLATE_UUID=$(vmrest_get_vmuuid ${TEMPLATE_NAME})
TARGET_IMAGE=test-vmrest-utility
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
CACHE=~/.local/vmware/cache

echo "test"
do_get "/vm/byname/ERROR"
exit

echo_blue_bold TEMPLATE_NAME=${TEMPLATE_UUID}

if [ -z "${TEMPLATE_UUID}" ] || [ "${TEMPLATE_UUID}" = "ERROR" ]; then
	echo_red_bold "${TEMPLATE_NAME} not found"
	exit 1
fi

cat > "${CACHE}/user-data" <<EOF
#cloud-config
EOF

cat > "${CACHE}/vendor-data" <<EOF
#cloud-config
timezone: ${TZ}
ssh_authorized_keys:
    - ${SSH_KEY}
users:
    - default
system_info:
    default_user:
        name: kubernetes
EOF

cat > "${CACHE}/meta-data" <<EOF
#cloud-config
local-hostname: "${TARGET_IMAGE}",
instance-id: "$(uuidgen)"
network:
    version: 2
    ethernets:
        eth0:
            dhcp4: true
        eth1:
            dhcp4: true
EOF

gzip -c9 < "${CACHE}/meta-data" | base64 -w 0 > ${CACHE}/metadata.base64
gzip -c9 < "${CACHE}/user-data" | base64 -w 0 > ${CACHE}/userdata.base64
gzip -c9 < "${CACHE}/vendor-data" | base64 -w 0 > ${CACHE}/vendordata.base64

TARGET_IMAGE_UUID=$(vmrest_create ${TEMPLATE_UUID} 2 2048 ${TARGET_IMAGE} 0 \
	"${CACHE}/metadata.base64" \
	"${CACHE}/userdata.base64" \
	"${CACHE}/vendordata.base64" \
	true \
	true)

if [ -z "${TARGET_IMAGE_UUID}" ] || [ "${TARGET_IMAGE_UUID}" == "ERROR" ]; then
	echo_red_bold "failed to create ${TARGET_IMAGE}"
	exit 1
fi

echo_blue_bold "Power On ${TARGET_IMAGE}"
vmrest_poweron ${TARGET_IMAGE_UUID}

echo_blue_bold "Wait power On ${TARGET_IMAGE}"
vmrest_wait_for_powerstate ${TARGET_IMAGE_UUID} poweredOn

vmrest_power_state ${TARGET_IMAGE_UUID}

echo_blue_bold "Wait for IP from ${TARGET_IMAGE}"
vmrest_waitip ${TARGET_IMAGE_UUID}

echo_blue_bold "Power Off ${TARGET_IMAGE}"
vmrest_poweroff ${TARGET_IMAGE_UUID}

echo_blue_bold "Wait power Off ${TARGET_IMAGE}"
vmrest_wait_for_powerstate ${TARGET_IMAGE_UUID} poweredOff

vmrest_power_state ${TARGET_IMAGE_UUID}

echo_blue_bold "Delete VM ${TARGET_IMAGE}"
vmrest_destroy ${TARGET_IMAGE_UUID}