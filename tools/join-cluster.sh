#!/bin/bash
APISERVER_ADVERTISE_PORT=6443
CERT_SANS=
CLOUD_PROVIDER=
CLUSTER_DIR=/etc/cluster
CLUSTER_DNS="10.96.0.10"
CLUSTER_NODES=()
CNI_PLUGIN=flannel
CONTROL_PLANE_ENDPOINT_ADDR=
CONTROL_PLANE_ENDPOINT=
ETCD_ENDPOINT=
EXTERNAL_ETCD=NO
USE_ETC_HOSTS=true
CONTROL_PLANE=false
INSTANCEID=
INSTANCENAME=${HOSTNAME}
KUBEADM_CONFIG=/etc/kubernetes/kubeadm-config.yaml
KUBERNETES_DISTRO=kubeadm
KUBERNETES_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
MASTER_IP=$(cat ./cluster/manager-ip)
MASTER_NODE_ALLOW_DEPLOYMENT=NO
MAX_PODS=110
PRIVATE_NET_INF=$(ip route get 1|awk '{print $5;exit}')
NODEGROUP_NAME=
NODEINDEX=0
NODENAME=${HOSTNAME}
POD_NETWORK_CIDR="10.244.0.0/16"
REGION=home
SERVICE_NETWORK_CIDR="10.96.0.0/12"
TOKEN=$(cat ./cluster/token)
ZONEID=office
USE_LOADBALANCER=NO

OPTIONS=(
	"allow-deployment:"
	"cloud-provider:"
	"cluster-nodes:"
	"cni-plugin:"
	"container-runtime:"
	"control-plane-endpoint:"
	"control-plane:"
	"etcd-endpoint:"
	"join-master:"
	"kube-engine:"
	"kube-version:"
	"max-pods:"
	"net-if:"
	"node-group:"
	"node-index:"
	"plateform:"
	"region:"
	"tls-san:"
	"trace use-etc-hosts:"
	"use-external-etcd:"
	"use-load-balancer:"
	"vm-uuid:"
	"zone:"
)

PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o i:g:k:c:n:r:x --long "${PARAMS}" -n "$0" -- "$@")

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
	-g|--node-group)
		NODEGROUP_NAME="$2"
		shift 2
		;;
	-i|--node-index)
		NODEINDEX="$2"
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
	--control-plane)
		CONTROL_PLANE=$2
		shift 2
		;;
	--use-external-etcd)
		EXTERNAL_ETCD=$2
		shift 2
		;;
	--max-pods)
		MAX_PODS="$2"
		shift 2
		;;
	--etcd-endpoint)
		ETCD_ENDPOINT="$2"
		shift 2
		;;
	--join-master)
		MASTER_IP=$2
		shift 2
		;;
	--cni-plugin)
		CNI_PLUGIN=$2
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
	-n|--cluster-nodes)
		IFS=, read -a CLUSTER_NODES <<< "$2"
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
				CONTAINER_ENGINE="$2"
				CONTAINER_RUNTIME=remote
				CONTAINER_CTL=unix:///run/containerd/containerd.sock
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
	--use-load-balancer)
		USE_LOADBALANCER="$2"
		shift 2
		;;
# Plateform specific
	-c|--control-plane-endpoint)
		IFS=: read CONTROL_PLANE_ENDPOINT CONTROL_PLANE_ENDPOINT_ADDR <<< "$2"
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
	--vm-uuid)
		INSTANCEID=$2
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

IFS=: read JOIN_MASTER_IP JOIN_MASTER_PORT <<< "${MASTER_IP}"

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

if [ ${PLATEFORM} == "aws" ]; then
	LOCALHOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
	INSTANCEID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
	ZONEID=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
	REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
	INSTANCENAME=$(aws ec2  describe-instances --region ${REGION} --instance-ids ${INSTANCEID} | jq -r '.Reservations[0].Instances[0].Tags[]|select(.Key == "Name")|.Value')
	APISERVER_ADVERTISE_ADDRESS=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
	PROVIDERID=aws://${ZONEID}/${INSTANCEID}
