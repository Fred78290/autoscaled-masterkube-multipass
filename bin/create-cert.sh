#!/bin/bash
CURDIR=$(dirname $0)

source ${CURDIR}/echo.sh

function usage() {
cat <<EOF
$0 create an autosigned certificat with own CA
Options are:
--help | -h                            # Display usage
--ca                                   # External certificat authority
--ca-key                               # External certificat authority private key
--ssl-location | -l                    # Where to store cert
--cert-email | -m                      # Email used in cert
--domain | -d                          # Domain used for cert
EOF
}

OPTIONS=(
	"ca-key:"
	"ca:"
	"cert-email:"
	"domain:"
	"help"
	"ssl-location:"
)
PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o hl:d:m: --long "${PARAMS}" -n "$0" -- "$@")

eval set -- "${TEMP}"

while true; do
	case "$1" in
	-h|--help)
		usage
		exit
		shift 1
		;;
	-l|--ssl-location)
		SSL_LOCATION=$2
		shift 2
		;;
	-m|--cert-email)
		CERT_EMAIL=$2
		shift 2
		;;
	-d|--domain)
		ACM_DOMAIN_NAME=$2
		shift 2
		;;
	--ca)
		EXTERNAL_CA=$2
		shift 2
		;;
	--ca-key)
		EXTERNAL_CA_KEY=$2
		shift 2
		;;
	--)
		shift
		break
		;;
	*)
		echo_red "$1 - Internal error!"
		usage
		exit 1
		;;
	esac
done

if [ -n "${EXTERNAL_CA}" ] && [ -n "${EXTERNAL_CA_KEY}" ]; then
	if [ ! -f "${EXTERNAL_CA}" ]; then
		echo_red_bold "${EXTERNAL_CA} not found, exit"
		exit 1
	fi

	if [ ! -f "${EXTERNAL_CA_KEY}" ]; then
		echo_red_bold "${EXTERNAL_CA_KEY} not found, exit"
		exit 1
	fi
fi

if [ -z "${SSL_LOCATION}" ]; then
	echo_red_bold "SSL_LOCATION is not defined, exit"
	exit 1
fi

if [ -z "${ACM_DOMAIN_NAME}" ]; then
	echo_red_bold "ACM_DOMAIN_NAME is not defined, exit"
	exit 1
fi

if [ -z "${CERT_EMAIL}" ]; then
	echo_red_bold "CERT_EMAIL is not defined, exit"
	exit 1
fi

mkdir -p ${SSL_LOCATION}/

WILDCARD="*.${ACM_DOMAIN_NAME}"

pushd ${SSL_LOCATION} &>/dev/null

if [ -z "${EXTERNAL_CA}" ] && [ -z "${EXTERNAL_CA_KEY}" ]; then
	cat > ca-csr.json <<EOF
{
  "CN": "${ACM_DOMAIN_NAME}",
  "key": {
	"algo": "rsa",
	"size": 2048
  },
  "names": [
	{
		"C": "US",
		"ST": "California",
		"L": "San Francisco",
		"O": "GitHub",
		"OU": "Fred78290",
		"emailAddress": "${CERT_EMAIL}"
	}
  ]
}
EOF

	CACERT=$(cfssl gencert -initca ca-csr.json)
	echo ${CACERT} | jq -r '.cert' > ca.pem
	echo ${CACERT} | jq -r '.csr' > ca.csr
	echo ${CACERT} | jq -r '.key' > ca.key

	EXTERNAL_CA=${PWD}/ca.pem
	EXTERNAL_CA_KEY=${PWD}/ca.key
fi

cat > ca-config.json <<EOF
{
  "signing": {
	"default": {
	  "expiry": "87600h"
	},
	"profiles": {
	  "${ACM_DOMAIN_NAME}": {
		"usages": [
			"signing",
			"key encipherment",
			"server auth",
			"client auth"
		],
		"expiry": "87600h"
	  }
	}
  }
}
EOF

cat > csr.json <<EOF
{
	"CN": "${ACM_DOMAIN_NAME}",
	"hosts": [
		"${WILDCARD}",
		"${ACM_DOMAIN_NAME}"
	],
	"key": {
		"algo": "rsa",
		"size": 2048
	},
	"names": [
		{
			"C": "US",
			"ST": "California",
			"L": "San Francisco",
			"O": "GitHub",
			"OU": "Fred78290",
			"emailAddress": "${CERT_EMAIL}"
		}
	]
}
EOF

CERT=$(cfssl gencert -ca=${EXTERNAL_CA} -ca-key=${EXTERNAL_CA_KEY} -config=ca-config.json -profile=${ACM_DOMAIN_NAME} csr.json)

echo ${CERT} | jq -r '.cert' > cert.pem
echo ${CERT} | jq -r '.csr' > cert.csr
echo ${CERT} | jq -r '.key' > privkey.pem

cat cert.pem ${EXTERNAL_CA} > chain.pem
cat cert.pem ${EXTERNAL_CA} privkey.pem > fullchain.pem
chmod 644 *

popd &>/dev/null