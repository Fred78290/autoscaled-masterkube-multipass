#!/bin/bash
ECR_PASSWORD=
CNI_PLUGIN=
CNI_VERSION=
CONTAINER_ENGINE=
CONTAINER_CTL=
KUBERNETES_VERSION=
KUBERNETES_DISTRO=
PLATEFORM=
ARCH=$([[ "$(uname -m)" =~ arm64|aarch64 ]] && echo -n arm64 || echo -n amd64)

export DEBIAN_FRONTEND=noninteractive

OPTIONS=(
	"container-runtime:"
	"cni-version:"
	"cni-plugin:"
	"ecr-password:"
	"kube-version:"
	"kube-engine:"
	"plateform:"
)

PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
TEMP=$(getopt -o r:c:p:v:d: --long "${PARAMS}"  -n "$0" -- "$@")

eval set -- "${TEMP}"

while true ; do
	#echo "$1=$2"
	case "$1" in
		-r|--container-runtime)
			case "$2" in
				"docker")
					CONTAINER_ENGINE="$2"
					CONTAINER_CTL=docker
					;;
				"cri-o"|"containerd")
					CONTAINER_ENGINE="$2"
					CONTAINER_CTL=crictl
					;;
				*)
					echo "Unsupported container runtime: $2"
					exit 1
					;;
			esac
			shift 2
			;;
		-c|--cni-version)
			CNI_VERSION=$2
			shift 2
			;;
		-p|--cni-plugin)
			CNI_PLUGIN=$2
			shift 2
			;;
		--ecr-password)
			ECR_PASSWORD=$2
			shift 2
			;;
		-v|--kube-version)
			KUBERNETES_VERSION=$2
			shift 2
			;;
		-d|--kube-engine)
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
		--plateform)
			PLATEFORM=$2
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

if [ ! -f /etc/default/grub.d/60-biosdevname.cfg ] && [ "${PLATEFORM}" != "openstack" ] && [ "${PLATEFORM}" != "cloudstack" ] && [ "${PLATEFORM}" != "aws" ]; then
	echo 'GRUB_CMDLINE_LINUX_DEFAULT="\${GRUB_CMDLINE_LINUX_DEFAULT} net.ifnames=0 biosdevname=0"' > /etc/default/grub.d/60-biosdevname.cfg
	update-grub
fi

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | awk -F. '{ print $2 }')
CRIO_VERSION=$(echo -n ${KUBERNETES_VERSION} | tr -d 'v' | awk -F. '{ print $1"."$2 }')

echo "==============================================================================================================================="
echo "= Upgrade ubuntu distro"
echo "==============================================================================================================================="
apt update
apt upgrade -y
echo

if [ "${PLATEFORM}" != "aws" ]; then
	UBUNTU_VERSION_ID=$(cat /etc/os-release | grep VERSION_ID | tr -d '"' | cut -d '=' -f 2)

	if [ -n "$(apt search linux-generic-hwe-${UBUNTU_VERSION_ID} 2>/dev/null | grep linux-generic-hwe-${UBUNTU_VERSION_ID})" ]; then
		echo "==============================================================================================================================="
		echo "= Install linux-generic-hwe-${UBUNTU_VERSION_ID}"
		echo "==============================================================================================================================="

		apt install -y linux-generic-hwe-${UBUNTU_VERSION_ID}
	fi
fi

echo "==============================================================================================================================="
echo "= Install mandatories tools"
echo "==============================================================================================================================="

apt install jq socat conntrack net-tools traceroute nfs-common unzip -y
snap install yq

set -e

echo "==============================================================================================================================="
echo "= Install aws cli"
echo "==============================================================================================================================="

mkdir -p /tmp/aws-install

pushd /tmp/aws-install

if [ "${ARCH}" == "arm64" ];  then
    echo "= Install aws cli arm64"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
    echo "= Install aws cli amd64"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi

unzip awscliv2.zip > /dev/null

./aws/install

popd

rm -rf /tmp/aws-install

mkdir -p /etc/kubernetes

echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.conf
echo "net.bridge.bridge-nf-call-arptables = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

modprobe overlay && echo "overlay" >> /etc/modules || :
modprobe br_netfilter && echo "br_netfilter" >> /etc/modules || :

echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

sysctl --system

case "${KUBERNETES_DISTRO}" in
	k3s|rke2)
		CREDENTIALS_CONFIG_DIR=/var/lib/rancher/credentialprovider
		CREDENTIALS_BIN=/var/lib/rancher/credentialprovider/bin
		;;
	kubeadm|microk8s)
		CREDENTIALS_CONFIG_DIR=/etc/kubernetes
		CREDENTIALS_BIN=/usr/local/bin
		;;
esac

