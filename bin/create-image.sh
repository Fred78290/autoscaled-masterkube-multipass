#!/bin/bash

export CURDIR=$(dirname $0)
export TRACE=${TRACE:=NO}

while true; do
	ARG=$1

	if [ -z "${ARG}" ]; then
		break
	elif [[ "${ARG}" = --trace ]] || [[ "${ARG}" = -x ]]; then
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
		ARGS+=("${ARG}'")
	fi

	shift
done

eval set -- "${ARGS[@]}"

if [ ${TRACE} == "YES" ]; then
	set -x
fi

if [ -n "${PLATEFORM}" ]; then
	source "${CURDIR}/common.sh"
	source "${CURDIR}/plateform/${PLATEFORM}/image.sh"
else
	echo "PLATEFORM not defined, exit"
	exit 1
fi
