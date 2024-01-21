#!/bin/bash

set -eu

FORCE=NO
INSTANCE_IMAGE=t3a.small
SEED_IMAGE=
TARGET_IMAGE=
SUBNET_ID=
SECURITY_GROUPID=
MASTER_USE_PUBLICIP=true

OPTIONS=(
	"force"
	"profile:"
	"region:"
	"custom-image:"
	"cni-version:"
	"cni-plugin:"
	"user:"
	"kubernetes-version:"
	"ami:"
	"arch:"
	"ecr-password:"
	"ssh-key-name:"
	"ssh-key-file:"
	"subnet-id:"
	"sg-id:"
	"use-public-ip:"
	"k8s-distribution:"
	"container-runtime:"
	"aws-access-key:"
	"aws-secret-key:"
)

PARAMS=$(echo ${OPTIONS[*]} | tr ' ' ',')
TEMP=$(getopt -o fp:r:i:n:c:u: --long "${PARAMS}"  -n "$0" -- "$@")
v:
eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true ; do
	#echo "1:$1"
	case "$1" in
		-f|--force) FORCE=YES ; shift;;

		-p|--profile) AWS_PROFILE="${2}" ; shift 2;;
		-r|--region) AWS_REGION="${2}" ; shift 2;;
		-i|--custom-image) TARGET_IMAGE="$2" ; shift 2;;
		-n|--cni-version) CNI_VERSION=$2 ; shift 2;;
		-c|--cni-plugin) CNI_PLUGIN=$2 ; shift 2;;
		-u|--user) KUBERNETES_USER=$2 ; shift 2;;
		-v|--kubernetes-version) KUBERNETES_VERSION=$2 ; shift 2;;

		--ami) SEED_IMAGE=$2 ; shift 2;;
		--arch) SEED_ARCH=$2 ; shift 2;;
		--ecr-password) ECR_PASSWORD=$2 ; shift 2;;
		--ssh-key-name) SSH_KEYNAME=$2 ; shift 2;;
		--ssh-key-file) SSH_PUBLIC_KEY="${2}" ; shift 2;;
		--subnet-id) SUBNET_ID="${2}" ; shift 2;;
		--sg-id) SECURITY_GROUPID="${2}" ; shift 2;;
		--use-public-ip) MASTER_USE_PUBLICIP="${2}" ; shift 2;;
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

mkdir -p ${CACHE}

if [ -z "${SEED_IMAGE}" ]; then
	echo_red_bold "Seed image is not defined, exit"
	exit 1
fi

SOURCE_IMAGE_ID=$(aws ec2 describe-images --profile ${AWS_PROFILE} --region ${AWS_REGION} --image-ids "${SEED_IMAGE}" 2>/dev/null | jq -r '.Images[0].ImageId//""')

if [ -z "${SOURCE_IMAGE_ID}" ]; then
	echo_red_bold "Source ${SOURCE_IMAGE_ID} not found!"
	exit 1
fi

if [ -z "${SUBNET_ID}" ]; then
	echo_red_bold "Subnet to be used is not defined, exit"
	exit 1
fi

if [ -z "${SECURITY_GROUPID}" ]; then
	echo_red_bold "Security group to be used is not defined, exit"
	exit 1
fi

if [ -z "${TARGET_IMAGE}" ]; then
	ROOT_IMG_NAME=$(aws ec2 describe-images --image-ids ${SEED_IMAGE} | jq -r '.Images[0].Name//""' | gsed -E 's/.+ubuntu-(\w+)-.+/\1-k8s/')

	if [ "${ROOT_IMG_NAME}" = "-k8s" ]; then
		echo_red_bold "AMI: ${SEED_IMAGE} not found or not ubuntu, exit"
		exit
	fi

	TARGET_IMAGE="${ROOT_IMG_NAME}-cni-${CNI_PLUGIN}-${KUBERNETES_VERSION}-${CONTAINER_ENGINE}-${SEED_ARCH}"
fi

if [ "${SEED_ARCH}" == "amd64" ]; then
	INSTANCE_TYPE=t3a.small
elif [ "${SEED_ARCH}" == "arm64" ]; then
	INSTANCE_TYPE=t4g.small
else
	echo_red_bold "Unsupported architecture: ${SEED_ARCH}"
	exit -1
fi

TARGET_IMAGE_ID=$(aws ec2 describe-images --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=architecture,Values=x86_64" "Name=name,Values=${TARGET_IMAGE}" "Name=virtualization-type,Values=hvm" 2>/dev/null | jq -r '.Images[0].ImageId//""')
KEYEXISTS=$(aws ec2 describe-key-pairs --profile ${AWS_PROFILE} --region ${AWS_REGION} --key-names "${SSH_KEYNAME}" 2>/dev/null | jq  -r '.KeyPairs[].KeyName//""')

if [ -n "${TARGET_IMAGE_ID}" ]; then
	if [ ${FORCE} = NO ]; then
		echo_blue_bold "${TARGET_IMAGE} already exists!"
		exit 0
	fi
	aws ec2 deregister-image --profile ${AWS_PROFILE} --region ${AWS_REGION} --image-id "${TARGET_IMAGE_ID}" &>/dev/null
fi

if [ -z ${KEYEXISTS} ]; then
	echo_red_bold "SSH Public key doesn't exist"
	if [ -z ${SSH_PUBLIC_KEY} ]; then
		echo_red_bold "${SSH_PUBLIC_KEY} doesn't exists. FATAL"
		exit -1
	fi
	aws ec2 import-key-pair --profile ${AWS_PROFILE} --region ${AWS_REGION} --key-name ${SSH_KEYNAME} --public-key-material "file://${SSH_PUBLIC_KEY}"
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

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | awk -F. '{ print $2 }')
CRIO_VERSION=$(echo -n ${KUBERNETES_VERSION} | tr -d 'v' | awk -F. '{ print $1"."$2 }')

