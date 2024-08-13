#!/bin/bash
set -eu

CURDIR=$(dirname $0)

source "${CURDIR}/echo.sh"

AWS_PROFILE=
AWS_REGION=
AWS_VPCID=
AWS_PRIVATE_SUBNETID=()
AWS_PUBLIC_SUBNETID=()
AWS_SECURITY_GROUP=
AWS_CERT_ARN=
LOAD_BALANCER_PORT=(80 443 6443)
AWS_NLB_NAME=
AWS_USE_PUBLICIP=false
PUBLIC_INSTANCES_ID=
CONTROLPLANE_INSTANCES_ID=
CROSS_ZONE=false
CONTROL_PLANE_PUBLIC=false

OPTIONS=(
	"cert-arn:"
	"control-plane-public:"
	"controlplane-instances-id:"
	"expose-public:"
	"cross-zone:"
	"name:"
	"private-subnet-id:"
	"profile:"
	"public-instances-id:"
	"public-subnet-id:"
	"region:"
	"security-group:"
	"target-port:"
	"target-vpc-id:"
	"trace"
)
PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=`getopt -o n:p:r:s:x --long "${PARAMS}" -n "$0" -- "$@"`

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true ; do
	#echo "1:$1"
	case "$1" in
		-x|--trace)
			set -x
			shift 1
			;;
		--name)
			AWS_NLB_NAME="$2"
			shift 2
			;;
		--cross-zone)
			CROSS_ZONE=$2
			shift 2
			;;
		--expose-public)
			AWS_USE_PUBLICIP="$2"
			shift 2
			;;
		--control-plane-public)
			CONTROL_PLANE_PUBLIC="$2"
			shift 2
			;;
		--profile)
			AWS_PROFILE="$2"
			shift 2
			;;
		--region)
			AWS_REGION="$2"
			shift 2
			;;
		--cert-arn)
			AWS_CERT_ARN="$2"
			shift 2
			;;
		--security-group)
			AWS_SECURITY_GROUP="$2"
			shift 2
			;;
		--public-instances-id)
			IFS=, read -a PUBLIC_INSTANCES_ID <<< "$2"
			shift 2
			;;
		--controlplane-instances-id)
			IFS=, read -a CONTROLPLANE_INSTANCES_ID <<< "$2"
			shift 2
			;;
		--public-subnet-id)
			IFS=, read -a AWS_PUBLIC_SUBNETID <<< "$2"
			shift 2
			;;
		--private-subnet-id)
			IFS=, read -a AWS_PRIVATE_SUBNETID <<< "$2"
			shift 2
			;;
		--target-vpc-id)
			AWS_VPCID="$2"
			shift 2
			;;
		--target-port)
			IFS=, read -a LOAD_BALANCER_PORT <<< "$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo "$1 - Internal error!"
			exit 1
			;;
	esac
done

if [ -z "${AWS_NLB_NAME}" ]; then
	echo_red_bold "subnet is not defined"
	exit -1
fi

