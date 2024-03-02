#!/bin/bash

#set -e

# This script will create 2 VM used as template
# The first one is the seed VM customized to use vmware guestinfos cloud-init datasource instead ovf datasource.
# This step is done by importing https://cloud-images.ubuntu.com/${DISTRO}/current/${DISTRO}-server-cloudimg-amd64.ova
# If don't have the right to import OVA with govc to your vpshere you can try with ovftool import method else you must build manually this seed
# Jump to Prepare seed VM comment.
# Very important, shutdown the seed VM by using shutdown guest or shutdown -P now. Never use PowerOff vsphere command
# This VM will be used to create the kubernetes template VM 

# The second VM will contains everything to run kubernetes
set -eu

IMPORTMODE="govc"
PRIMARY_NETWORK_ADAPTER=vmxnet3
PRIMARY_NETWORK_NAME="${GOVC_NETWORK}"
SECOND_NETWORK_ADAPTER=vmxnet3
SECOND_NETWORK_NAME=
TARGET_IMAGE=
FOLDER_OPTIONS=

OPTIONS=(
	"distribution:"
	"custom-image:"
	"ssh-key:"
	"ssh-priv-key:"
	"cni-version:"
	"password:"
	"seed:"
	"arch:"
	"user:"
	"kubernetes-version:"
	"primary-network:"
	"second-network:"
	"k8s-distribution:"
	"container-runtime:"
)

PARAMS=$(echo ${OPTIONS[*]} | tr ' ' ',')
TEMP=$(getopt -o d:i:k:n:p:s:a:u:v: --long "${PARAMS}"  -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true ; do
	#echo "1:$1"
	case "$1" in
		-d|--distribution)
			DISTRO="$2"
			SEED_IMAGE=${DISTRO}-server-cloudimg-seed
			shift 2
			;;
		-i|--custom-image) TARGET_IMAGE="$2" ; shift 2;;
		-k|--ssh-key) SSH_KEY=$2 ; shift 2;;
		--ssh-priv-key) SSH_PRIVATE_KEY=$2 ; shift 2;;
		-n|--cni-version) CNI_VERSION=$2 ; shift 2;;
		-p|--password) KUBERNETES_PASSWORD=$2 ; shift 2;;
		-s|--seed) SEED_IMAGE=$2 ; shift 2;;
		-a|--arch) SEED_ARCH=$2 ; shift 2;;
		-u|--user) KUBERNETES_USER=$2 ; shift 2;;
		-v|--kubernetes-version) KUBERNETES_VERSION=$2 ; shift 2;;
		--primary-network) PRIMARY_NETWORK_NAME=$2 ; shift 2;;
		--second-network) SECOND_NETWORK_NAME=$2 ; shift 2;;
		--k8s-distribution) 
			case "$2" in
				kubeadm|k3s|rke2|microk8s)
				KUBERNETES_DISTRO=$2
				;;
			*)
				echo "Unsupported kubernetes distribution: $2"
				exit 1
				;;
			esac
			shift 2
			;;
		--container-runtime)
			CONTAINER_ENGINE="$2"
			case "$2" in
				"docker")
					CONTAINER_CTL=docker
					;;
				"cri-o"|"containerd")
					CONTAINER_CTL=crictl
					;;
				*)
					echo_red_bold "Unsupported container runtime: $2"
					exit 1
					;;
			esac
			shift 2;;
		--primary-adapter) PRIMARY_NETWORK_ADAPTER=$2 ; shift 2;;
		--second-adapter) SECOND_NETWORK_ADAPTER=$2 ; shift 2;;
		-o|--ovftool) IMPORTMODE=ovftool ; shift 2;;
		--) shift ; break ;;
		*) echo_red_bold "$1 - Internal error!" ; exit 1 ;;
	esac
done

SSH_OPTIONS="${SSH_OPTIONS} -i ${SSH_PRIVATE_KEY}"
SCP_OPTIONS="${SCP_OPTIONS} -i ${SSH_PRIVATE_KEY}"

if [ -z "${TARGET_IMAGE}" ]; then
	TARGET_IMAGE=${DISTRO}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}
fi