echo_blue_bold "Prepare ${TARGET_IMAGE} image with cri-o version: ${CRIO_VERSION} and kubernetes: ${KUBERNETES_VERSION}"

cat > ${CACHE}/mapping.json <<EOF
[
	{
		"DeviceName": "/dev/sda1",
		"Ebs": {
			"DeleteOnTermination": true,
			"VolumeType": "gp3",
			"VolumeSize": 10,
			"Encrypted": false
		}
	}
]
EOF

cat > "${CACHE}/prepare-image.sh" << EOF
#!/bin/bash
SEED_ARCH=${SEED_ARCH}
CNI_PLUGIN=${CNI_PLUGIN}
CNI_VERSION=${CNI_VERSION}
KUBERNETES_VERSION=${KUBERNETES_VERSION}
KUBERNETES_MINOR_RELEASE=${KUBERNETES_MINOR_RELEASE}
ECR_PASSWORD=${ECR_PASSWORD}
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

if [ "${MASTER_USE_PUBLICIP}" == "true" ]; then
	PUBLIC_IP_OPTIONS=--associate-public-ip-address
else
	PUBLIC_IP_OPTIONS=--no-associate-public-ip-address
fi

echo_blue_bold "Launch instance ${SEED_IMAGE} to ${TARGET_IMAGE}"
LAUNCHED_INSTANCE=$(aws ec2 run-instances \
	--profile ${AWS_PROFILE} \
	--region ${AWS_REGION} \
	--image-id ${SEED_IMAGE} \
	--count 1  \
	--instance-type ${INSTANCE_TYPE} \
	--key-name ${SSH_KEYNAME} \
	--subnet-id ${SUBNET_ID} \
	--security-group-ids ${SECURITY_GROUPID} \
	--block-device-mappings "file://${CACHE}/mapping.json" \
	--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TARGET_IMAGE}}]" \
	${PUBLIC_IP_OPTIONS})

LAUNCHED_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.Instances[0].InstanceId//""')

if [ -z ${LAUNCHED_ID} ]; then
	echo_red_bold "Something goes wrong when launching ${TARGET_IMAGE}"
	exit -1
fi

echo_blue_dot_title "Wait for ${TARGET_IMAGE} instanceID ${LAUNCHED_ID} to boot"

while [ ! "$(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids ${LAUNCHED_ID} | jq .Reservations[0].Instances[0].State.Code)" -eq 16 ];
do
	echo_blue_dot
	sleep 1
done

echo

LAUNCHED_INSTANCE=$(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids ${LAUNCHED_ID} | jq .Reservations[0].Instances[0])

if [ "${MASTER_USE_PUBLICIP}" == "true" ]; then
	export IPADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PublicIpAddress//""')
	IP_TYPE="public"
else
	export IPADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateIpAddress//""')
	IP_TYPE="private"
fi

echo_blue_dot_title "Wait for ${TARGET_IMAGE} ssh ready for on ${IP_TYPE} IP=${IPADDR}"

while :
do
	echo_blue_dot
	scp ${SSH_OPTIONS} -o ConnectTimeout=1 "${CACHE}/prepare-image.sh" "${SEED_USER}@${IPADDR}":~ 2>/dev/null && break
	sleep 1
done

echo

ssh ${SSH_OPTIONS} -t "${SEED_USER}@${IPADDR}" sudo ./prepare-image.sh
ssh ${SSH_OPTIONS} -t "${SEED_USER}@${IPADDR}" rm ./prepare-image.sh

aws ec2 stop-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${LAUNCHED_ID}" &> /dev/null

echo_blue_dot_title "Wait ${TARGET_IMAGE} to shutdown"

while [ ! $(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${LAUNCHED_ID}" | jq .Reservations[0].Instances[0].State.Code) -eq 80 ];
do
	echo_blue_dot
	sleep 1
done
echo


echo_blue_bold "Created image ${TARGET_IMAGE} with kubernetes version ${KUBERNETES_VERSION}"

IMAGEID=$(aws ec2 create-image --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-id "${LAUNCHED_ID}" --name "${TARGET_IMAGE}" --description "Kubernetes ${KUBERNETES_VERSION} image ready to use, based on AMI ${SEED_IMAGE}" | jq -r '.ImageId//""')

if [ -z ${IMAGEID} ]; then
	echo_red_bold "Something goes wrong when creating image from ${TARGET_IMAGE}"
	exit -1
fi

echo_blue_dot_title "Wait AMI ${IMAGEID} to be available"
while [ ! $(aws ec2 describe-images --profile ${AWS_PROFILE} --region ${AWS_REGION} --image-ids "${IMAGEID}" | jq .Images[0].State | tr -d '"') == "available" ];
do
	echo_blue_dot
	sleep 5
done
echo

aws ec2 terminate-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${LAUNCHED_ID}" &>/dev/null

exit 0
