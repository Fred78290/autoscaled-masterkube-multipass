#!/bin/bash

export CURDIR=$(dirname $0)
export OUTPUT=${CURDIR}/../config/deploy.log
export TIMEFORMAT='It takes %R seconds to complete this task...'
export ARGS=()

OPTIONS=(
	"help"
	"distribution:"
	"upgrade"
	"verbose"
	"trace"
	"resume"
	"delete"
	"configuration-location:"
	"ssl-location:"
	"cert-email:"
	"use-zerossl"
	"use-self-signed-ca"
	"zerossl-eab-kid:"
	"zerossl-eab-hmac-secret:"
	"godaddy-key:"
	"godaddy-secret:"
	"route53-zone-id:"
	"route53-access-key:"
	"route53-secret-key:"
	"dashboard-hostname:"
	"public-domain:"
	"defs:"
	"create-image-only"
	"max-pods:"
	"k8s-distribution:"
	"ha-cluster"
	"create-external-etcd"
	"node-group:"
	"container-runtime:"
	"target-image:"
	"arch:"
	"seed-image:"
	"nginx-machine:"
	"control-plane-machine:"
	"worker-node-machine:"
	"autoscale-machine:"
	"ssh-private-key:"
	"cni-plugin:"
	"cni-version:"
	"transport:"
	"kubernetes-version:"
	"kubernetes-user:"
	"kubernetes-password:"
	"worker-nodes:"
	"cloudprovider:"
	"max-nodes-total:"
	"cores-total:"
	"memory-total:"
	"max-autoprovisioned-node-group-count:"
	"scale-down-enabled:"
	"scale-down-delay-after-add:"
	"scale-down-delay-after-delete:"
	"scale-down-delay-after-failure:"
	"scale-down-unneeded-time:"
	"scale-down-unready-time:"
	"unremovable-node-recheck-timeout:"
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

	if [ -n "${PLATEFORM}" ]; then
		source ${CURDIR}/common.sh
		source "${CURDIR}/plateform/${PLATEFORM}/create.sh"
	else
		echo "PLATEFORM not defined, exit"
	fi

	popd &>/dev/null

} 2>&1 | tee -a ${OUTPUT}

echo "==================================================================================" | tee -a ${OUTPUT}
echo "= End at: " $(date) | tee -a ${OUTPUT}
echo "==================================================================================" | tee -a ${OUTPUT}