if [ ${#AWS_PUBLIC_SUBNETID[@]} -eq 0 ]; then
	echo_red_bold "public subnet is not defined"
	exit -1
fi

if [ ${#AWS_PRIVATE_SUBNETID[@]} -eq 0 ]; then
	echo_red_bold "private subnet is not defined"
	exit -1
fi

if [ -z "${AWS_SECURITY_GROUP}" ]; then
	echo_red_bold "security group is not defined"
	exit -1
fi

if [ -z "${AWS_CERT_ARN}" ]; then
	echo_red_bold "certificat arn is not defined"
	exit -1
fi

if [ ${#PUBLIC_INSTANCES_ID[@]} -eq 0 ]; then
	echo_red_bold "public instances is not defined"
	exit -1
fi

if [ ${#CONTROLPLANE_INSTANCES_ID[@]} -eq 0 ]; then
	echo_red_bold "controlplane instances is not defined"
	exit -1
fi

PUBLIC_INSTANCES_IP=
CONTROLPLANE_INSTANCES_IP=

# Extract IP
for INSTANCE in $(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids ${PUBLIC_INSTANCES_ID[@]} | jq '.Reservations[].Instances[].PrivateIpAddress')
do
	PUBLIC_INSTANCES_IP+=("Id=${INSTANCE}")
done

for INSTANCE in $(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids ${CONTROLPLANE_INSTANCES_ID[@]} | jq '.Reservations[].Instances[].PrivateIpAddress')
do
	CONTROLPLANE_INSTANCES_IP+=("Id=${INSTANCE}")
done

function create_nlb() {
	local NLB_NAME=$1
	local SCHEME=$2
	local AWS_SUBNETID=$3
	local TARGET_PORTS=$4
	local TYPE=$5
	local INSTANCES=$6
	local NLB_ARN=
	local TARGET_ARN=
	local TARGET_PORT=

	NLB_ARN=$(aws elbv2 create-load-balancer --profile=${AWS_PROFILE} --region=${AWS_REGION} --name ${NLB_NAME} \
		--security-groups ${AWS_SECURITY_GROUP} --scheme ${SCHEME} --type ${TYPE} --subnets ${AWS_SUBNETID} | jq -r '.LoadBalancers[0].LoadBalancerArn')

	SILENT=$(aws elbv2 modify-load-balancer-attributes --profile=${AWS_PROFILE} --region=${AWS_REGION} \
		--load-balancer-arn=${NLB_ARN} \
		--attributes \
		Key=load_balancing.cross_zone.enabled,Value=${CROSS_ZONE} \
		Key=dns_record.client_routing_policy,Value=availability_zone_affinity)

	for TARGET_PORT in ${TARGET_PORTS}
	do

		local CERTIFICAT_ARGS=
		local PROTOCOL=

		if [ ${TYPE} == "network" ]; then
			PROTOCOL=TCP
	   elif [ "${TARGET_PORT}" = "80" ]; then
			PROTOCOL=HTTP
		else
			PROTOCOL=HTTPS
			CERTIFICAT_ARGS="--certificates CertificateArn=${AWS_CERT_ARN}"
		fi

		TARGET_ARN=$(aws elbv2 create-target-group --profile=${AWS_PROFILE} --region=${AWS_REGION} \
			--name ${NLB_NAME::26}-${TARGET_PORT} \
			--protocol ${PROTOCOL} \
			--port ${TARGET_PORT} \
			--vpc-id ${AWS_VPCID} \
			--health-check-enabled \
			--health-check-protocol ${PROTOCOL} \
			--health-check-port ${TARGET_PORT} \
			--health-check-interval-seconds 10 \
			--healthy-threshold-count 2 \
			--unhealthy-threshold-count 2 \
			--target-type ip | jq -r '.TargetGroups[0].TargetGroupArn')

		aws elbv2 create-listener ${CERTIFICAT_ARGS} \
			--profile=${AWS_PROFILE} \
			--region=${AWS_REGION} \
			--load-balancer-arn ${NLB_ARN} \
			--protocol ${PROTOCOL} \
			--port ${TARGET_PORT} \
			--default-actions Type=forward,TargetGroupArn=${TARGET_ARN} > /dev/null

		aws elbv2 register-targets --profile=${AWS_PROFILE} --region=${AWS_REGION} \
			--target-group-arn ${TARGET_ARN} \
			--targets ${INSTANCES} > /dev/null
	done

	echo ${NLB_ARN}
}

if [ ${AWS_USE_PUBLICIP} = "true" ]; then
	if [ ${CONTROL_PLANE_PUBLIC} == "true" ]; then
		EXPOSED_PORTS="${LOAD_BALANCER_PORT[*]}"
	else
		EXPOSED_PORTS="80 443"
	fi

	NLB_ARN=$(create_nlb "p-${AWS_NLB_NAME}" internet-facing "${AWS_PUBLIC_SUBNETID[*]}" "${EXPOSED_PORTS}" network "${PUBLIC_INSTANCES_IP[*]}")
fi

if [ ${CONTROL_PLANE_PUBLIC} == "false" ]; then
	NLB_ARN=$(create_nlb "c-${AWS_NLB_NAME}" internal "${AWS_PRIVATE_SUBNETID[*]}" "${LOAD_BALANCER_PORT[*]}" network "${CONTROLPLANE_INSTANCES_IP[*]}")
fi

NBL_DESCRIBE=

echo_blue_dot_title "Wait NLB to start ${NLB_ARN}"

while [ "$(echo "${NBL_DESCRIBE}" | jq -r '.LoadBalancers[0].State.Code // ""')" != "active" ];
do
	echo_blue_dot
	sleep 5
	NBL_DESCRIBE=$(aws elbv2 describe-load-balancers --profile=${AWS_PROFILE} --region=${AWS_REGION} --load-balancer-arns ${NLB_ARN})
done

echo