mkdir -p ${CREDENTIALS_CONFIG_DIR}
mkdir -p ${CREDENTIALS_BIN}
mkdir -p /root/.aws

echo "kubernetes ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/kubernetes

curl -sL https://github.com/Fred78290/aws-ecr-credential-provider/releases/download/v1.29.0/ecr-credential-provider-${ARCH} -o ${CREDENTIALS_BIN}/ecr-credential-provider
chmod +x ${CREDENTIALS_BIN}/ecr-credential-provider

if [ "${KUBERNETES_DISTRO}" == "microk8s" ]; then
	echo "==============================================================================================================================="
	echo "= Install kubernetes binaries"
	echo "==============================================================================================================================="

	cd /usr/local/bin
	curl -sL --remote-name-all https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubectl
	chmod +x /usr/local/bin/kube*
elif [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	echo "==============================================================================================================================="
	echo "= Install rke2 binaries"
	echo "==============================================================================================================================="

	curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL="${KUBERNETES_VERSION}" sh -

	pushd /usr/local/bin
	curl -sL --remote-name-all https://dl.k8s.io/release/${KUBERNETES_VERSION%%+*}/bin/linux/${ARCH}/{kubectl,kube-proxy}
	chmod +x /usr/local/bin/kube*
	popd

	mkdir -p /etc/rancher/rke2
	mkdir -p /etc/NetworkManager/conf.d

	cat > /etc/NetworkManager/conf.d/rke2-canal.conf <<"EOF"
[keyfile]
unmanaged-devices=interface-name:cali*;interface-name:flannel*
EOF
	cat > /etc/rancher/rke2/config.yaml <<"EOF"
kubelet-arg:
  - cloud-provider=external
  - fail-swap-on=false
EOF

elif [ "${KUBERNETES_DISTRO}" == "k3s" ]; then
	echo "==============================================================================================================================="
	echo "= Install k3s binaries"
	echo "==============================================================================================================================="

	curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${KUBERNETES_VERSION}" INSTALL_K3S_SKIP_ENABLE=true sh -

	mkdir -p /etc/systemd/system/k3s.service.d
	echo "K3S_MODE=agent" > /etc/default/k3s
	echo "K3S_ARGS=" > /etc/systemd/system/k3s.service.env
	echo "K3S_SERVER_ARGS=" > /etc/systemd/system/k3s.server.env
	echo "K3S_AGENT_ARGS=" > /etc/systemd/system/k3s.agent.env
	echo "K3S_DISABLE_ARGS=" > /etc/systemd/system/k3s.disabled.env

	cat > /etc/systemd/system/k3s.service.d/10-k3s.conf <<"EOF"
[Service]
Environment="KUBELET_ARGS=--kubelet-arg=cloud-provider=external --kubelet-arg=fail-swap-on=false"
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-/etc/systemd/system/k3s.service.env
EnvironmentFile=-/etc/systemd/system/k3s.server.env
EnvironmentFile=-/etc/systemd/system/k3s.agent.env
EnvironmentFile=-/etc/systemd/system/k3s.disabled.env
ExecStart=
ExecStart=/usr/local/bin/k3s $K3S_MODE $K3S_ARGS $K3S_SERVER_ARGS $K3S_AGENT_ARGS $K3S_DISABLE_ARGS $KUBELET_ARGS

EOF

elif [ "${KUBERNETES_DISTRO}" == "kubeadm" ]; then
	echo "prepare kubeadm image"

	function pull_image() {
		local DOCKER_IMAGES=$(curl -s $1 | yq eval -P - | grep "image: " \
			| awk '{print $2}' \
			| sed -e 's/602401143452\.dkr\.ecr\.us-west-2\.amazonaws.com\/amazon\//public.ecr.aws\/eks\//g' -e 's/602401143452\.dkr\.ecr\.us-west-2\.amazonaws.com/public.ecr.aws\/eks/g')
		local USERNAME=$2
		local PASSWORD=$3
		local AUTHENT=

# Use public ecr
#		if [ "${USERNAME}X${PASSWORD}" != "X" ]; then
#			if [ ${CONTAINER_CTL} == crictl ]; then
#				AUTHENT="--creds ${USERNAME}:${PASSWORD}"
#			else
#				${CONTAINER_CTL} login -u ${USERNAME} -p "${PASSWORD}" "602401143452.dkr.ecr.us-west-2.amazonaws.com"
#			fi
#		fi

		for DOCKER_IMAGE in ${DOCKER_IMAGES}
		do
			echo "Pull image ${DOCKER_IMAGE}"
			${CONTAINER_CTL} pull ${AUTHENT} ${DOCKER_IMAGE}
		done
	}

	mkdir -p /etc/systemd/system/kubelet.service.d
	mkdir -p /etc/kubernetes
	mkdir -p /var/lib/kubelet
	mkdir -p /opt/cni/bin
	mkdir -p /usr/local/bin

	. /etc/os-release

	OS=x${NAME}_${VERSION_ID}

	systemctl disable apparmor

	echo "Prepare to install CNI plugins"

	echo "==============================================================================================================================="
	echo "= Install CNI plugins"
	echo "==============================================================================================================================="

	curl -sL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz" | tar -C /opt/cni/bin -xz

	ls -l /opt/cni/bin

	echo

	if [ "${CONTAINER_ENGINE}" = "docker" ]; then

		echo "==============================================================================================================================="
		echo "Install Docker"
		echo "==============================================================================================================================="

		mkdir -p /etc/docker
		mkdir -p /etc/systemd/system/docker.service.d

		curl -s https://get.docker.com | bash

		cat > /etc/docker/daemon.json <<EOF
{
	"exec-opts": [
		"native.cgroupdriver=systemd"
	],
	"log-driver": "json-file",
	"log-opts": {
		"max-size": "100m"
	},
	"storage-driver": "overlay2"
}
EOF

		# Restart docker.
		systemctl daemon-reload
		systemctl restart docker

		usermod -aG docker ubuntu

	elif [ "${CONTAINER_ENGINE}" == "containerd" ]; then

		echo "==============================================================================================================================="
		echo "Install Containerd"
		echo "==============================================================================================================================="

		curl -sL https://github.com/containerd/containerd/releases/download/v1.7.20/cri-containerd-cni-1.7.20-linux-${ARCH}.tar.gz | tar -C / -xz

		mkdir -p /etc/containerd
		containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/g' | tee /etc/containerd/config.toml

		systemctl enable containerd.service
		systemctl restart containerd

		curl -sL https://github.com/containerd/nerdctl/releases/download/v1.7.6/nerdctl-1.7.6-linux-${ARCH}.tar.gz | tar -C /usr/local/bin -xz

	else

		echo "==============================================================================================================================="
		echo "Install CRI-O repositories"
		echo "==============================================================================================================================="

		echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/${CRIO_VERSION}/${OS}/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}.list
		curl -sL https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}/${OS}/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers-cri-o.gpg add -

		apt update
		apt install cri-o cri-o-runc -y
		echo

		mkdir -p /etc/crio/crio.conf.d/

		systemctl daemon-reload
		systemctl enable crio
		systemctl restart crio
	fi

	echo "==============================================================================================================================="
	echo "= Install crictl"
	echo "==============================================================================================================================="
	curl -sL https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRIO_VERSION}.0/crictl-v${CRIO_VERSION}.0-linux-${ARCH}.tar.gz | tar -C /usr/local/bin -xz
	chmod +x /usr/local/bin/crictl

	echo "==============================================================================================================================="
	echo "= Clean ubuntu distro"
	echo "==============================================================================================================================="
	apt-get autoremove -y
	apt-get autoclean -y
	echo

	echo "==============================================================================================================================="
	echo "= Install kubernetes binaries"
	echo "==============================================================================================================================="

	cd /usr/local/bin
	curl -sL --remote-name-all https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/{kubeadm,kubelet,kubectl,kube-proxy}
	chmod +x /usr/local/bin/kube*

	echo

	echo "==============================================================================================================================="
	echo "= Configure kubelet"
	echo "==============================================================================================================================="

	cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=http://kubernetes.io/docs/