else
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
	sed -i "/${CONTROL_PLANE_ENDPOINT}/d" /etc/hosts
	echo "${CONTROL_PLANE_ENDPOINT_ADDR%%,*}   ${CONTROL_PLANE_ENDPOINT}" >> /etc/hosts

	for CLUSTER_NODE in ${CLUSTER_NODES[@]}
	do
		IFS=: read HOST IP <<< "${CLUSTER_NODE}"
		if [ -n "${IP}" ]; then
			sed -i "/${HOST}/d" /etc/hosts
			echo "${IP}   ${HOST}" >> /etc/hosts
		fi
	done
fi

# Hack because k3s and rke2 1.28.4 don't set the good feature gates
if [ "${DELETE_CREDENTIALS_CONFIG}" == "YES" ]; then
	case "${KUBERNETES_DISTRO}" in
		k3s|rke2)
			rm -rf /var/lib/rancher/credentialprovider
			;;
	esac
fi

mkdir -p /etc/kubernetes/pki/etcd

cp cluster/config /etc/kubernetes/admin.conf

export KUBECONFIG=/etc/kubernetes/admin.conf

SUDO_HOME=$(eval echo ~${SUDO_USER})

mkdir -p ${SUDO_HOME}/.kube
cp ${KUBECONFIG} ${SUDO_HOME}/.kube/config
chown ${SUDO_UID}:${SUDO_GID} ${SUDO_HOME}/.kube/config

if [ ${KUBERNETES_DISTRO} == "microk8s" ]; then
	IFS=. read VERSION MAJOR MINOR <<< "${KUBERNETES_VERSION}"
	MICROK8S_CHANNEL="${VERSION:1}.${MAJOR}/stable"
	MICROK8S_CONFIG=/var/snap/microk8s/common/.microk8s.yaml
	APISERVER_ADVERTISE_PORT=16443
	ANNOTE_MASTER=true

	mkdir -p /var/snap/microk8s/common/

	cat >  ${MICROK8S_CONFIG} <<EOF
version: 0.1.0
persistentClusterToken: ${TOKEN}
extraKubeletArgs:
  --max-pods: ${MAX_PODS}
  --node-ip: ${APISERVER_ADVERTISE_ADDRESS}
EOF

	if [ -n "${CLOUD_PROVIDER}" ]; then
		echo "  --cloud-provider: ${CLOUD_PROVIDER}" >> ${MICROK8S_CONFIG}
	fi

	if [ -f /etc/kubernetes/credential.yaml ]; then
		echo "  --image-credential-provider-config: /etc/kubernetes/credential.yaml" >> ${MICROK8S_CONFIG}
		echo "  --image-credential-provider-bin-dir: /usr/local/bin" >> ${MICROK8S_CONFIG}
	fi

	if [ "${CONTROL_PLANE}" = "true" ]; then
		echo "join:" >> ${MICROK8S_CONFIG}
		echo "  url: ${JOIN_MASTER_IP}:25000/${TOKEN}" >> ${MICROK8S_CONFIG}

		echo "addons:" >> ${MICROK8S_CONFIG}
		echo "  - name: dns" >> ${MICROK8S_CONFIG}
		echo "  - name: rbac" >> ${MICROK8S_CONFIG}
		echo "  - name: ha-cluster" >> ${MICROK8S_CONFIG}

		echo "extraKubeAPIServerArgs:" >> ${MICROK8S_CONFIG}
		echo "  --advertise-address: ${APISERVER_ADVERTISE_ADDRESS}" >> ${MICROK8S_CONFIG}
		echo "  --authorization-mode: RBAC,Node" >> ${MICROK8S_CONFIG}

		if [ "${EXTERNAL_ETCD}" == "true" ]; then
			echo "  --etcd-servers: ${ETCD_ENDPOINT}" >> ${MICROK8S_CONFIG}
			echo "  --etcd-cafile: /etc/etcd/ssl/ca.pem" >> ${MICROK8S_CONFIG}
			echo "  --etcd-certfile: /etc/etcd/ssl/etcd.pem" >> ${MICROK8S_CONFIG}
			echo "  --etcd-keyfile: /etc/etcd/ssl/etcd-key.pem" >> ${MICROK8S_CONFIG}
		fi

		echo "extraSANs:" >> ${MICROK8S_CONFIG}
		
		for CERT_SAN in $(echo -n ${CERT_SANS} | tr ',' ' ')
		do
			echo "  - ${CERT_SAN}" >>  ${MICROK8S_CONFIG}
		done

	else
		if [ ${USE_LOADBALANCER} = "true" ]; then
			echo 'extraMicroK8sAPIServerProxyArgs:' >> ${MICROK8S_CONFIG}
			echo '  --refresh-interval: "0"' >> ${MICROK8S_CONFIG}
			echo '  --traefik-config: /usr/local/etc/microk8s/traefik.yaml' >> ${MICROK8S_CONFIG}

			mkdir -p /usr/local/etc/microk8s

			cat > /usr/local/etc/microk8s/traefik.yaml <<EOF
