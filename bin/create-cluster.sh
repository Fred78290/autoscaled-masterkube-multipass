#!/bin/bash

set -e

APISERVER_ADVERTISE_PORT=6443
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
DELETE_CREDENTIALS_CONFIG=NO
ETCD_ENDPOINT=
EXTERNAL_ETCD=false
HA_CLUSTER=false
INSTANCEID=
INSTANCENAME=$HOSTNAME
K8_OPTIONS="--ignore-preflight-errors=All --config=/etc/kubernetes/kubeadm-config.yaml"
KUBEADM_CONFIG=/etc/kubernetes/kubeadm-config.yaml
KUBECONFIG=/etc/kubernetes/admin.conf
KUBERNETES_DISTRO=kubeadm
KUBERNETES_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
LOAD_BALANCER_IP=
MAX_PODS=110
NET_IF=$(ip route get 1|awk '{print $5;exit}')
NODEGROUP_NAME=
NODEINDEX=0
NODENAME=$HOSTNAME
POD_NETWORK_CIDR="10.244.0.0/16"
REGION=home
PRIVATE_DOMAIN_NAME=
SERVICE_NETWORK_CIDR="10.96.0.0/12"
TOKEN_TLL="0s"
ZONEID=office

export KUBECONFIG=

if [ "$(uname -p)" == "aarch64" ]; then
	ARCH="arm64"
else
	ARCH="amd64"
fi

TEMP=$(getopt -o xm:g:r:i:c:n:k: --long cloud-provider:,plateform:,tls-san:,delete-credentials-provider:,etcd-endpoint:,k8s-distribution:,allow-deployment:,max-pods:,trace:,container-runtime:,node-index:,use-external-etcd:,load-balancer-ip:,node-group:,cluster-nodes:,control-plane-endpoint:,ha-cluster:,cni:,kubernetes-version:,csi-region:,csi-zone:,vm-uuid:,net-if:,ecr-password:,private-zone-id:,private-zone-name: -n "$0" -- "$@")

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
	--delete-credentials-provider)
		DELETE_CREDENTIALS_CONFIG=$2
		shift 2
		;;
	--k8s-distribution)
		case "$2" in
			kubeadm|k3s|rke2)
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
	--cni)
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
	-k|--kubernetes-version)
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
		AWS_ROUTE53_ZONE_ID="$2"
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
		NET_IF=$2
		shift 2
		;;
	--csi-region)
		REGION=$2
		shift 2
		;;
	--csi-zone)
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

