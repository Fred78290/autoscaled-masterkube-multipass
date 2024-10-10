#!/bin/bash
ZONE_NAMES=()
NET_INF=$(ip route get 1|awk '{print $5;exit}')
ADVERTISE_ADDRESS=$(ip addr show ${NET_INF} | grep "inet\s" | tr '/' ' ' | awk '{print $2}')
MASTER_DNS=$(resolvectl dns ${NET_INF} | cut -d ' ' -f 4)
USER=ubuntu

OPTIONS=(
	"user:"
	"master-dns:"
	"zone-name:"
)
PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o m:u:z: --long "${PARAMS}" -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true; do
	case "$1" in
	-m|--master-dns)
		MASTER_DNS=$2
		shift 2
		;;
	-u|--user)
		USER=$2
		shift 2
		;;
	-z|--zone-name)
		ZONE_NAME=$2
		if [[ ! ${ZONE_NAMES[@]} =~ "${ZONE_NAME}" ]]; then
			if [ "${ZONE_NAME: -1}" != '.' ]; then
				ZONE_NAME="${ZONE_NAME}."
			fi

			ZONE_NAMES+=("${ZONE_NAME}")
		fi
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

apt update -y
apt install resolvconf bind9 -y

cat > /etc/bind/named.conf.options <<EOF
include "/etc/bind/rndc.key";

acl internals {
	// lo adapter 
	127.0.0.1;
	// CIDR for your local networks
	172.16.0.0/16;
	192.168.0.0/16;
	10.0.0.0/8;
};

options {
	directory "/var/cache/bind";

	allow-new-zones yes;
	request-ixfr no;

	recursion yes;
//	allow-recursion {
//		internals;
//	};

	forwarders {
		${MASTER_DNS};
	};

	dnssec-validation auto;

	listen-on-v6 {
		none;
	};

	listen-on {
		0.0.0.0/0;
	};
};

controls {
  inet * port 953 allow { "internals"; } keys { "rndc-key"; };
};
EOF

chown root:bind /etc/bind/named.conf.options

for ZONE_NAME in ${ZONE_NAMES[@]}
do
	ZONE_NAME=${ZONE_NAME::-1}
	ZONE_FILE=/var/lib/bind/${ZONE_NAME}

	if [ ! -f ${ZONE_FILE} ]; then
		cat >>  /etc/bind/named.conf.local <<EOF

zone "${ZONE_NAME}" {
    type master;

    file "${ZONE_FILE}";

    allow-transfer {
        key "rndc-key";
    };

    update-policy {
        grant "rndc-key" zonesub ANY;
    };
};
EOF

		cat > ${ZONE_FILE} <<EOF
\$TTL 60
@                       IN SOA  ns.${ZONE_NAME}. master@${ZONE_NAME}. (
                                16         ; serial
                                60         ; refresh (1 minute)
                                60         ; retry (1 minute)
                                60         ; expire (1 minute)
                                60         ; minimum (1 minute)
                                )
;
                        NS      ns.${ZONE_NAME}.
ns      IN      A       ${ADVERTISE_ADDRESS}
EOF
	fi

	chown bind:bind ${ZONE_FILE}
done

mkdir /etc/systemd/resolved.conf.d/
cat > /etc/systemd/resolved.conf.d/resolv.conf <<EOF
[Resolve]
DNS=${ADVERTISE_ADDRESS}
FallbackDNS=${MASTER_DNS}
Domains=${ZONE_NAME[@]}
EOF

systemctl enable named
systemctl restart named

systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service

cp /etc/bind/rndc.key /home/${USER}
chmod 644 /home/${USER}/rndc.key