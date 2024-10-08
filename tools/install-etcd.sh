#!/bin/bash
CLUSTER_NODES=()
NODE_INDEX=
ETCD_VER=v3.5.12
GOOGLE_URL=https://storage.googleapis.com/etcd
GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
DOWNLOAD_URL=${GOOGLE_URL}
ARCH=amd64

if [ "$(uname -p)" == "aarch64" ];  then
	ARCH="arm64"
fi

OPTIONS=(
	"cluster-nodes:"
	"node-index:"
	"user:"
)
PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o u:c:n: --long "${PARAMS}" -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true; do
	case "$1" in
	-c|--cluster-nodes)
		IFS=, read -a CLUSTER_NODES <<< "$2"
		shift 2
		;;

	-n|--node-index)
		NODE_INDEX="$2"
		shift 2
		;;

	-u | --user)
		USER=$2
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

for CLUSTER_NODE in ${CLUSTER_NODES[@]}
do
	IFS=: read HOST IP <<< "${CLUSTER_NODE}"

	sed -i "/${HOST}/d" /etc/hosts
	echo "${IP}   ${HOST} ${HOST%%.*}" >> /etc/hosts
done

mkdir -p /etc/etcd
mkdir -p /var/lib/etcd

cp -R /home/${USER}/etcd/ssl /etc/etcd/ssl
cp /home/${USER}/etcd/etcd-0${NODE_INDEX}.service /etc/systemd/system/etcd.service

curl -sL ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-${ARCH}.tar.gz | tar zx

cp etcd-${ETCD_VER}-linux-${ARCH}/etcd* /usr/local/bin/
cp etcd-${ETCD_VER}-linux-${ARCH}/etcdutl /usr/local/bin/
cp etcd-${ETCD_VER}-linux-${ARCH}/etcdctl /usr/local/bin/

rm -rf etcd-${ETCD_VER}-linux-${ARCH}.tar.gz etcd-${ETCD_VER}-linux-${ARCH}

systemctl daemon-reload
systemctl enable etcd

if [ ${NODE_INDEX} -eq 3 ]; then
	systemctl start etcd
else
	systemctl start etcd --no-block
fi
