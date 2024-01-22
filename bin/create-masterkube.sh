#!/bin/bash

export CURDIR=$(dirname $0)
export OUTPUT=${CURDIR}/../config/deploy.log
export TIMEFORMAT='It takes %R seconds to complete this task...'
export ARGS=()

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
