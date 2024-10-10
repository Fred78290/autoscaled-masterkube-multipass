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

apt update -y
apt install nginx -y || echo "Need to reconfigure NGINX"

UBUNTU_VERSION_ID=$(cat /etc/os-release | grep VERSION_ID | tr -d '"' | cut -d '=' -f 2)
IFS=. read UBUNTU_VERSION_MAJOR UBUNTU_VERSION_MINOR <<< "${UBUNTU_VERSION_ID}"

if [ ${UBUNTU_VERSION_MAJOR} -gt 22 ]; then
	apt install libnginx-mod-stream -y
fi

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
	local STREAM_NAME="$1"
	local LISTEN_ADDR="$2"
	local TCP_PORT="$3"
	local NGINX_CONF="$4"

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
		echo "    listen ${LISTEN_ADDR}:${PORT};" >> ${NGINX_CONF}
		echo "    proxy_pass ${STREAM_NAME}_${PORT};" >> ${NGINX_CONF}
		echo "  }" >> ${NGINX_CONF}
	done
}

# Remove 80 & 443 port"
IFS=, read -a PORTS <<< "${LOAD_BALANCER_PORT}"
LOAD_BALANCER_PORT=()

for PORT in ${PORTS[@]}
do
	if [ ${PORT} -ne "80" ] && [ ${PORT} -ne "443" ]; then
		LOAD_BALANCER_PORT+=(${PORT})
	fi
done

create_tcp_stream tcp_public_lb "0.0.0.0" "80 443" /etc/nginx/tcpconf.d/listen.conf
create_tcp_stream tcp_private_lb "${PRIVATE_IP}" "${LOAD_BALANCER_PORT[@]}" /etc/nginx/tcpconf.d/listen.conf

apt install --fix-broken

systemctl restart nginx

if [ -f /etc/systemd/system/kubelet.service ]; then
	systemctl disable kubelet
fi

cat > /etc/sysctl.d/99-nginx.conf <<EOF
net.ipv4.ip_forward=0
net.ipv6.conf.all.forwarding=0

###################################################################
# Additional settings - these settings can improve the network
# security of the host and prevent against some network attacks
# including spoofing attacks and man in the middle attacks through
# redirection. Some network environments, however, require that these
# settings are disabled so review and enable them as needed.
#
# Do not accept ICMP redirects (prevent MITM attacks)
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
# _or_
# Accept ICMP redirects only for gateways listed in our default
# gateway list (enabled by default)
net.ipv4.conf.all.secure_redirects = 1
#
# Do not send ICMP redirects (we are not a router)
net.ipv4.conf.all.send_redirects = 0
#
# Do not accept IP source route packets (we are not a router)
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
#
# Log Martian Packets
#net.ipv4.conf.all.log_martians = 1
#
EOF

sysctl --load=/etc/sysctl.d/99-nginx.conf