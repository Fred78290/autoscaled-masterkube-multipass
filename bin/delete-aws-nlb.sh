#!/bin/bash
set -e

CURDIR=$(dirname $0)

source "${CURDIR}/common.sh"

AWS_NLB_NAME=${MASTERKUBE}
AWS_PROFILE=
AWS_REGION=

TEMP=`getopt -o n:p:r: --long name:,profile:,region: -n "$0" -- "$@"`
eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true ; do
	#echo "1:$1"
	case "$1" in
		--name)
			AWS_NLB_NAME="$2"
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

if [ -z ${AWS_NLB_NAME} ]; then
	echo_red "subnet is not defined"
	exit -1
fi

function delete_nlb() {
	local NLB_NAME=$1
	local NLB_ARN=$(aws elbv2 describe-load-balancers --profile=${AWS_PROFILE} --region=${AWS_REGION} --names ${NLB_NAME} 2> /dev/null | jq -r '.LoadBalancers[0].LoadBalancerArn // ""')

	if [ "x${NLB_ARN}" != "x" ]; then
		NLB_LISTENERS=$(aws elbv2 describe-listeners --profile=${AWS_PROFILE} --region=${AWS_REGION} --load-balancer-arn ${NLB_ARN} | jq -r '.Listeners[].ListenerArn // ""')

		for NLB_LISTENER in ${NLB_LISTENERS}
		do
			NLB_TARGETGROUPS=$(aws elbv2 describe-listeners --profile=${AWS_PROFILE} --region=${AWS_REGION} --listener-arns ${NLB_LISTENER} | jq -r '.Listeners[]|.DefaultActions[]|.TargetGroupArn // ""')
		
			aws elbv2 delete-listener --profile=${AWS_PROFILE} --region=${AWS_REGION} --listener-arn ${NLB_LISTENER}

			for NLB_TARGETGROUP in ${NLB_TARGETGROUPS}
			do
				aws elbv2 delete-target-group --profile=${AWS_PROFILE} --region=${AWS_REGION} --target-group-arn ${NLB_TARGETGROUP}
			done
		done

		aws elbv2 delete-load-balancer --profile=${AWS_PROFILE} --region=${AWS_REGION} --load-balancer-arn ${NLB_ARN}
	fi
}

delete_nlb "p-${AWS_NLB_NAME}"
delete_nlb "c-${AWS_NLB_NAME}"