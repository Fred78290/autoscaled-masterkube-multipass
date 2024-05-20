#!/bin/bash

export CURDIR=$(dirname $0)
export OUTPUT=${CURDIR}/../config/deploy.log
export TIMEFORMAT='It takes %R seconds to complete this task...'
export TRACE=${TRACE:=NO}
export ARGS=()

OPTIONS=(
	"arch:"
	"autoscale-machine:"
	"cert-email:"
	"cloudprovider:"
	"cni-plugin:"
	"cni-version:"
	"configuration-location:"
	"container-runtime:"
	"control-plane-machine:"
	"cores-total:"
	"create-external-etcd"
	"create-image-only"
	"create-nginx-apigateway"
	"dashboard-hostname:"
	"defs:"
	"delete"
	"distribution:"
	"external-dns-provider:"
	"godaddy-key:"
	"godaddy-secret:"
	"ha-cluster"
	"help"
	"kube-engine:"
	"kube-password:"
	"kube-user:"
	"kube-version:"
	"max-autoprovisioned-node-group-count:"
	"max-node-provision-time:"
	"max-nodes-total:"
	"max-pods:"
	"memory-total:"
	"nginx-machine:"
	"node-group:"
	"public-domain:"
	"resume"
	"route53-access-key:"
	"route53-secret-key:"
	"route53-zone-id:"
	"scale-down-delay-after-add:"
	"scale-down-delay-after-delete:"
	"scale-down-delay-after-failure:"
	"scale-down-enabled:"
	"scale-down-gpu-utilization-threshold:"
	"scale-down-unneeded-time:"
	"scale-down-unready-time:"
	"scale-down-utilization-threshold:"
	"seed-image:"
	"ssh-private-key:"
	"ssl-location:"
	"trace"
	"transport:"
	"unremovable-node-recheck-timeout:"
	"upgrade"
	"use-cloud-init"
	"use-self-signed-ca"
	"use-zerossl"
	"verbose"
	"worker-node-machine:"
	"worker-nodes:"
	"zerossl-eab-hmac-secret:"
	"zerossl-eab-kid:"
)

echo -n > ${OUTPUT}

echo "==================================================================================" | tee -a ${OUTPUT}
echo "Start at: " $(date) | tee -a ${OUTPUT}
echo "==================================================================================" | tee -a ${OUTPUT}
echo | tee -a ${OUTPUT}

time {
	pushd ${CURDIR}/../ &>/dev/null

	export PATH=${PWD}/bin:${PATH}

	while true; do
		ARG=$1

		if [ -z "${ARG}" ]; then
			break
		elif [[ "${ARG}" = --trace ]] || [[ "${ARG}" = -x ]]; then
			ARGS+=("${ARG}" )
			TRACE=YES
			shift
		elif [[ "${ARG}" = --plateform* ]] || [[ "${ARG}" = -p* ]]; then
			export PLATEFORM=
			IFS== read IGNORE PLATEFORM <<<"${ARG}"

			if [ -z "${PLATEFORM}" ]; then
				shift
				PLATEFORM=$1
			fi

		elif [[ "${ARG}" =~ --[\w]* ]] || [[ "${ARG}" = -[\w* ]]; then
			IFS== read ARGUMENT VALUE <<<"${ARG}"
			if [ -n "${VALUE}" ]; then
				if [[ "${VALUE}" = *" "* ]]; then
					ARGS+=("${ARGUMENT}=\"${VALUE}\"")
				else
					ARGS+=("${ARGUMENT}=${VALUE}")
				fi
			else
				ARGS+=("${ARG}" )
			fi

		elif [[ "${ARG}" = *" "* ]]; then
			ARGS+=("\"${ARG}\"")
		else
			ARGS+=("${ARG}")
		fi

		shift
	done

	eval set -- "${ARGS[@]}"

	if [ "${TRACE}" == "YES" ]; then
		set -x
	fi

	if [ -n "${PLATEFORM}" ]; then
		source "${CURDIR}/common.sh"
		source "${CURDIR}/create-vm.sh"
		source "${CURDIR}/create-deployment.sh"
	else
		echo "PLATEFORM not defined, exit"
	fi

	popd &>/dev/null

} 2>&1 | tee -a ${OUTPUT}

echo "==================================================================================" | tee -a ${OUTPUT}
echo "= End at: " $(date) | tee -a ${OUTPUT}
echo "==================================================================================" | tee -a ${OUTPUT}