entryPoints:
  apiserver:
    address: ':${JOIN_MASTER_PORT}'
providers:
  file:
    filename: /usr/local/etc/microk8s/provider.yaml
    watch: true
EOF

			cat > /usr/local/etc/microk8s/provider.yaml <<EOF
tcp:
  routers:
    Router-1:
      rule: HostSNI(\`*\`)
      service: kube-apiserver
      tls:
        passthrough: true
  services:
    kube-apiserver:
      loadBalancer:
        servers:
        - address: ${CONTROL_PLANE_ENDPOINT}:${JOIN_MASTER_PORT}
EOF
		fi


		echo "join:" >> ${MICROK8S_CONFIG}
		echo "  url: ${CONTROL_PLANE_ENDPOINT}:25000/${TOKEN}" >> ${MICROK8S_CONFIG}
		echo "  worker: true" >> ${MICROK8S_CONFIG}
	fi

	cat ${MICROK8S_CONFIG}

	echo "Install microk8s ${MICROK8S_CHANNEL}"
	snap install microk8s --classic --channel=${MICROK8S_CHANNEL}

	if [ "${CONTROL_PLANE}" = "true" ]; then
		echo "Wait microk8s get ready"
		microk8s status --wait-ready -t 120
	fi

elif [ ${KUBERNETES_DISTRO} == "rke2" ]; then
	ANNOTE_MASTER=true
	RKE2_SERVICE=rke2-agent

	if [ "${CONTROL_PLANE}" = "true" ]; then
		RKE2_ENDPOINT=${JOIN_MASTER_IP}
	else
		RKE2_ENDPOINT=${CONTROL_PLANE_ENDPOINT}
	fi

	if [ $"{CLOUD_PROVIDER}" == "external" ]; then
		cat > /etc/rancher/rke2/config.yaml <<EOF
kubelet-arg:
  - cloud-provider=external
  - fail-swap-on=false
  - provider-id=${PROVIDERID}
  - max-pods=${MAX_PODS}
node-name: ${NODENAME}
server: https://${RKE2_ENDPOINT}:9345
advertise-address: ${APISERVER_ADVERTISE_ADDRESS}
token: ${TOKEN}
EOF
   else   
		cat > /etc/rancher/rke2/config.yaml <<EOF
kubelet-arg:
  - fail-swap-on=false
  - max-pods=${MAX_PODS}
node-name: ${NODENAME}
server: https://${RKE2_ENDPOINT}:9345
advertise-address: ${APISERVER_ADVERTISE_ADDRESS}
token: ${TOKEN}
EOF
	fi

	if [ "${CONTROL_PLANE}" = "true" ]; then
		RKE2_SERVICE=rke2-server

		if [ $"{CLOUD_PROVIDER}" == "external" ]; then   
			echo "disable-cloud-controller: true" >> /etc/rancher/rke2/config.yaml
			echo "cloud-provider-name: external" >> /etc/rancher/rke2/config.yaml
		fi

		echo "disable:" >> /etc/rancher/rke2/config.yaml
		echo "  - servicelb" >> /etc/rancher/rke2/config.yaml
		echo "  - rke2-ingress-nginx" >> /etc/rancher/rke2/config.yaml
		echo "  - rke2-metrics-server" >> /etc/rancher/rke2/config.yaml
		echo "tls-san:" >> /etc/rancher/rke2/config.yaml

		for CERT_SAN in $(echo -n ${CERT_SANS} | tr ',' ' ')
		do
			echo "  - ${CERT_SAN}" >> /etc/rancher/rke2/config.yaml
		done
	fi

	echo -n "Start ${RKE2_SERVICE} service"

	systemctl enable ${RKE2_SERVICE}.service
	systemctl start ${RKE2_SERVICE}.service --no-block

elif [ ${KUBERNETES_DISTRO} == "k3s" ]; then
	ANNOTE_MASTER=true

	K3S_MODE=agent
	K3S_DISABLE_ARGS=""

	if [ "${CONTROL_PLANE}" != "true" ]; then
		K3S_ARGS="--kubelet-arg=max-pods=${MAX_PODS} --node-name=${NODENAME} --server=https://${JOIN_MASTER_IP}:${JOIN_MASTER_PORT} --token=${TOKEN}"
	else
		K3S_ARGS="--kubelet-arg=max-pods=${MAX_PODS} --node-name=${NODENAME} --server=https://${CONTROL_PLANE_ENDPOINT}:${JOIN_MASTER_PORT} --token=${TOKEN}"
	fi

	if [ -n "${PROVIDERID}" ]; then
		K3S_ARGS="${K3S_ARGS} --kubelet-arg=provider-id=${PROVIDERID}"
	fi

	if [ "${CONTROL_PLANE}" = "true" ]; then
        K3S_MODE=server
		K3S_DISABLE_ARGS="--disable=servicelb --disable=traefik --disable=metrics-server"
		K3S_SERVER_ARGS="--tls-san=${CERT_SANS}"

		if [ "${CLOUD_PROVIDER}" == "external" ]; then
			K3S_DISABLE_ARGS="${K3S_DISABLE_ARGS} --disable-cloud-controller"
		fi

		if [ "${EXTERNAL_ETCD}" == "true" ] && [ -n "${ETCD_ENDPOINT}" ]; then
			K3S_SERVER_ARGS="${K3S_SERVER_ARGS} --datastore-endpoint=${ETCD_ENDPOINT} --datastore-cafile=/etc/etcd/ssl/ca.pem --datastore-certfile=/etc/etcd/ssl/etcd.pem --datastore-keyfile=/etc/etcd/ssl/etcd-key.pem"
		fi
	fi

	echo "K3S_MODE=${K3S_MODE}" > /etc/default/k3s
	echo "K3S_ARGS='${K3S_ARGS}'" > /etc/systemd/system/k3s.service.env
	echo "K3S_DISABLE_ARGS='${K3S_DISABLE_ARGS}'" > /etc/systemd/system/k3s.disabled.env
	echo "K3S_SERVER_ARGS='${K3S_SERVER_ARGS}'" > /etc/systemd/system/k3s.server.env

	echo -n "Start k3s service"

	systemctl enable k3s.service
	systemctl start k3s.service --no-block

else
	CACERT=$(cat ./cluster/ca.cert)
	mkdir -p /etc/kubernetes/patches

	# Kubelet argument if credential config exist
	if [ -f /etc/kubernetes/credential.yaml ]; then
		echo "KUBELET_EXTRA_ARGS='--image-credential-provider-config=/etc/kubernetes/credential.yaml --image-credential-provider-bin-dir=/usr/local/bin'" > /etc/default/kubelet
	fi

	cat > /etc/kubernetes/patches/kubeletconfiguration.yaml <<EOF
address: ${APISERVER_ADVERTISE_ADDRESS}
providerID: ${PROVIDERID}
maxPods: ${MAX_PODS}
EOF

	if [ "${CONTROL_PLANE}" = "true" ]; then
		cp cluster/kubernetes/pki/ca.crt /etc/kubernetes/pki
		cp cluster/kubernetes/pki/ca.key /etc/kubernetes/pki
		cp cluster/kubernetes/pki/sa.key /etc/kubernetes/pki
		cp cluster/kubernetes/pki/sa.pub /etc/kubernetes/pki
		cp cluster/kubernetes/pki/front-proxy-ca.key /etc/kubernetes/pki
		cp cluster/kubernetes/pki/front-proxy-ca.crt /etc/kubernetes/pki

		chown -R root:root /etc/kubernetes/pki

		chmod 600 /etc/kubernetes/pki/ca.crt
		chmod 600 /etc/kubernetes/pki/ca.key
		chmod 600 /etc/kubernetes/pki/sa.key
		chmod 600 /etc/kubernetes/pki/sa.pub
		chmod 600 /etc/kubernetes/pki/front-proxy-ca.key
		chmod 600 /etc/kubernetes/pki/front-proxy-ca.crt

		if [ -f cluster/kubernetes/pki/etcd/ca.crt ]; then
			cp cluster/kubernetes/pki/etcd/ca.crt /etc/kubernetes/pki/etcd
			cp cluster/kubernetes/pki/etcd/ca.key /etc/kubernetes/pki/etcd

			chmod 600 /etc/kubernetes/pki/etcd/ca.crt
			chmod 600 /etc/kubernetes/pki/etcd/ca.key
		fi

		kubeadm join ${JOIN_MASTER_IP}:${JOIN_MASTER_PORT} \
			--node-name "${NODENAME}" \
			--token "${TOKEN}" \
			--patches /etc/kubernetes/patches \
			--discovery-token-ca-cert-hash "sha256:${CACERT}" \
			--apiserver-advertise-address ${APISERVER_ADVERTISE_ADDRESS} \
			--control-plane
	else
		kubeadm join ${CONTROL_PLANE_ENDPOINT}:${JOIN_MASTER_PORT} \
			--node-name "${NODENAME}" \
			--token "${TOKEN}" \
			--patches /etc/kubernetes/patches \
			--discovery-token-ca-cert-hash "sha256:${CACERT}"
	fi
fi

wait_node_ready

if [ "${CONTROL_PLANE}" = "true" ]; then
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

	if [ "${MASTER_NODE_ALLOW_DEPLOYMENT}" = "YES" ]; then
		kubectl taint node ${NODENAME} node-role.kubernetes.io/master:NoSchedule- node-role.kubernetes.io/control-plane:NoSchedule-
	elif [ "${KUBERNETES_DISTRO}" == "k3s" ]; then
		kubectl taint node ${NODENAME} node-role.kubernetes.io/master:NoSchedule node-role.kubernetes.io/control-plane:NoSchedule
	fi
else
	kubectl label nodes ${NODENAME} \
		"cluster.autoscaler.nodegroup/name=${NODEGROUP_NAME}" \
		"node-role.kubernetes.io/worker=${ANNOTE_MASTER}" \
		"topology.kubernetes.io/region=${REGION}" \
		"topology.kubernetes.io/zone=${ZONEID}" \
		"topology.csi.vmware.com/k8s-region=${REGION}" \
		"topology.csi.vmware.com/k8s-zone=${ZONEID}" \
		"worker=true" \
		--overwrite
fi

kubectl annotate node ${NODENAME} \
	"cluster.autoscaler.nodegroup/name=${NODEGROUP_NAME}" \
	"cluster.autoscaler.nodegroup/instance-id=${INSTANCEID}" \
	"cluster.autoscaler.nodegroup/instance-name=${INSTANCENAME}" \
	"cluster.autoscaler.nodegroup/node-index=${NODEINDEX}" \
	"cluster.autoscaler.nodegroup/autoprovision=false" \
	"cluster-autoscaler.kubernetes.io/scale-down-disabled=true" \
	--overwrite
