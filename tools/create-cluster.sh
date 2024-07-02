#!/bin/bash

set -e

APISERVER_ADVERTISE_PORT=6443
ARCH=$([[ "$(uname -m)" =~ arm64|aarch64 ]] && echo -n arm64 || echo -n amd64)
CERT_EXTRA_SANS=()
CERT_SANS=
CLOUD_PROVIDER=
CLUSTER_DIR=/etc/cluster
CLUSTER_DNS="10.96.0.10"
CLUSTER_NODES=()
CNI_PLUGIN=flannel
CONFIGURE_CLOUD_ROUTE=false
CONTAINER_CTL=unix:///var/run/dockershim.sock
CONTAINER_ENGINE=docker
CONTAINER_RUNTIME=docker
CONTROL_PLANE_ENDPOINT_ADDR=
CONTROL_PLANE_ENDPOINT_HOST=
CONTROL_PLANE_ENDPOINT=
ETCD_ENDPOINT=
EXTERNAL_ETCD=false
HA_CLUSTER=false
INSTANCEID=
INSTANCENAME=${HOSTNAME}
K8_OPTIONS="--ignore-preflight-errors=All --config=/etc/kubernetes/kubeadm-config.yaml"
KUBECONFIG=/etc/kubernetes/admin.conf
KUBERNETES_DISTRO=kubeadm
KUBERNETES_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
LOAD_BALANCER_IP=
MAX_PODS=110
PRIVATE_NET_INF=$(ip route get 1|awk '{print $5;exit}')
NODEGROUP_NAME=
NODEINDEX=0
NODENAME=${HOSTNAME}
POD_NETWORK_CIDR="10.244.0.0/16"
REGION=home
PRIVATE_DOMAIN_NAME=
SERVICE_NETWORK_CIDR="10.96.0.0/12"
TOKEN_TLL="0s"
ZONEID=office
USE_ETC_HOSTS=true
KUBEPATCH=/tmp/patch.yaml

export KUBECONFIG=

OPTIONS=(
	"advertise-port:"
	"allow-deployment:"
	"cloud-provider:"
	"cluster-nodes:"
	"cni-plugin:"
	"container-runtime:"
	"control-plane-endpoint:"
	"ecr-password:"
	"etcd-endpoint:"
	"ha-cluster:"
	"kube-engine:"
	"kube-version:"
	"load-balancer-ip:"
	"max-pods:"
	"net-if:"
	"node-group:"
	"node-index:"
	"plateform:"
	"private-zone-id:"
	"private-zone-name:"
	"region:"
	"tls-san:"
	"trace"
	"use-etc-hosts:"
	"use-external-etcd:"
	"vm-uuid:"
	"zone:"
)
PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o xm:g:r:i:c:n:k:p: --long "${PARAMS}" -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true; do
	case "$1" in
	--cloud-provider)
		CLOUD_PROVIDER=$2
		shift 2
		;;
	--plateform)
		PLATEFORM=$2
		shift 2
		;;
	-x|--trace)
		set -x
		shift 1
		;;
	-p|--advertise-port)
		APISERVER_ADVERTISE_PORT=$2
		shift 2
		;;
	-m|--max-pods)
		MAX_PODS=$2
		shift 2
		;;
	-g|--node-group)
		NODEGROUP_NAME="$2"
		shift 2
		;;
	--allow-deployment)
		MASTER_NODE_ALLOW_DEPLOYMENT=$2
		shift 2
		;;
	--use-etc-hosts)
		USE_ETC_HOSTS=$2
		shift 2
		;;
	--kube-engine)
		case "$2" in
			kubeadm|k3s|rke2|microk8s)
				KUBERNETES_DISTRO=$2
				;;
			*)
				echo "Unsupported kubernetes distribution: $2"
				exit 1
				;;
		esac
		shift 2
		;;
	-r|--container-runtime)
		case "$2" in
			"docker")
				CONTAINER_ENGINE="docker"
				CONTAINER_RUNTIME=docker
				CONTAINER_CTL=unix:///var/run/dockershim.sock
				;;
			"containerd")
				CONTAINER_ENGINE="$2"
				CONTAINER_RUNTIME=remote
				CONTAINER_CTL=unix:///var/run/containerd/containerd.sock
				;;
			"cri-o")
				CONTAINER_ENGINE="$2"
				CONTAINER_RUNTIME=remote
				CONTAINER_CTL=unix:///var/run/crio/crio.sock
				;;
			*)
				echo "Unsupported container runtime: $2"
				exit 1
				;;
		esac
		shift 2;;
	-i|--node-index)
		NODEINDEX="$2"
		shift 2
		;;
	--cni-plugin)
		CNI_PLUGIN=$2
		shift 2
		;;
	--ha-cluster)
		HA_CLUSTER=$2
		shift 2
		;;
	--load-balancer-ip)
		IFS=, read -a LOAD_BALANCER_IP <<< "$2"
		shift 2
		;;
	-c|--control-plane-endpoint)
		IFS=: read CONTROL_PLANE_ENDPOINT CONTROL_PLANE_ENDPOINT_ADDR <<< "$2"
		shift 2
		;;
	-n|--cluster-nodes)
		IFS=, read -a CLUSTER_NODES <<< "$2"
		shift 2
		;;
	-k|--kube-version)
		KUBERNETES_VERSION="$2"
		shift 2
		;;
	--tls-san)
		CERT_SANS=$2
		shift 2
		;;
	--use-external-etcd)
		EXTERNAL_ETCD=$2
		shift 2
		;;
	--etcd-endpoint)
		ETCD_ENDPOINT="$2"
		shift 2
		;;
