#!/bin/bash

export CURDIR=$(dirname $0)

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
	exec "${CURDIR}/plateform/${PLATEFORM}/image.sh" ${ARGS[@]}
else
	echo "PLATEFORM not defined, exit"
	exit 1
fi
