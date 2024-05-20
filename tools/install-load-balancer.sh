#!/bin/bash

set -e

CONTROL_PLANE_ENDPOINT=
CLUSTER_NODES=()
PRIVATE_IP=0.0.0.0
LOAD_BALANCER_PORT=80,443,6443

OPTIONS=(
	"cluster-nodes:"
	"control-plane-endpoint:"
	"listen-ip:"
	"listen-port:"
)
PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o l:c:p:n: --long "${PARAMS}" -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true; do
	case "$1" in
	-c | --control-plane-endpoint)
		CONTROL_PLANE_ENDPOINT="$2"
		shift 2
		;;
	-p | --listen-port)
		LOAD_BALANCER_PORT=$2
		shift 2
		;;
	-n | --cluster-nodes)
		IFS=, read -a CLUSTER_NODES <<< "$2"
		shift 2
		;;
	-l | --listen-ip)
		PRIVATE_IP="$2"
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

echo "127.0.0.1 ${CONTROL_PLANE_ENDPOINT}" >> /etc/hosts

for CLUSTER_NODE in ${CLUSTER_NODES[@]}
do
	IFS=: read HOST IP <<< "${CLUSTER_NODE}"

	echo "${IP}   ${HOST}" >> /etc/hosts
done

apt install nginx -y || echo "Need to reconfigure NGINX"

# Remove http default listening
rm -rf /etc/nginx/sites-enabled/*

if [ -z "$(grep tcpconf /etc/nginx/nginx.conf)" ]; then
	echo "include /etc/nginx/tcpconf.conf;" >> /etc/nginx/nginx.conf
fi

cat > /etc/nginx/tcpconf.conf <<EOF
stream {
	include /etc/nginx/tcpconf.d/*.conf;
}
EOF

mkdir -p /etc/nginx/tcpconf.d

function create_tcp_stream() {
	local STREAM_NAME=$1
	local TCP_PORT=$2
	local NGINX_CONF=$3

	TCP_PORT=$(echo -n ${TCP_PORT} | tr ',' ' ')

	touch ${NGINX_CONF}

	for PORT in ${TCP_PORT}
	do
		echo "  upstream ${STREAM_NAME}_${PORT} {" >> ${NGINX_CONF}
		echo "    least_conn;" >> ${NGINX_CONF}

		for CLUSTER_NODE in ${CLUSTER_NODES[@]}
		do
			IFS=: read HOST IP <<< "${CLUSTER_NODE}"

			if [ -n ${HOST} ]; then
				echo "    server ${IP}:${PORT} max_fails=3 fail_timeout=30s;" >> ${NGINX_CONF}
			fi
		done

		echo "  }" >> ${NGINX_CONF}

		echo "  server {" >> ${NGINX_CONF}
		echo "    listen ${PRIVATE_IP}:${PORT};" >> ${NGINX_CONF}
		echo "    proxy_pass ${STREAM_NAME}_${PORT};" >> ${NGINX_CONF}
		echo "  }" >> ${NGINX_CONF}
	done
}

create_tcp_stream tcp_lb ${LOAD_BALANCER_PORT} /etc/nginx/tcpconf.d/listen.conf

apt install --fix-broken

systemctl restart nginx

if [ -f /etc/systemd/system/kubelet.service ]; then
	systemctl disable kubelet
fi