# Specific per plateform
	--ecr-password)
		ECR_PASSWORD=$2
		shift 2
		;;
	--private-zone-id)
		AWS_ROUTE53_PRIVATE_ZONE_ID="$2"
		shift 2
		;;
	--private-zone-name)
		PRIVATE_DOMAIN_NAME="$2"
		shift 2
		;;
	--vm-uuid)
		INSTANCEID=$2
		shift 2
		;;
	--net-if)
		PRIVATE_NET_INF=$2
		shift 2
		;;
	--region)
		REGION=$2
		shift 2
		;;
	--zone)
		ZONEID=$2
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

function wait_node_ready() {
	echo -n "Wait node ${NODENAME} to be ready"

	while [ -z "$(kubectl get no ${NODENAME} 2>/dev/null | grep -v NAME)" ];
	do
		echo -n "."
		sleep 1
	done

	kubectl wait --for=condition=Ready nodes --field-selector metadata.name=${NODENAME} --timeout=120s

	echo
}

if [ -z "${NODEGROUP_NAME}" ]; then
	echo "NODEGROUP_NAME not defined"
	exit 1
fi

if [ ${PLATEFORM} == "aws" ]; then
	REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
	LOCALHOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
	MAC_ADDRESS="$(curl -s http://169.254.169.254/latest/meta-data/mac)"
	INSTANCEID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
	INSTANCENAME=$(aws ec2  describe-instances --region ${REGION} --instance-ids ${INSTANCEID} | jq -r '.Reservations[0].Instances[0].Tags[]|select(.Key == "Name")|.Value')
	SUBNET_IPV4_CIDR_BLOCK=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC_ADDRESS}/subnet-ipv4-cidr-block)
	VPC_IPV4_CIDR_BLOCK=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC_ADDRESS}/vpc-ipv4-cidr-block)
	ZONEID=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
	DNS_SERVER=$(echo ${VPC_IPV4_CIDR_BLOCK} | tr './' ' '| awk '{print $1"."$2"."$3".2"}')
	AWS_DOMAIN=${LOCALHOSTNAME#*.*}
	AWS_ROUTE53_PRIVATE_ZONE_ID=
	APISERVER_ADVERTISE_ADDRESS=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
	PROVIDERID=aws://${ZONEID}/${INSTANCEID}
else
	# Check if interface exists, else take inet default gateway
	ifconfig ${PRIVATE_NET_INF} &> /dev/null || PRIVATE_NET_INF=$(ip route get 1|awk '{print $5;exit}')
	APISERVER_ADVERTISE_ADDRESS=$(ip addr show ${PRIVATE_NET_INF} | grep "inet\s" | tr '/' ' ' | awk '{print $2}')
	APISERVER_ADVERTISE_ADDRESS=$(echo ${APISERVER_ADVERTISE_ADDRESS} | awk '{print $1}')

	if [ "${CLOUD_PROVIDER}" == "external" ]; then
		if [ ${PLATEFORM} == "openstack" ]; then
			PROVIDERID=${PLATEFORM}://${REGION}/${INSTANCEID}
		else
			PROVIDERID=${PLATEFORM}://${INSTANCEID}
		fi
	fi
fi

if [ ${USE_ETC_HOSTS} == "true" ]; then
	for CLUSTER_NODE in ${CLUSTER_NODES[@]}
	do
		IFS=: read HOST IP <<< "${CLUSTER_NODE}"
		if [ -n "${IP}" ]; then
			sed -i "/${HOST}/d" /etc/hosts
			echo "${IP}   ${HOST} ${HOST%%.*}" >> /etc/hosts
		fi
	done

	echo "${APISERVER_ADVERTISE_ADDRESS} $(hostname) ${CONTROL_PLANE_ENDPOINT}" >> /etc/hosts
fi

if [ -z "${LOAD_BALANCER_IP}" ]; then
	LOAD_BALANCER_IP=(${APISERVER_ADVERTISE_ADDRESS})
fi

# Hack because k3s and rke2 1.28.4 don't set the good feature gates
if [ "${DELETE_CREDENTIALS_CONFIG}" == "YES" ]; then
	case "${KUBERNETES_DISTRO}" in
		k3s|rke2)
		rm -rf /var/lib/rancher/credentialprovider
		;;
	esac