if [ -n "$(govc vm.info ${TARGET_IMAGE} 2>&1)" ]; then
	echo_blue_bold "${TARGET_IMAGE} already exists!"
	exit 0
fi

echo_blue_bold "Ubuntu password:${KUBERNETES_PASSWORD}"

BOOTSTRAP_PASSWORD=$(uuidgen)
read -a VCENTER <<< "$(echo ${GOVC_URL} | awk -F/ '{print $3}' | tr '@' ' ')"
VCENTER=${VCENTER[${#VCENTER[@]} - 1]}

USERDATA=$(base64 <<EOF
#cloud-config
password: ${BOOTSTRAP_PASSWORD}
ssh_pwauth: true
chpasswd: 
  expire: false
  users:
    - name: ubuntu
      password: ${KUBERNETES_PASSWORD}
      type: text
EOF
)

# If your seed image isn't present create one by import ${DISTRO} cloud ova.
# If you don't have the access right to import with govc (firewall rules blocking https traffic to esxi),
# you can try with ovftool to import the ova.
# If you have the bug "unsupported server", you must do it manually!
if [ -z "$(govc vm.info ${SEED_IMAGE} 2>&1)" ]; then
	[ -f ${CACHE}/${DISTRO}-server-cloudimg-${SEED_ARCH}.ova ] || curl -Ls https://cloud-images.ubuntu.com/${DISTRO}/current/${DISTRO}-server-cloudimg-${SEED_ARCH}.ova -o ${CACHE}/${DISTRO}-server-cloudimg-amd64.ova

	if [ "${IMPORTMODE}" == "govc" ]; then
		govc import.spec ${CACHE}/${DISTRO}-server-cloudimg-${SEED_ARCH}.ova \
			| jq \
				--arg GOVC_NETWORK "${PRIMARY_NETWORK_NAME}" \
				'.NetworkMapping = [ { Name: "VM Network", Network: $GOVC_NETWORK } ]' \
			> ${CACHE}/${DISTRO}-server-cloudimg-${SEED_ARCH}.spec
		
		cat ${CACHE}/${DISTRO}-server-cloudimg-${SEED_ARCH}.spec \
			| jq --arg SSH_KEY "${SSH_KEY}" \
				--arg SSH_KEY "${SSH_KEY}" \
				--arg USERDATA "${USERDATA}" \
				--arg BOOTSTRAP_PASSWORD "${BOOTSTRAP_PASSWORD}" \
				--arg NAME "${SEED_IMAGE}" \
				--arg INSTANCEID $(uuidgen) \
				--arg TARGET_IMAGE "${TARGET_IMAGE}" \
				'.Name = $NAME | .PropertyMapping |= [ { Key: "instance-id", Value: $INSTANCEID }, { Key: "hostname", Value: $TARGET_IMAGE }, { Key: "public-keys", Value: $SSH_KEY }, { Key: "user-data", Value: $USERDATA }, { Key: "password", Value: $BOOTSTRAP_PASSWORD } ]' \
				> ${CACHE}/${DISTRO}-server-cloudimg-${SEED_ARCH}.txt

		DATASTORE="/${GOVC_DATACENTER}/datastore/${GOVC_DATASTORE}"
		FOLDER="/${GOVC_DATACENTER}/vm/${GOVC_FOLDER}"

		echo_blue_bold "Import ${DISTRO}-server-cloudimg-${SEED_ARCH}.ova to ${SEED_IMAGE} with govc"
		govc import.ova \
			-options=${CACHE}/${DISTRO}-server-cloudimg-${SEED_ARCH}.txt \
			-folder="${FOLDER}" \
			-ds="${DATASTORE}" \
			-name="${SEED_IMAGE}" \
			${CACHE}/${DISTRO}-server-cloudimg-${SEED_ARCH}.ova
	else
		echo_blue_bold "Import ${DISTRO}-server-cloudimg-${SEED_ARCH}.ova to ${SEED_IMAGE} with ovftool"

		MAPPED_NETWORK=$(govc import.spec ${CACHE}/${DISTRO}-server-cloudimg-${SEED_ARCH}.ova | jq -r '.NetworkMapping[0].Name//""')

		ovftool \
			--acceptAllEulas \
			--name="${SEED_IMAGE}" \
			--datastore="${GOVC_DATASTORE}" \
			--vmFolder="${GOVC_FOLDER}" \
			--diskMode=thin \
			--prop:instance-id="$(uuidgen)" \
			--prop:hostname="${SEED_IMAGE}" \
			--prop:public-keys="${SSH_KEY}" \
			--prop:user-data="${USERDATA}" \
			--prop:password="${BOOTSTRAP_PASSWORD}" \
			--net:"${MAPPED_NETWORK}"="${PRIMARY_NETWORK_NAME}" \
			https://cloud-images.ubuntu.com/${DISTRO}/current/${DISTRO}-server-cloudimg-${SEED_ARCH}.ova \
			"vi://${GOVC_USERNAME}:${GOVC_PASSWORD}@${VCENTER}/${GOVC_RESOURCE_POOL}/"
	fi

	if [ $? -eq 0 ]; then

		if [ -n "${PRIMARY_NETWORK_ADAPTER}" ];then
			echo_blue_bold "Change primary network card ${PRIMARY_NETWORK_NAME} to ${PRIMARY_NETWORK_ADAPTER} on ${SEED_IMAGE}"

			govc vm.network.change -vm "${SEED_IMAGE}" -net="${PRIMARY_NETWORK_NAME}" -net.adapter=${PRIMARY_NETWORK_ADAPTER} ethernet-0
		fi

		# Never add second network 
		# if $(jq --arg SECOND_NETWORK_NAME "${SECOND_NETWORK_NAME}" '.network.interfaces | select(.network = $SECOND_NETWORK_NAME)|.exists' provider.json) == false
		if [ -n "${SECOND_NETWORK_NAME}" ]; then
			echo_blue_bold "Add second network card ${SECOND_NETWORK_NAME} on ${SEED_IMAGE}"

			govc vm.network.add -vm "${SEED_IMAGE}" -net="${SECOND_NETWORK_NAME}" -net.adapter="${SECOND_NETWORK_ADAPTER}"
		fi

		echo_blue_bold "Power On ${SEED_IMAGE}"
		govc vm.upgrade -version=17 -vm ${SEED_IMAGE}
		govc vm.power -on "${SEED_IMAGE}"

		echo_blue_bold "Wait for IP from ${SEED_IMAGE}"
		IPADDR=$(govc vm.ip -wait 5m "${SEED_IMAGE}")

		if [ -z "${IPADDR}" ]; then
			echo_red_bold "Can't get IP!"
			exit -1
		fi

		# Prepare seed VM
		echo_blue_bold "Install cloud-init VMWareGuestInfo datasource"

		ssh -t "${SEED_USER}@${IPADDR}" <<EOF
		sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/' /etc/default/grub
		sudo update-grub
		sudo apt update
		sudo apt upgrade -y
		sudo apt install jq socat conntrack net-tools traceroute nfs-common unzip -y
		sudo snap install yq
		sudo sh -c 'echo datasource_list: [ NoCloud, VMware ] > /etc/cloud/cloud.cfg.d/99-VMWare-Only.cfg'
		exit 
EOF

		echo_blue_bold "clean cloud-init"
		ssh -t "${SEED_USER}@${IPADDR}" <<EOF
		sudo cloud-init clean
		sudo cloud-init clean -l
		exit
EOF

		# Shutdown the guest
		govc vm.power -persist-session=false -s "${SEED_IMAGE}"

		echo_blue_dot_title "Wait ${SEED_IMAGE} to shutdown"
		while [ $(govc vm.info -json "${SEED_IMAGE}" | jq -r '.virtualMachines[0].runtime.powerState') == "poweredOn" ]
		do
			echo_blue_dot
			sleep 1
		done
		echo

		echo_blue_bold "${SEED_IMAGE} is ready"
	else
		echo_red_bold "Import failed!"
		exit -1
	fi 
else
	echo_blue_bold "${SEED_IMAGE} already exists, nothing to do!"
fi

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | tr '.' ' ' | awk '{ print $2 }')
CRIO_VERSION=$(echo -n ${KUBERNETES_VERSION} | tr -d 'v' | tr '.' ' ' | awk '{ print $1"."$2 }')

echo_blue_bold "Prepare ${TARGET_IMAGE} image with cri-o version: ${CRIO_VERSION} and kubernetes: ${KUBERNETES_VERSION}"

cat > "${CACHE}/user-data" <<EOF
#cloud-config
write_files:
- encoding: b64
  content: $(cat ${CURDIR}/prepare-image.sh | base64 -w 0)
  owner: root:adm
  path: /usr/local/bin/prepare-image.sh
  permissions: '0755'
EOF

cat > "${CACHE}/network.yaml" <<EOF
#cloud-config
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF

cat > "${CACHE}/vendor-data" <<EOF
#cloud-config
timezone: ${TZ}
ssh_authorized_keys:
  - ${SSH_KEY}
users:
  - name: ${KUBERNETES_USER}
    groups: users, admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    shell: /bin/bash
    plain_text_passwd: ${KUBERNETES_PASSWORD}
    ssh_authorized_keys:
      - ${SSH_KEY}
EOF

cat > "${CACHE}/meta-data" <<EOF
{
	"local-hostname": "${TARGET_IMAGE}",
	"instance-id": "$(uuidgen)"
}
EOF

gzip -c9 < "${CACHE}/meta-data" | base64 -w 0 > ${CACHE}/metadata.base64
gzip -c9 < "${CACHE}/user-data" | base64 -w 0 > ${CACHE}/userdata.base64
gzip -c9 < "${CACHE}/vendor-data" | base64 -w 0 > ${CACHE}/vendordata.base64

# Due to my vsphere center the folder name refer more path, so I need to precise the path instead
if [ "${GOVC_FOLDER}" ]; then
	FOLDERS=$(govc folder.info ${GOVC_FOLDER}|grep Path|wc -l)
	if [ "${FOLDERS}" != "1" ]; then
		FOLDER_OPTIONS="-folder=/${GOVC_DATACENTER}/vm/${GOVC_FOLDER}"
	fi
fi

govc vm.clone -on=false ${FOLDER_OPTIONS} -c=2 -m=4096 -vm=${SEED_IMAGE} ${TARGET_IMAGE}

govc vm.change -vm "${TARGET_IMAGE}" \
	-e disk.enableUUID=1 \
	-e guestinfo.metadata="$(cat ${CACHE}/metadata.base64)" \
	-e guestinfo.metadata.encoding="gzip+base64" \
	-e guestinfo.userdata="$(cat ${CACHE}/userdata.base64)" \
	-e guestinfo.userdata.encoding="gzip+base64" \
	-e guestinfo.vendordata="$(cat ${CACHE}/vendordata.base64)" \
	-e guestinfo.vendordata.encoding="gzip+base64"

echo_blue_bold "Power On ${TARGET_IMAGE}"
govc vm.power -on "${TARGET_IMAGE}"

echo_blue_bold "Wait for IP from ${TARGET_IMAGE}"
IPADDR=$(govc vm.ip -wait 5m "${TARGET_IMAGE}")

ssh ${SSH_OPTIONS} -t "${KUBERNETES_USER}@${IPADDR}" sudo /usr/local/bin/prepare-image.sh \
						--container-runtime ${CONTAINER_ENGINE} \
						--cni-version ${CNI_VERSION} \
						--cni-plugin ${CNI_PLUGIN} \
						--kubernetes-version ${KUBERNETES_VERSION} \
						--k8s-distribution ${KUBERNETES_DISTRO}

govc vm.power -persist-session=false -s=true "${TARGET_IMAGE}"

echo_blue_dot_title "Wait ${TARGET_IMAGE} to shutdown"
while [ $(govc vm.info -json "${TARGET_IMAGE}" | jq .virtualMachines[0].runtime.powerState | tr -d '"') == "poweredOn" ]
do
	echo_blue_dot
	sleep 1
done
echo

echo_blue_bold "Created image ${TARGET_IMAGE} with kubernetes version ${KUBERNETES_VERSION}"

exit 0