[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

	mkdir -p /etc/systemd/system/kubelet.service.d

	cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<"EOF"
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generate at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF

	if [ ${CNI_PLUGIN} = "aws" ]; then
		# Add some EKS init 
		UBUNTU_VERSION_ID=$(cat /etc/os-release | grep VERSION_ID | tr -d '"' | cut -d '=' -f 2 | cut -d '.' -f 1)
		
		# Set NTP server
		if [ -f  /etc/systemd/timesyncd.conf ]; then
			echo "set NTP server"
			sed -i '/^NTP/d' /etc/systemd/timesyncd.conf
			echo "NTP=169.254.169.123" >>/etc/systemd/timesyncd.conf
			timedatectl set-timezone UTC
			systemctl restart systemd-timesyncd.service
		fi

		mkdir -p /etc/eks
		mkdir -p /etc/sysconfig
		curl -s https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/misc/eni-max-pods.txt  | grep -v '#' > /etc/eks/eni-max-pods.txt

		/sbin/iptables-save > /etc/sysconfig/iptables

		# wget https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/iptables-restore.service -O /etc/systemd/system/iptables-restore.service

		cat > /etc/systemd/system/iptables-restore.service <<EOF
[Unit]
Description=Restore iptables
# iptables-restore must start after docker because docker will
# reconfigure iptables to drop forwarded packets.
After=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c "/sbin/iptables-restore < /etc/sysconfig/iptables"

[Install]
WantedBy=multi-user.target
EOF

		sudo systemctl daemon-reload
		sudo systemctl enable iptables-restore

		# https://github.com/aws/amazon-vpc-cni-k8s/issues/2103#issuecomment-1321698870
		if [ ${UBUNTU_VERSION_ID} -ge 22 ]; then
			echo -e "\x1B[90m= \x1B[31m\x1B[1m\x1B[31mWARNING: Patch network for aws with ubuntu 22.x, see issue: https://github.com/aws/amazon-vpc-cni-k8s/issues/2103\x1B[0m\x1B[39m"
			mkdir -p /etc/systemd/network/99-default.link.d/
			cat << EOF > /etc/systemd/network/99-default.link.d/aws-cni-workaround.conf
[Link]
MACAddressPolicy=none
EOF
		fi

		cat >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<"EOF"
# Add iptables enable forwarding
ExecStartPre=/sbin/iptables -P FORWARD ACCEPT -w 5
EOF
	fi

	echo "KUBELET_EXTRA_ARGS=" > /etc/default/kubelet

	echo 'export PATH=/opt/cni/bin:${PATH}' >> /etc/profile.d/apps-bin-path.sh

	echo "==============================================================================================================================="
	echo "= Restart kubelet"
	echo "==============================================================================================================================="

	systemctl enable kubelet
	systemctl restart kubelet

	echo "==============================================================================================================================="
	echo "= Pull kube images"
	echo "==============================================================================================================================="

	/usr/local/bin/kubeadm config images pull --kubernetes-version=${KUBERNETES_VERSION}

	echo "==============================================================================================================================="
	echo "= Pull cni image"
	echo "==============================================================================================================================="

	if [ "${CNI_PLUGIN}" = "aws" ]; then
		AWS_CNI_URL=https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.18.2/config/master/aws-k8s-cni.yaml
		pull_image ${AWS_CNI_URL} AWS ${ECR_PASSWORD}
	elif [ "${CNI_PLUGIN}" = "calico" ]; then
		curl -s -O -L "https://github.com/projectcalico/calico/releases/download/v3.28.0/calicoctl-linux-${ARCH}"
		chmod +x calicoctl-linux-${ARCH}
		mv calicoctl-linux-${ARCH} /usr/local/bin/calicoctl
		pull_image https://docs.projectcalico.org/manifests/calico-vxlan.yaml
	elif [ "${CNI_PLUGIN}" = "flannel" ]; then
		pull_image https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
	elif [ "${CNI_PLUGIN}" = "weave" ]; then
		pull_image "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
	elif [ "${CNI_PLUGIN}" = "canal" ]; then
		pull_image https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/canal.yaml
	elif [ "${CNI_PLUGIN}" = "kube" ]; then
		pull_image https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml
		pull_image https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter-all-features.yaml
	elif [ "${CNI_PLUGIN}" = "romana" ]; then
		pull_image https://raw.githubusercontent.com/romana/romana/master/containerize/specs/romana-kubeadm.yml
	fi
fi

apt upgrade -y
apt autoremove -y

mkdir -p /etc/vmware-tools

cat >> /etc/vmware-tools/tools.conf <<EOF
[guestinfo]
exclude-nics=docker*,veth*,vEthernet*,flannel*,cni*,calico*
primary-nics=eth0
low-priority-nics=eth1,eth2,eth3
EOF

echo "==============================================================================================================================="
echo "= Cleanup"
echo "==============================================================================================================================="

# Delete default cni config from containerd
rm -rf /etc/cni/net.d/*

[ -f /etc/cloud/cloud.cfg.d/50-curtin-networking.cfg ] && rm /etc/cloud/cloud.cfg.d/50-curtin-networking.cfg
rm /etc/netplan/*
cloud-init clean
cloud-init clean -l

rm -rf /etc/apparmor.d/cache/* /etc/apparmor.d/cache/.features
/usr/bin/truncate --size 0 /etc/machine-id
rm -f /snap/README
find /usr/share/netplan -name __pycache__ -exec rm -r {} +
rm -rf /var/cache/pollinate/seeded /var/cache/snapd/* /var/cache/motd-news
rm -rf /var/lib/cloud /var/lib/dbus/machine-id /var/lib/private /var/lib/systemd/timers /var/lib/systemd/timesync /var/lib/systemd/random-seed
rm -f /var/lib/ubuntu-release-upgrader/release-upgrade-available
rm -f /var/lib/update-notifier/fsck-at-reboot /var/lib/update-notifier/hwe-eol
find /var/log -type f -exec rm -f {} +
rm -r /tmp/* /tmp/.*-unix /var/tmp/* /var/lib/apt/*
/bin/sync