fi

mkdir -p /etc/kubernetes
mkdir -p ${CLUSTER_DIR}/etcd

if [ ${KUBERNETES_DISTRO} == "microk8s" ]; then
	IFS=. read VERSION MAJOR MINOR <<< "${KUBERNETES_VERSION}"
	MICROK8S_CHANNEL="${VERSION:1}.${MAJOR}/stable"
	MICROK8S_CONFIG=/var/snap/microk8s/common/.microk8s.yaml
	MICROK8S_CLUSTER_TOKEN=$(echo $(date +%s%N) | sha256sum | head -c 32)
	APISERVER_ADVERTISE_PORT=16443
	ANNOTE_MASTER=true

	mkdir -p "$(dirname ${MICROK8S_CONFIG})"

	if [ "${HA_CLUSTER}" == "true" ]; then
		DISABLE_HA_CLUSTER=false
	else
		DISABLE_HA_CLUSTER=true
	fi

	cat >  ${MICROK8S_CONFIG} <<EOF
version: 0.1.0
persistentClusterToken: ${MICROK8S_CLUSTER_TOKEN}
addons:
  - name: dns
  - name: rbac
  - name: ha-cluster
extraKubeAPIServerArgs:
  --advertise-address: ${APISERVER_ADVERTISE_ADDRESS}
  --authorization-mode: RBAC,Node
EOF

	if [ "${EXTERNAL_ETCD}" == "true" ]; then
		echo "  --etcd-servers: ${ETCD_ENDPOINT}" >> ${MICROK8S_CONFIG}
		echo "  --etcd-cafile: /etc/etcd/ssl/ca.pem" >> ${MICROK8S_CONFIG}
		echo "  --etcd-certfile: /etc/etcd/ssl/etcd.pem" >> ${MICROK8S_CONFIG}
		echo "  --etcd-keyfile: /etc/etcd/ssl/etcd-key.pem" >> ${MICROK8S_CONFIG}
	fi

	echo "extraKubeletArgs:" >> ${MICROK8S_CONFIG}
	echo "  --max-pods: ${MAX_PODS}" >> ${MICROK8S_CONFIG}
	echo "  --node-ip: ${APISERVER_ADVERTISE_ADDRESS}" >> ${MICROK8S_CONFIG}

	if [ "${CLOUD_PROVIDER}" == "external" ]; then
		echo "  --cloud-provider: ${CLOUD_PROVIDER}" >> ${MICROK8S_CONFIG}
		cat > ${KUBEPATCH} <<EOF
spec:
    providerID: "${PROVIDERID}"
