#!/bin/bash

#set -e

# This script will create 2 VM used as template
# The first one is the seed VM customized to use vmware guestinfos cloud-init datasource instead ovf datasource.
# This step is done by importing https://cloud-images.ubuntu.com/${DISTRO}/current/${DISTRO}-server-cloudimg-amd64.ova
# Jump to Prepare seed VM comment.
# Very important, shutdown the seed VM by using shutdown guest or shutdown -P now. Never use PowerOff vmware desktop command
# This VM will be used to create the kubernetes template VM 

# The second VM will contains everything to run kubernetes

PRIMARY_NETWORK_NAME=vmnet0
SECOND_NETWORK_NAME=vmnet8
TARGET_IMAGE=

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
	"aws-access-key:"
	"aws-secret-key:"
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
				kubeadm|k3s|rke2)
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
			case "$2" in
				"docker")
					CONTAINER_ENGINE="$2"
					CONTAINER_CTL=docker
					;;
				"cri-o"|"containerd")
					CONTAINER_ENGINE="$2"
					CONTAINER_CTL=crictl
					;;
				*)
					echo_red_bold "Unsupported container runtime: $2"
					exit 1
					;;
			esac
			shift 2;;

		--aws-access-key)
			AWS_ACCESS_KEY_ID=$2
			shift 2
			;;
		--aws-secret-key)
			AWS_SECRET_ACCESS_KEY=$2
			shift 2
			;;

		--) shift ; break ;;
		*) echo_red_bold "$1 - Internal error!" ; exit 1 ;;
	esac
done

if [ -z "${TARGET_IMAGE}" ]; then
	TARGET_IMAGE=${DISTRO}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}
fi

TARGET_IMAGE_UUID=$(vmrest_get_vmuuid ${TARGET_IMAGE})

if [ -n "${TARGET_IMAGE_UUID}" ]; then
	echo_blue_bold "${TARGET_IMAGE} already exists!"
	exit 0
fi

echo_blue_bold "Ubuntu password:${KUBERNETES_PASSWORD}"

cat > "${CACHE}/user-data" <<EOF
#cloud-config
EOF

cat > "${CACHE}/vendor-data" <<EOF
#cloud-config
package_upgrade: true
package_update: true
packages:
  - jq
  - socat
  - conntrack
  - net-tools
  - traceroute
  - nfs-common
  - unzip
timezone: ${TZ}
password: ${KUBERNETES_PASSWORD}
ssh_pwauth: true
chpasswd:
  expire: false
ssh_authorized_keys:
  - ${SSH_KEY}
users:
  - default
system_info:
  default_user:
    name: ubuntu
runcmd:
  - sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/' /etc/default/grub
  - update-grub
EOF

cat > "${CACHE}/meta-data" <<EOF
{
	"local-hostname": "${SEED_IMAGE}",
	"instance-id": "$(uuidgen)"
}
EOF

METADATA=$(gzip -c9 < "${CACHE}/meta-data" | base64 -w 0)
USERDATA=$(gzip -c9 < "${CACHE}/user-data" | base64 -w 0)
VENDORDATA=$(gzip -c9 < "${CACHE}/vendor-data" | base64 -w 0)

# If your seed image isn't present create one by import ${DISTRO} cloud ova.
SEEDIMAGE_UUID=$(vmrest_get_vmuuid "${SEED_IMAGE}")

