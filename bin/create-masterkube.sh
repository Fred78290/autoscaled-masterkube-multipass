#!/bin/bash

export CURDIR=$(dirname $0)
export OUTPUT=${CURDIR}/../config/deploy.log
export TIMEFORMAT='It takes %R seconds to complete this task...'
export ARGS=()
export PLATEFORM=

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
			IFS== read IGNORE PLATEFORM <<<"${ARG}"
			shift

			if [ -z "${PLATEFORM}" ]; then
				PLATEFORM=$1
				shift
			fi
		else
			ARGS+=("${ARG}")
			shift
		fi
	done

	if [ -n "${PLATEFORM}" ]; then
		exec "${CURDIR}/plateform/${PLATEFORM}/create.sh" ${ARGS[@]}
	else
		echo "PLATEFORM not defined, exit"
	fi

	popd &>/dev/null

} 2>&1 | tee -a ${OUTPUT}

echo "==================================================================================" | tee -a ${OUTPUT}
echo "= End at: " $(date) | tee -a ${OUTPUT}
echo "==================================================================================" | tee -a ${OUTPUT}