EOF
	fi

	if [ -f /etc/kubernetes/credential.yaml ]; then
		echo "  --image-credential-provider-config: /etc/kubernetes/credential.yaml" >> ${MICROK8S_CONFIG}
		echo "  --image-credential-provider-bin-dir: /usr/local/bin" >> ${MICROK8S_CONFIG}
	fi

	echo "extraSANs:" >> ${MICROK8S_CONFIG}

	for CERT_SAN in $(echo -n ${CERT_SANS} | tr ',' ' ')
	do
		echo "  - ${CERT_SAN}" >>  ${MICROK8S_CONFIG}
	done

	cat ${MICROK8S_CONFIG}

	echo "Install microk8s ${MICROK8S_CHANNEL}"
	snap install microk8s --classic --channel=${MICROK8S_CHANNEL}
	
	echo "Wait microk8s get ready"
	microk8s status --wait-ready -t 600

	mkdir -p ${CLUSTER_DIR}/kubernetes/pki

	cp /var/snap/microk8s/current/certs/* ${CLUSTER_DIR}/kubernetes/pki

	if [ "${EXTERNAL_ETCD}" == "true" ]; then
		microk8s kubectl apply -f /var/snap/microk8s/current/args/cni-network/cni.yaml
	fi

	mkdir -p /etc/kubernetes/
	microk8s config -l > /etc/kubernetes/admin.conf

	KUBECONFIG=/etc/kubernetes/admin.conf

	cat /etc/kubernetes/admin.conf | sed \
		-e "s/admin/admin@${NODEGROUP_NAME}/g" \
		-e "s/127.0.0.1/${CONTROL_PLANE_ENDPOINT}/g" \
		-e "s/microk8s-cluster/${NODEGROUP_NAME}/g" | yq \
		".contexts[0].name = \"${NODEGROUP_NAME}\"| .current-context = \"${NODEGROUP_NAME}\"" > ${CLUSTER_DIR}/config

	echo -n ${MICROK8S_CLUSTER_TOKEN} > ${CLUSTER_DIR}/token
	openssl x509 -pubkey -in /var/snap/microk8s/current/certs/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' | tr -d '\n' > ${CLUSTER_DIR}/ca.cert

	chmod -R uog+r ${CLUSTER_DIR}/*

elif [ ${KUBERNETES_DISTRO} == "rke2" ]; then
	ANNOTE_MASTER=true

	if [ "${CLOUD_PROVIDER}" == "external" ]; then
		cat > /etc/rancher/rke2/config.yaml <<EOF
kubelet-arg:
  - cloud-provider=external
  - fail-swap-on=false
  - provider-id=${PROVIDERID}
  - max-pods=${MAX_PODS}
node-name: ${HOSTNAME}
advertise-address: ${APISERVER_ADVERTISE_ADDRESS}
disable-cloud-controller: true
cloud-provider-name: external
disable:
  - rke2-ingress-nginx
  - rke2-metrics-server
  - servicelb
tls-san:
EOF
	else
		cat > /etc/rancher/rke2/config.yaml <<EOF
kubelet-arg:
  - fail-swap-on=false
  - max-pods=${MAX_PODS}
node-name: ${HOSTNAME}
advertise-address: ${APISERVER_ADVERTISE_ADDRESS}
disable:
  - rke2-ingress-nginx
  - rke2-metrics-server
  - servicelb
tls-san:
EOF
	fi

	for CERT_SAN in $(echo -n ${CERT_SANS} | tr ',' ' ')
	do
		echo "  - ${CERT_SAN}" >> /etc/rancher/rke2/config.yaml
	done

	if [ "${HA_CLUSTER}" = "true" ]; then
		echo "cluster-init: true" >> /etc/rancher/rke2/config.yaml
	fi

	echo -n "Start rke2-server service"

	systemctl enable rke2-server.service
	systemctl start rke2-server.service

	while [ ! -f /etc/rancher/rke2/rke2.yaml ];
	do
		echo -n "."
		sleep 1
	done

	echo

	mkdir -p ${CLUSTER_DIR}/kubernetes/pki

	KUBECONFIG=/etc/rancher/rke2/rke2.yaml

	cp /var/lib/rancher/rke2/server/token ${CLUSTER_DIR}/token
	cp -r /var/lib/rancher/rke2/server/tls/* ${CLUSTER_DIR}/kubernetes/pki/

	openssl x509 -pubkey -in /var/lib/rancher/rke2/server/tls/server-ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' | tr -d '\n' > ${CLUSTER_DIR}/ca.cert

	cat ${KUBECONFIG} | sed \
		-e "s/127.0.0.1/${CONTROL_PLANE_ENDPOINT}/g" \
		-e "s/default/kubernetes-admin@${NODEGROUP_NAME}/g" > ${CLUSTER_DIR}/config

	rm -rf ${CLUSTER_DIR}/kubernetes/pki/temporary-certs

elif [ ${KUBERNETES_DISTRO} == "k3s" ]; then
	ANNOTE_MASTER=true

	K3S_MODE=server
	K3S_ARGS="--kubelet-arg=max-pods=${MAX_PODS} --node-name=${NODENAME} --advertise-address=${APISERVER_ADVERTISE_ADDRESS} --advertise-port=${APISERVER_ADVERTISE_PORT} --tls-san=${CERT_SANS}"
	K3S_DISABLE_ARGS="--disable=servicelb --disable=traefik --disable=metrics-server"
	K3S_SERVER_ARGS=

	if [ -n "${PROVIDERID}" ]; then
		K3S_ARGS="${K3S_ARGS} --kubelet-arg=provider-id=${PROVIDERID}"
	fi

	if [ "${CLOUD_PROVIDER}" == "external" ]; then
		K3S_DISABLE_ARGS="${K3S_DISABLE_ARGS} --disable-cloud-controller"
	fi

	if [ "${HA_CLUSTER}" = "true" ]; then
		K3S_MODE=server

		if [ "${EXTERNAL_ETCD}" == "true" ] && [ -n "${ETCD_ENDPOINT}" ]; then
			K3S_SERVER_ARGS="--datastore-endpoint=${ETCD_ENDPOINT} --datastore-cafile /etc/etcd/ssl/ca.pem --datastore-certfile /etc/etcd/ssl/etcd.pem --datastore-keyfile /etc/etcd/ssl/etcd-key.pem"
		else
			K3S_SERVER_ARGS="--cluster-init"
		fi
	fi

	echo "K3S_MODE=${K3S_MODE}" > /etc/default/k3s
	echo "K3S_ARGS='${K3S_ARGS}'" > /etc/systemd/system/k3s.service.env
	echo "K3S_DISABLE_ARGS='${K3S_DISABLE_ARGS}'" > /etc/systemd/system/k3s.disabled.env
	echo "K3S_SERVER_ARGS='${K3S_SERVER_ARGS}'" > /etc/systemd/system/k3s.server.env

	echo -n "Start k3s service"

	systemctl enable k3s.service
	systemctl start k3s.service

	while [ ! -f /etc/rancher/k3s/k3s.yaml ];
	do
		echo -n "."
		sleep 1
	done

	echo

	KUBECONFIG=/etc/rancher/k3s/k3s.yaml

	mkdir -p ${CLUSTER_DIR}/kubernetes/pki

	cp /var/lib/rancher/k3s/server/token ${CLUSTER_DIR}/token
	cp -r /var/lib/rancher/k3s/server/tls/* ${CLUSTER_DIR}/kubernetes/pki/

	openssl x509 -pubkey -in /var/lib/rancher/k3s/server/tls/server-ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' | tr -d '\n' > ${CLUSTER_DIR}/ca.cert

	cat ${KUBECONFIG} | sed \
		-e "s/127.0.0.1/${CONTROL_PLANE_ENDPOINT}/g" \
		-e "s/default/kubernetes-admin@${NODEGROUP_NAME}/g" > ${CLUSTER_DIR}/config

	rm -rf ${CLUSTER_DIR}/kubernetes/pki/temporary-certs
else
	if [ -f /etc/kubernetes/kubelet.conf ]; then
		echo "Already installed k8s master node"
	fi

	if [ -e /etc/default/kubelet ]; then
		source /etc/default/kubelet
	else
		touch /etc/default/kubelet
	fi

	systemctl restart kubelet

	if [ -z "${CNI_PLUGIN}" ]; then
		CNI_PLUGIN="calico"
	fi

	CNI_PLUGIN=$(echo "${CNI_PLUGIN}" | tr '[:upper:]' '[:lower:]')
	KUBEADM_TOKEN=$(kubeadm token generate)
	KUBEADM_CONFIG=/etc/kubernetes/kubeadm-config.yaml

	case ${CNI_PLUGIN} in
		aws)
			POD_NETWORK_CIDR="${VPC_IPV4_CIDR_BLOCK}"
			TEN_RANGE=$(echo -n ${VPC_IPV4_CIDR_BLOCK} | grep -c '^10\..*' || true )

			if [ ${TEN_RANGE} -eq 0 ]; then
				CLUSTER_DNS="10.100.0.10"
				SERVICE_NETWORK_CIDR="10.100.0.0/16"
			else
				SERVICE_NETWORK_CIDR="172.20.0.0/16"
				CLUSTER_DNS="172.20.0.10"
			fi
			;;
		flannel)
			SERVICE_NETWORK_CIDR="10.96.0.0/12"
			POD_NETWORK_CIDR="10.244.0.0/16"
			;;
		weave|canal|kube|romana)
			SERVICE_NETWORK_CIDR="10.96.0.0/12"
			POD_NETWORK_CIDR="10.244.0.0/16"
			;;
		calico)
			SERVICE_NETWORK_CIDR="10.96.0.0/12"
			POD_NETWORK_CIDR="192.168.0.0/16"
			;;
		*)
			echo "CNI ${CNI_PLUGIN} is not supported"
			exit -1
			;;
	esac

	IFS=. read VERSION MAJOR MINOR <<< "${KUBERNETES_VERSION}"

	cat > ${KUBEADM_CONFIG} <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: ${KUBEADM_TOKEN}
  ttl: ${TOKEN_TLL}
  usages:
  - signing
  - authentication
localAPIEndpoint:
  advertiseAddress: ${APISERVER_ADVERTISE_ADDRESS}
  bindPort: ${APISERVER_ADVERTISE_PORT}
nodeRegistration:
  criSocket: ${CONTAINER_CTL}
  name: ${NODENAME}
  taints:
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
  kubeletExtraArgs:
    container-runtime: ${CONTAINER_RUNTIME}
    container-runtime-endpoint: ${CONTAINER_CTL}
    cloud-provider: ${CLOUD_PROVIDER}
    node-ip: ${APISERVER_ADVERTISE_ADDRESS}
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: ${APISERVER_ADVERTISE_ADDRESS}
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 0s
    cacheUnauthorizedTTL: 0s
clusterDNS:
  - ${CLUSTER_DNS}
cgroupDriver: systemd
failSwapOn: false
hairpinMode: hairpin-veth
readOnlyPort: 10255
clusterDomain: cluster.local
cpuManagerReconcilePeriod: 0s
evictionPressureTransitionPeriod: 0s
fileCheckFrequency: 0s
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 0s
imageMinimumGCAge: 0s
nodeStatusReportFrequency: 0s
nodeStatusUpdateFrequency: 0s
rotateCertificates: true
runtimeRequestTimeout: 0s
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 0s
syncFrequency: 0s
volumeStatsAggPeriod: 0s
maxPods: ${MAX_PODS}
providerID: ${PROVIDERID}
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
certificatesDir: /etc/kubernetes/pki
clusterName: ${NODEGROUP_NAME}
imageRepository: registry.k8s.io
kubernetesVersion: ${KUBERNETES_VERSION}
networking:
  dnsDomain: cluster.local
  serviceSubnet: ${SERVICE_NETWORK_CIDR}
  podSubnet: ${POD_NETWORK_CIDR}
scheduler: {}
controllerManager:
  extraArgs:
    cloud-provider: "${CLOUD_PROVIDER}"
    configure-cloud-routes: "${CONFIGURE_CLOUD_ROUTE}"
controlPlaneEndpoint: ${CONTROL_PLANE_ENDPOINT}:${APISERVER_ADVERTISE_PORT}
#dns:
#  imageRepository: registry.k8s.io/coredns
#  imageTag: v1.9.3
apiServer:
  extraArgs:
    authorization-mode: Node,RBAC
    cloud-provider: "${CLOUD_PROVIDER}"
  timeoutForControlPlane: 4m0s
  certSANs:
EOF

	for CERT_SAN in $(echo -n ${CERT_SANS} | tr ',' ' ')
	do
		echo "  - ${CERT_SAN}" >> ${KUBEADM_CONFIG}
	done

	# External ETCD
	if [ "${EXTERNAL_ETCD}" = "true" ] && [ -n "${ETCD_ENDPOINT}" ]; then
		cat >> ${KUBEADM_CONFIG} <<EOF
etcd:
  external:
    caFile: /etc/etcd/ssl/ca.pem
    certFile: /etc/etcd/ssl/etcd.pem
    keyFile: /etc/etcd/ssl/etcd-key.pem
    endpoints:
EOF

		for ENDPOINT in $(echo -n ${ETCD_ENDPOINT} | tr ',' ' ')
		do
			echo "    - ${ENDPOINT}" >> ${KUBEADM_CONFIG}
		done
	fi

	# If version 27 or greater, remove this kuletet argument
	if [ ${MAJOR} -ge 27 ]; then
		sed -i '/container-runtime:/d' ${KUBEADM_CONFIG}
	fi

	# Kubelet argument if credential config exist
	if [ -f /etc/kubernetes/credential.yaml ]; then
		echo "KUBELET_EXTRA_ARGS='--image-credential-provider-config=/etc/kubernetes/credential.yaml --image-credential-provider-bin-dir=/usr/local/bin'" > /etc/default/kubelet
	fi

	echo "Init K8 cluster with options:$K8_OPTIONS"

	cat ${KUBEADM_CONFIG}

	kubeadm init $K8_OPTIONS 2>&1

	echo "Retrieve token infos"

	openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' | tr -d '\n' > ${CLUSTER_DIR}/ca.cert
	kubeadm token list 2>&1 | grep "authentication,signing" | awk '{print $1}'  | tr -d '\n' > ${CLUSTER_DIR}/token 

	echo "Get token:$(cat ${CLUSTER_DIR}/token)"
	echo "Get cacert:$(cat ${CLUSTER_DIR}/ca.cert)"
	echo "Set local K8 environement"

	KUBECONFIG=/etc/kubernetes/admin.conf

	cat ${KUBECONFIG} | sed \
		-e "s/kubernetes-admin@${NODEGROUP_NAME}/${NODEGROUP_NAME}/g" \
		-e "s/kubernetes-admin/kubernetes-admin@${NODEGROUP_NAME}/g" > ${CLUSTER_DIR}/config

	mkdir -p ${CLUSTER_DIR}/kubernetes/pki

	cp /etc/kubernetes/pki/ca.crt ${CLUSTER_DIR}/kubernetes/pki
	cp /etc/kubernetes/pki/ca.key ${CLUSTER_DIR}/kubernetes/pki
	cp /etc/kubernetes/pki/sa.key ${CLUSTER_DIR}/kubernetes/pki
	cp /etc/kubernetes/pki/sa.pub ${CLUSTER_DIR}/kubernetes/pki
	cp /etc/kubernetes/pki/front-proxy-ca.crt ${CLUSTER_DIR}/kubernetes/pki
	cp /etc/kubernetes/pki/front-proxy-ca.key ${CLUSTER_DIR}/kubernetes/pki

	if [ "${EXTERNAL_ETCD}" != "true" ]; then
		mkdir -p ${CLUSTER_DIR}/kubernetes/pki/etcd
		cp /etc/kubernetes/pki/etcd/ca.crt ${CLUSTER_DIR}/kubernetes/pki/etcd/ca.crt
		cp /etc/kubernetes/pki/etcd/ca.key ${CLUSTER_DIR}/kubernetes/pki/etcd/ca.key
	fi

	chmod -R uog+r ${CLUSTER_DIR}/*

	if [ "${CNI_PLUGIN}" = "aws" ]; then
		# Password for AWS cni plugin
		if [ -n "${ECR_PASSWORD}" ]; then
			kubectl create secret docker-registry aws-registry --docker-server=602401143452.dkr.ecr.us-west-2.amazonaws.com --docker-username=AWS --docker-password=${ECR_PASSWORD}
		fi

		echo "Install AWS network"

		KUBERNETES_MINOR_RELEASE=$(kubectl version -o json | jq -r .serverVersion.minor)

		kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.16.2/config/master/aws-k8s-cni.yaml

		kubectl set env daemonset -n kube-system aws-node AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS=${VPC_IPV4_CIDR_BLOCK}

	elif [ "${CNI_PLUGIN}" = "calico" ]; then

		echo "Install calico network"

		kubectl apply -f "https://docs.projectcalico.org/manifests/calico-vxlan.yaml" 2>&1

	elif [ "${CNI_PLUGIN}" = "flannel" ]; then

		echo "Install flannel network"

		kubectl apply -f "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml" 2>&1

	elif [ "${CNI_PLUGIN}" = "weave" ]; then

		echo "Install weave network for K8"

		kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')" 2>&1

	elif [ "${CNI_PLUGIN}" = "canal" ]; then

		echo "Install canal network"

		kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/canal.yaml" 2>&1

	elif [ "${CNI_PLUGIN}" = "kube" ]; then

		echo "Install kube network"

		kubectl apply -f "https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml" 2>&1
		kubectl apply -f "https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter-all-features.yaml" 2>&1

	elif [ "${CNI_PLUGIN}" = "romana" ]; then

		echo "Install romana network"

		kubectl apply -f https://raw.githubusercontent.com/romana/romana/master/containerize/specs/romana-kubeadm.yml 2>&1

	fi
fi

wait_node_ready

if [ -f "${KUBEPATCH}" ]; then
    kubectl patch node ${NODENAME} --patch-file ${KUBEPATCH}
fi

SUDO_HOME=$(eval echo ~${SUDO_USER})

mkdir -p ${SUDO_HOME}/.kube
cp ${KUBECONFIG} ${SUDO_HOME}/.kube/config
chown ${SUDO_UID}:${SUDO_GID} ${SUDO_HOME}/.kube/config

chmod -R uog+r ${CLUSTER_DIR}/*

kubectl label nodes ${NODENAME} \
	"cluster.autoscaler.nodegroup/name=${NODEGROUP_NAME}" \
	"node-role.kubernetes.io/control-plane=${ANNOTE_MASTER}" \
	"node-role.kubernetes.io/master=${ANNOTE_MASTER}" \
	"topology.kubernetes.io/region=${REGION}" \
	"topology.kubernetes.io/zone=${ZONEID}" \
	"topology.csi.vmware.com/k8s-region=${REGION}" \
	"topology.csi.vmware.com/k8s-zone=${ZONEID}" \
	"master=true" \
	--overwrite

kubectl annotate node ${NODENAME} \
	"cluster.autoscaler.nodegroup/name=${NODEGROUP_NAME}" \
	"cluster.autoscaler.nodegroup/instance-id=${INSTANCEID}" \
	"cluster.autoscaler.nodegroup/instance-name=${INSTANCENAME}" \
	"cluster.autoscaler.nodegroup/node-index=${NODEINDEX}" \
	"cluster.autoscaler.nodegroup/autoprovision=false" \
	"cluster-autoscaler.kubernetes.io/scale-down-disabled=true" \
	--overwrite

if [ "${MASTER_NODE_ALLOW_DEPLOYMENT}" = "YES" ];then
	kubectl taint node ${NODENAME} node-role.kubernetes.io/master:NoSchedule- node-role.kubernetes.io/control-plane:NoSchedule-
elif [ "${KUBERNETES_DISTRO}" == "k3s" ]; then
	kubectl taint node ${NODENAME} node-role.kubernetes.io/master:NoSchedule node-role.kubernetes.io/control-plane:NoSchedule
fi

#sed -i -e "/${CONTROL_PLANE_ENDPOINT%%.}/d" /etc/hosts

if [ "${KUBERNETES_DISTRO}" == "microk8s" ]; then
	echo -n "${APISERVER_ADVERTISE_ADDRESS}:${APISERVER_ADVERTISE_PORT}" > ${CLUSTER_DIR}/manager-ip
else
	echo -n "${LOAD_BALANCER_IP[0]}:${APISERVER_ADVERTISE_PORT}" > ${CLUSTER_DIR}/manager-ip
fi

echo "Done k8s master node"