function update_vmx() {
	local VMX="$1"
	local METADATA=$2
	local USERDATA=$3
	local VENDORDATA=$4
	local BASENAME=$(basename "${VMX}")
	local NAME=${BASENAME:0:${#BASENAME}-4}
	local GUESTOS=

	if [ ${SEED_ARCH} == "arm64" ]; then
		GUESTOS=arm-ubuntu-64
	else
		GUESTOS=ubuntu-64
	fi

	sed -i \
		-e '/displayname/Id' \
		-e '/guestinfo/Id' \
		-e '/guestos/Id' \
		-e '/memsize/Id' \
		-e '/numvcpus/Id' "${VMX}"

	cat >> "${VMX}" <<EOF
memsize = "3072"
numvcpus = "2"
displayname = "${NAME}"
guestos = "${GUESTOS}"
guestinfo.metadata = "${METADATA}"
guestinfo.metadata.encoding = "gzip+base64"
guestinfo.userdata = "${USERDATA}"
guestinfo.userdata.encoding = "gzip+base64"
guestinfo.vendordata = "${VENDORDATA}"
guestinfo.vendordata.encoding = "gzip+base64"
EOF
}

if [ -z "${SEEDIMAGE_UUID}" ] || [ "${SEEDIMAGE_UUID}" == "ERROR" ]; then
	CLOUDIMG_NAME=${DISTRO}-server-cloudimg-${SEED_ARCH}

	if [ ! -f ${CACHE}/${CLOUDIMG_NAME}.ova ]; then

		if [ ${SEED_ARCH} = "arm64" ]; then
			if [ ! -f "${CACHE}/${CLOUDIMG_NAME}.img" ]; then
				echo_blue_bold "Download https://${CLOUD_IMAGES_UBUNTU}/${DISTRO}/current/${CLOUDIMG_NAME}.img"
				curl -Ls "https://${CLOUD_IMAGES_UBUNTU}/${DISTRO}/current/${CLOUDIMG_NAME}.img" -o "${CACHE}/${CLOUDIMG_NAME}.img"
			else
				echo_blue_bold "Img already exists ${CACHE}/${CLOUDIMG_NAME}.img"
			fi

			if [ ! -f "${CACHE}/${CLOUDIMG_NAME}.vmdk" ]; then
				echo_blue_bold "Convert qemu-img convert ${CACHE}/${CLOUDIMG_NAME}.img to ${CACHE}/${CLOUDIMG_NAME}.vmdk"
				qemu-img convert "${CACHE}/${CLOUDIMG_NAME}.img" -O vmdk "${CACHE}/${CLOUDIMG_NAME}.vmdk"
			else
				echo_blue_bold "Vmdk already exists ${CACHE}/${CLOUDIMG_NAME}.vmdk"
			fi

			SIZE_VMDK=$(stat "${CACHE}/${CLOUDIMG_NAME}.vmdk" | cut -d ' ' -f 8)

			sed s/ovf:size=.*\ /ovf:size=\"${SIZE_VMDK}\"\ / "${CURDIR}/../templates/ubuntu-ovf/ubuntu-${DISTRO}-cloudimg.ovf" > "${CACHE}/${CLOUDIMG_NAME}.ovf"
			
			SHA_OVF=$(sha256sum "${CACHE}/${CLOUDIMG_NAME}.ovf" | cut -d ' ' -f 1)
			SHA_VMDK=$(sha256sum "${CACHE}/${CLOUDIMG_NAME}.vmdk" | cut -d ' ' -f 1)

			echo "SHA256(${CLOUDIMG_NAME}.vmdk)= ${SHA_VMDK}" > ${CACHE}/${CLOUDIMG_NAME}.mf
			echo "SHA256(${CLOUDIMG_NAME}.ovf)= ${SHA_OVF}" >> ${CACHE}/${CLOUDIMG_NAME}.mf

			echo_blue_bold "Build OVA ${CACHE}/${CLOUDIMG_NAME}.ova"

			ovftool --overwrite --allowExtraConfig --allowAllExtraConfig "${CACHE}/${CLOUDIMG_NAME}.ovf" "${CACHE}/${CLOUDIMG_NAME}.ova"
		else
			curl -Ls "https://${CLOUD_IMAGES_UBUNTU}/${DISTRO}/current/${CLOUDIMG_NAME}.ova" -o "${CACHE}/${CLOUDIMG_NAME}.ova"
		fi

	fi

	echo_blue_bold "Import ${CLOUDIMG_NAME}.ova to ${SEED_IMAGE} with ovftool"

	VMFOLDER="${VMREST_FOLDER}/${SEED_IMAGE}${VMWAREWM}"
	VMX="${VMFOLDER}/${SEED_IMAGE}.vmx"

	ovftool \
		--acceptAllEulas \
		--allowExtraConfig \
		--allowAllExtraConfig \
		--name="${SEED_IMAGE}" \
		${CACHE}/${CLOUDIMG_NAME}.ova \
		"${VMREST_FOLDER}"

	if [ $? -eq 0 ]; then

		echo_blue_bold "Register ${SEED_IMAGE} '${VMX}'"

		update_vmx "${VMX}" ${METADATA} ${USERDATA} ${VENDORDATA}

		SEEDIMAGE_UUID=$(vmrest_vm_register ${SEED_IMAGE} "${VMX}")

		if [ -z "${SEEDIMAGE_UUID}" ] || [ "${SEEDIMAGE_UUID}" == "ERROR" ]; then
			echo_red_bold "Register ${SEED_IMAGE} failed!"
			rm -rf "${VMFOLDER}"
			exit -1
		fi

		if [ -n "${PRIMARY_NETWORK_NAME}" ];then
			echo_blue_bold "Change primary network card ${PRIMARY_NETWORK_NAME} on ${SEED_IMAGE}"

			vmrest_network_change ${SEEDIMAGE_UUID} ${PRIMARY_NETWORK_NAME} 1 > /dev/null
		fi

		echo_blue_bold "Power On ${SEED_IMAGE}"
		vmrest_poweron "${SEEDIMAGE_UUID}" > /dev/null

		echo_blue_bold "Wait for IP from ${SEED_IMAGE}"
		IPADDR=$(vmrest_waitip "${SEEDIMAGE_UUID}")

		if [ -z "${IPADDR}" ] || [ "${IPADDR}" == "ERROR" ]; then
			echo_red_bold "Can't get IP!"
			exit -1
		fi

		echo_blue_bold "Wait ssh ready for ${IPADDR}"
		wait_ssh_ready ${SEED_USER}@${IPADDR}

		echo_blue_bold "Update seed image ${SEED_IMAGE}"

		ssh -t "${SEED_USER}@${IPADDR}" "sudo apt update ; sudo apt upgrade -y"
		
		# Prepare seed VM
		echo_blue_bold "Install cloud-init VMWareGuestInfo datasource"

		ssh -t "${SEED_USER}@${IPADDR}" <<EOF
		sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/' /etc/default/grub
		sudo update-grub
		sudo apt install jq socat conntrack net-tools traceroute nfs-common unzip -y
		sudo snap install yq
		sudo sh -c 'echo datasource_list: [ NoCloud, VMware, OVF ] > /etc/cloud/cloud.cfg.d/99-VMWare-Only.cfg'
		sudo cloud-init clean
		exit
EOF
		echo_blue_bold "Cloud-init done, poweroff"

		# Shutdown the guest
		vmrest_poweroff "${SEEDIMAGE_UUID}" "soft" > /dev/null

		echo_blue_bold "Wait ${SEED_IMAGE} to shutdown"
		while [ $(vmrest_power_state "${SEEDIMAGE_UUID}") == "poweredOn" ]
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

case "${KUBERNETES_DISTRO}" in
	k3s|rke2)
		CREDENTIALS_CONFIG=/var/lib/rancher/credentialprovider/config.yaml
		CREDENTIALS_BIN=/var/lib/rancher/credentialprovider/bin
		;;
	kubeadm)
		CREDENTIALS_CONFIG=/etc/kubernetes/credential.yaml
		CREDENTIALS_BIN=/usr/local/bin
		;;