if [ ${PLATEFORM} == "aws" ]; then
	REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
	LOCALHOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
	MAC_ADDRESS="$(curl -s http://169.254.169.254/latest/meta-data/mac)"
	INSTANCEID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
	INSTANCENAME=$(aws ec2  describe-instances --region $REGION --instance-ids $INSTANCEID | jq -r '.Reservations[0].Instances[0].Tags[]|select(.Key == "Name")|.Value')
	SUBNET_IPV4_CIDR_BLOCK=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC_ADDRESS}/subnet-ipv4-cidr-block)
	VPC_IPV4_CIDR_BLOCK=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC_ADDRESS}/vpc-ipv4-cidr-block)
	ZONEID=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
	DNS_SERVER=$(echo $VPC_IPV4_CIDR_BLOCK | tr './' ' '| awk '{print $1"."$2"."$3".2"}')
	AWS_DOMAIN=${LOCALHOSTNAME#*.*}
	AWS_ROUTE53_ZONE_ID=
	APISERVER_ADVERTISE_ADDRESS=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
	PROVIDERID=aws://${ZONEID}/${INSTANCEID}
else
	# Check if interface exists, else take inet default gateway
	ifconfig $NET_IF &> /dev/null || NET_IF=$(ip route get 1|awk '{print $5;exit}')
	APISERVER_ADVERTISE_ADDRESS=$(ip addr show $NET_IF | grep "inet\s" | tr '/' ' ' | awk '{print $2}')
	APISERVER_ADVERTISE_ADDRESS=$(echo $APISERVER_ADVERTISE_ADDRESS | awk '{print $1}')

	if [ "${CLOUD_PROVIDER}" == "external" ]; then
		PROVIDERID=${PLATEFORM}://${INSTANCEID}
	fi

	if [ "$HA_CLUSTER" = "true" ]; then
		for CLUSTER_NODE in ${CLUSTER_NODES[*]}
		do
			IFS=: read HOST IP <<< "$CLUSTER_NODE"
			sed -i "/$HOST/d" /etc/hosts
			echo "${IP}   ${HOST} ${HOST%%.*}" >> /etc/hosts
		done
	fi
fi

if [ -z "$LOAD_BALANCER_IP" ]; then
	LOAD_BALANCER_IP=($APISERVER_ADVERTISE_ADDRESS)
fi

if [ -z "${NODEGROUP_NAME}" ]; then
	echo "NODEGROUP_NAME not defined"
	exit 1
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
mkdir -p $CLUSTER_DIR/etcd

echo "${APISERVER_ADVERTISE_ADDRESS} $(hostname) ${CONTROL_PLANE_ENDPOINT}" >> /etc/hosts

NODENAME=$HOSTNAME

if [ ${KUBERNETES_DISTRO} == "rke2" ]; then
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

	if [ "$HA_CLUSTER" = "true" ]; then
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

	mkdir -p $CLUSTER_DIR/kubernetes/pki

	mkdir -p $HOME/.kube
	cp -i /etc/rancher/rke2/rke2.yaml $HOME/.kube/config
	chown $(id -u):$(id -g) $HOME/.kube/config

	cp /etc/rancher/rke2/rke2.yaml $CLUSTER_DIR/config
	cp /var/lib/rancher/rke2/server/token $CLUSTER_DIR/token
	cp -r /var/lib/rancher/rke2/server/tls/* $CLUSTER_DIR/kubernetes/pki/

	openssl x509 -pubkey -in /var/lib/rancher/rke2/server/tls/server-ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' | tr -d '\n' > $CLUSTER_DIR/ca.cert

	sed -i -e "s/127.0.0.1/${CONTROL_PLANE_ENDPOINT}/g" -e "s/default/k8s-${HOSTNAME}-admin@${NODEGROUP_NAME}/g" $CLUSTER_DIR/config

	rm -rf $CLUSTER_DIR/kubernetes/pki/temporary-certs

	KUBECONFIG=/etc/rancher/rke2/rke2.yaml

	echo -n "Wait node ${HOSTNAME} to be ready"

	while [ -z "$(kubectl get no ${HOSTNAME} 2>/dev/null | grep -v NAME)" ];
	do
		echo -n "."
		sleep 1
	done

	echo

elif [ ${KUBERNETES_DISTRO} == "k3s" ]; then
	ANNOTE_MASTER=true

	echo "K3S_MODE=server" > /etc/default/k3s
	echo "K3S_ARGS='--kubelet-arg=provider-id=${PROVIDERID} --kubelet-arg=max-pods=${MAX_PODS} --node-name=${NODENAME} --advertise-address=${APISERVER_ADVERTISE_ADDRESS} --advertise-port=${APISERVER_ADVERTISE_PORT} --tls-san=${CERT_SANS}'" > /etc/systemd/system/k3s.service.env

	if [ "$CLOUD_PROVIDER" == "external" ]; then
		echo "K3S_DISABLE_ARGS='--disable-cloud-controller --disable=servicelb --disable=traefik --disable=metrics-server'" > /etc/systemd/system/k3s.disabled.env
	else
		echo "K3S_DISABLE_ARGS='--disable=servicelb --disable=traefik --disable=metrics-server'" > /etc/systemd/system/k3s.disabled.env
	fi

	if [ "$HA_CLUSTER" = "true" ]; then
		if [ "${EXTERNAL_ETCD}" == "true" ] && [ -n "${ETCD_ENDPOINT}" ]; then
			echo "K3S_SERVER_ARGS='--datastore-endpoint=${ETCD_ENDPOINT} --datastore-cafile /etc/etcd/ssl/ca.pem --datastore-certfile /etc/etcd/ssl/etcd.pem --datastore-keyfile /etc/etcd/ssl/etcd-key.pem'" > /etc/systemd/system/k3s.server.env
		else
			echo "K3S_SERVER_ARGS=--cluster-init" > /etc/systemd/system/k3s.server.env
		fi
	fi

	echo -n "Start k3s service"

	systemctl enable k3s.service
	systemctl start k3s.service

	while [ ! -f /etc/rancher/k3s/k3s.yaml ];
	do
		echo -n "."
		sleep 1
	done

	echo

	mkdir -p $CLUSTER_DIR/kubernetes/pki

	mkdir -p $HOME/.kube
	cp -i /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
	chown $(id -u):$(id -g) $HOME/.kube/config

	cp /etc/rancher/k3s/k3s.yaml $CLUSTER_DIR/config
	cp /var/lib/rancher/k3s/server/token $CLUSTER_DIR/token
	cp -r /var/lib/rancher/k3s/server/tls/* $CLUSTER_DIR/kubernetes/pki/

	openssl x509 -pubkey -in /var/lib/rancher/k3s/server/tls/server-ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' | tr -d '\n' > $CLUSTER_DIR/ca.cert

	sed -i -e "s/127.0.0.1/${CONTROL_PLANE_ENDPOINT}/g" -e "s/default/k8s-${HOSTNAME}-admin@${NODEGROUP_NAME}/g" $CLUSTER_DIR/config

	rm -rf $CLUSTER_DIR/kubernetes/pki/temporary-certs

	KUBECONFIG=/etc/rancher/k3s/k3s.yaml

	echo -n "Wait node ${NODENAME} to be ready"

	while [ -z "$(kubectl get no ${NODENAME} 2>/dev/null | grep -v NAME)" ];
	do
		echo -n "."
		sleep 1
	done

	echo

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

	if [ -z "$CNI_PLUGIN" ]; then
		CNI_PLUGIN="calico"
	fi

	CNI_PLUGIN=$(echo "$CNI_PLUGIN" | tr '[:upper:]' '[:lower:]')
	KUBEADM_TOKEN=$(kubeadm token generate)

	case $CNI_PLUGIN in
		aws)
			POD_NETWORK_CIDR="${VPC_IPV4_CIDR_BLOCK}"
			TEN_RANGE=$(echo -n ${VPC_IPV4_CIDR_BLOCK} | grep -c '^10\..*' || true )

			if [ $TEN_RANGE -eq 0 ]; then
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
			echo "CNI $CNI_PLUGIN is not supported"
			exit -1
			;;
	esac

	IFS=. read VERSION MAJOR MINOR <<< "$KUBERNETES_VERSION"

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
		echo "  - $CERT_SAN" >> ${KUBEADM_CONFIG}
	done

	# External ETCD
	if [ "$EXTERNAL_ETCD" = "true" ] && [ -n "${ETCD_ENDPOINT}" ]; then
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
	if [ $MAJOR -ge 27 ]; then
		sed -i '/container-runtime:/d' ${KUBEADM_CONFIG}
	fi

	echo "Init K8 cluster with options:$K8_OPTIONS"

	cat ${KUBEADM_CONFIG}

	kubeadm init $K8_OPTIONS 2>&1

	echo "Retrieve token infos"

	openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' | tr -d '\n' > $CLUSTER_DIR/ca.cert
	kubeadm token list 2>&1 | grep "authentication,signing" | awk '{print $1}'  | tr -d '\n' > $CLUSTER_DIR/token 

	echo "Get token:$(cat $CLUSTER_DIR/token)"
	echo "Get cacert:$(cat $CLUSTER_DIR/ca.cert)"
	echo "Set local K8 environement"

	mkdir -p $HOME/.kube
	cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	chown $(id -u):$(id -g) $HOME/.kube/config

	cp /etc/kubernetes/admin.conf $CLUSTER_DIR/config

	KUBECONFIG=/etc/kubernetes/admin.conf

	mkdir -p $CLUSTER_DIR/kubernetes/pki

	cp /etc/kubernetes/pki/ca.crt $CLUSTER_DIR/kubernetes/pki
	cp /etc/kubernetes/pki/ca.key $CLUSTER_DIR/kubernetes/pki
	cp /etc/kubernetes/pki/sa.key $CLUSTER_DIR/kubernetes/pki
	cp /etc/kubernetes/pki/sa.pub $CLUSTER_DIR/kubernetes/pki
	cp /etc/kubernetes/pki/front-proxy-ca.crt $CLUSTER_DIR/kubernetes/pki
	cp /etc/kubernetes/pki/front-proxy-ca.key $CLUSTER_DIR/kubernetes/pki

	if [ "$EXTERNAL_ETCD" != "true" ]; then
		mkdir -p $CLUSTER_DIR/kubernetes/pki/etcd
		cp /etc/kubernetes/pki/etcd/ca.crt $CLUSTER_DIR/kubernetes/pki/etcd/ca.crt
		cp /etc/kubernetes/pki/etcd/ca.key $CLUSTER_DIR/kubernetes/pki/etcd/ca.key
	fi

	chmod -R uog+r $CLUSTER_DIR/*

	# Password for AWS cni plugin
	kubectl create secret docker-registry aws-registry --docker-server=602401143452.dkr.ecr.us-west-2.amazonaws.com --docker-username=AWS --docker-password=${ECR_PASSWORD}

	if [ "$CNI_PLUGIN" = "aws" ]; then

		echo "Install AWS network"

		KUBERNETES_MINOR_RELEASE=$(kubectl version -o json | jq -r .serverVersion.minor)
		UBUNTU_VERSION_ID=$(cat /etc/os-release | grep VERSION_ID | tr -d '"' | cut -d '=' -f 2 | cut -d '.' -f 1)

		if [ ${KUBERNETES_MINOR_RELEASE} -gt 27 ]; then
			AWS_CNI_URL=https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.16.0/config/master/aws-k8s-cni.yaml
		elif [ $KUBERNETES_MINOR_RELEASE -gt 26 ]; then
			AWS_CNI_URL=https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.15.5/config/master/aws-k8s-cni.yaml
		elif [ $KUBERNETES_MINOR_RELEASE -gt 25 ]; then
			AWS_CNI_URL=https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.14.1/config/master/aws-k8s-cni.yaml
		elif [ $KUBERNETES_MINOR_RELEASE -gt 24 ]; then
			AWS_CNI_URL=https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.12.1/config/master/aws-k8s-cni.yaml
		elif [ $KUBERNETES_MINOR_RELEASE -gt 22 ]; then
			AWS_CNI_URL=https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.11/config/master/aws-k8s-cni.yaml
		elif [ $KUBERNETES_MINOR_RELEASE -gt 20 ]; then
			AWS_CNI_URL=https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.10/config/master/aws-k8s-cni.yaml
		else
			AWS_CNI_URL=https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.9.3/config/v1.9/aws-k8s-cni.yaml
		fi

		if [ $CONTAINER_ENGINE == "cri-o" ]; then
			curl -s ${AWS_CNI_URL} | yq e -P - \
					| sed -e 's/mountPath: \/var\/run\/dockershim\.sock/mountPath: \/var\/run\/cri\.sock/g' -e 's/path: \/var\/run\/dockershim\.sock/path: \/var\/run\/cri\.sock/g' > cni-aws.yaml
		elif [ $CONTAINER_ENGINE == "containerd" ]; then
			curl -s ${AWS_CNI_URL} | yq e -P - \
					| sed -e 's/mountPath: \/var\/run\/dockershim\.sock/mountPath: \/var\/run\/cri\.sock/g' -e 's/path: \/var\/run\/dockershim\.sock/path: \/var\/run\/containerd\/containerd\.sock/g' > cni-aws.yaml
		else
			curl -s ${AWS_CNI_URL} > cni-aws.yaml
		fi

		# https://github.com/aws/amazon-vpc-cni-k8s/issues/2103
		if [ ${UBUNTU_VERSION_ID} -ge 22 ]; then
			sed -i '/ENABLE_IPv6/i\            - name: ENABLE_NFTABLES\n              value: "true"' cni-aws.yaml
		fi

		kubectl apply -f cni-aws.yaml

		kubectl set env daemonset -n kube-system aws-node AWS_VPC_K8S_CNI_EXCLUDE_SNAT_CIDRS=${VPC_IPV4_CIDR_BLOCK}

	elif [ "$CNI_PLUGIN" = "calico" ]; then

		echo "Install calico network"

		kubectl apply -f "https://docs.projectcalico.org/manifests/calico-vxlan.yaml" 2>&1

	elif [ "$CNI_PLUGIN" = "flannel" ]; then

		echo "Install flannel network"

		kubectl apply -f "https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml" 2>&1

	elif [ "$CNI_PLUGIN" = "weave" ]; then

		echo "Install weave network for K8"

		kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')" 2>&1

	elif [ "$CNI_PLUGIN" = "canal" ]; then

		echo "Install canal network"

		kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/canal.yaml" 2>&1

	elif [ "$CNI_PLUGIN" = "kube" ]; then

		echo "Install kube network"

		kubectl apply -f "https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml" 2>&1
		kubectl apply -f "https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter-all-features.yaml" 2>&1

	elif [ "$CNI_PLUGIN" = "romana" ]; then

		echo "Install romana network"

		kubectl apply -f https://raw.githubusercontent.com/romana/romana/master/containerize/specs/romana-kubeadm.yml 2>&1

	fi

	if [ -n "${PROVIDERID}" ]; then
		cat > patch.yaml <<EOF
spec:
  providerID: '${PROVIDERID}'
EOF

		kubectl patch node ${NODENAME} --patch-file patch.yaml
	fi
fi

chmod -R uog+r $CLUSTER_DIR/*

kubectl label nodes ${NODENAME} \
	"cluster.autoscaler.nodegroup/name=${NODEGROUP_NAME}" \
	"node-role.kubernetes.io/master=${ANNOTE_MASTER}" \
	"topology.kubernetes.io/region=${REGION}" \
	"topology.kubernetes.io/zone=${ZONEID}" \
	"topology.csi.vmware.com/k8s-region=${REGION}" \
	"topology.csi.vmware.com/k8s-zone=${ZONEID}" \
	"master=true"
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

sed -i -e "/${CONTROL_PLANE_ENDPOINT%%.}/d" /etc/hosts

echo -n "${LOAD_BALANCER_IP[0]}:${APISERVER_ADVERTISE_PORT}" > $CLUSTER_DIR/manager-ip

echo "Done k8s master node"