esac

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | tr '.' ' ' | awk '{ print $2 }')
CRIO_VERSION=$(echo -n ${KUBERNETES_VERSION} | tr -d 'v' | tr '.' ' ' | awk '{ print $1"."$2 }')

echo_blue_bold "Prepare ${TARGET_IMAGE} image with cri-o version: ${CRIO_VERSION} and kubernetes: ${KUBERNETES_VERSION}"

cat > "${CACHE}/user-data" <<EOF
#cloud-config
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

cat > "${CACHE}/prepare-image.sh" << EOF
#!/bin/bash
SEED_ARCH=${SEED_ARCH}
CNI_PLUGIN=${CNI_PLUGIN}
CNI_VERSION=${CNI_VERSION}
KUBERNETES_VERSION=${KUBERNETES_VERSION}
KUBERNETES_MINOR_RELEASE=${KUBERNETES_MINOR_RELEASE}
CRIO_VERSION=${CRIO_VERSION}
CONTAINER_ENGINE=${CONTAINER_ENGINE}
CONTAINER_CTL=${CONTAINER_CTL}
KUBERNETES_DISTRO=${KUBERNETES_DISTRO}
CREDENTIALS_CONFIG=${CREDENTIALS_CONFIG}
CREDENTIALS_BIN=${CREDENTIALS_BIN}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
EOF

cat ${CURDIR}/prepare-image.sh >> "${CACHE}/prepare-image.sh"

chmod +x "${CACHE}/prepare-image.sh"

gzip -c9 < "${CACHE}/meta-data" | base64 -w 0 > ${CACHE}/metadata.base64
gzip -c9 < "${CACHE}/user-data" | base64 -w 0 > ${CACHE}/userdata.base64
gzip -c9 < "${CACHE}/vendor-data" | base64 -w 0 > ${CACHE}/vendordata.base64

TARGET_IMAGE_UUID=$(vmrest_create ${SEEDIMAGE_UUID} \
	2 \
	2048 \
	${TARGET_IMAGE} \
	0 \
	"${CACHE}/metadata.base64" \
	"${CACHE}/userdata.base64" \
	"${CACHE}/vendordata.base64" \
	true \
	false)

if [ -z "${TARGET_IMAGE_UUID}" ] || [ "${TARGET_IMAGE_UUID}" == "ERROR" ]; then
	echo_red_bold "Unable to clone ${SEED_IMAGE} to ${TARGET_IMAGE}"
	rm -rf "${VMREST_FOLDER}/${TARGET_IMAGE}"
	exit 1
fi

if [ -n "${SECOND_NETWORK_NAME}" ]; then
	echo_blue_bold "Add second network card ${SECOND_NETWORK_NAME} on ${TARGET_IMAGE}"

	vmrest_network_add ${TARGET_IMAGE_UUID} ${SECOND_NETWORK_NAME} > /dev/null
fi

echo_blue_bold "Power On ${TARGET_IMAGE}"
vmrest_poweron ${TARGET_IMAGE_UUID} > /dev/null

echo_blue_bold "Wait for IP from ${TARGET_IMAGE}"
IPADDR=$(vmrest_waitip ${TARGET_IMAGE_UUID})

echo_blue_bold "Wait ssh ready on ${IPADDR}"
wait_ssh_ready ${SEED_USER}@${IPADDR}

scp ${SCP_OPTIONS} "${CACHE}/prepare-image.sh" "${SEED_USER}@${IPADDR}:~"

ssh -t "${SEED_USER}@${IPADDR}" sudo ./prepare-image.sh

vmrest_poweroff "${TARGET_IMAGE_UUID}" "soft" > /dev/null

echo_blue_dot_title "Wait ${TARGET_IMAGE} to shutdown"
while [ $(vmrest_power_state ${TARGET_IMAGE_UUID}) == "poweredOn" ]
do
	echo_blue_dot
	sleep 1
done
echo

echo_blue_bold "Created image ${TARGET_IMAGE} with kubernetes version ${KUBERNETES_VERSION}"

exit 0
