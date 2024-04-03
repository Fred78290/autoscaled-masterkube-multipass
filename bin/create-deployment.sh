# Recopy config file on master node
EXTERNAL_DNS_TARGET="${MASTERKUBE}.${DOMAIN_NAME}"

mkdir -p ${TARGET_DEPLOY_LOCATION}/configmap
mkdir -p ${TARGET_DEPLOY_LOCATION}/secrets

if [ "${KUBERNETES_DISTRO}" == "microk8s" ] || [ "${KUBERNETES_DISTRO}" == "k3s" ] || [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
  ANNOTE_MASTER=true
fi

kubectl create configmap config-cluster-autoscaler -n kube-system --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-file ${TARGET_CONFIG_LOCATION}/${CLOUD_PROVIDER_CONFIG} \
	--from-file ${TARGET_CONFIG_LOCATION}/provider.json \
	--from-file ${TARGET_CONFIG_LOCATION}/machines.json \
	--from-file ${TARGET_CONFIG_LOCATION}/autoscaler.json \
	| tee ${TARGET_DEPLOY_LOCATION}/configmap/config-cluster-autoscaler.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

kubectl create configmap kubernetes-pki -n kube-system --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-file ${TARGET_CLUSTER_LOCATION}/kubernetes/pki \
	| tee ${TARGET_DEPLOY_LOCATION}/configmap/kubernetes-pki.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

if [ "${EXTERNAL_ETCD}" = "true" ]; then
	kubectl create secret generic etcd-ssl -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-file ${TARGET_CLUSTER_LOCATION}/etcd/ssl \
		| tee ${TARGET_DEPLOY_LOCATION}/secrets/etcd-ssl.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
else
	mkdir -p ${TARGET_CLUSTER_LOCATION}/kubernetes/pki/etcd
	kubectl create secret generic etcd-ssl -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-file ${TARGET_CLUSTER_LOCATION}/kubernetes/pki/etcd \
		| tee ${TARGET_DEPLOY_LOCATION}/secrets/etcd-ssl.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
fi

if [ ${PLATEFORM} == "multipass" ] || [ ${PLATEFORM} == "desktop" ]; then
	kubectl create secret generic autoscaler-utility-cert -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-file $(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientKey) \
		--from-file $(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .ClientCertificate) \
		--from-file $(echo ${AUTOSCALER_DESKTOP_UTILITY_TLS} | jq -r .Certificate) \
		| tee ${TARGET_DEPLOY_LOCATION}/secrets/autoscaler-utility-cert.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
else
	kubectl create secret generic autoscaler-utility-cert -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		| tee ${TARGET_DEPLOY_LOCATION}/secrets/autoscaler-utility-cert.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
fi

if [ "${PLATEFORM}" != "openstack" ]; then
	# Empty configmap for autoscaler deployment
	kubectl create configmap openstack-env -n kube-system \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-literal=OS_CLOUD=

	kubectl create configmap openstack-cloud-config -n kube-system \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--from-literal=clouds.yaml= \
		--from-literal=cloud.conf=
fi

echo_title "Save templates into cluster"

# Save template
kubectl create ns ${NODEGROUP_NAME} --kubeconfig=${TARGET_CLUSTER_LOCATION}/config --dry-run=client -o yaml | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

if [ ${PLATEFORM} == "vsphere" ]; then
	echo_title "Create VSphere CSI provisionner"
	create-vsphere-provisionner.sh
elif [ ${PLATEFORM} == "openstack" ]; then
	echo_title "Create OpenStack controller"
	create-openstack-controller.sh
elif [ ${PLATEFORM} == "aws" ]; then
	echo_title "Create AWS controller"
	create-aws-controller.sh

	echo_title "Create EBS provisionner"
	create-ebs-provisionner.sh

	echo_title "Create EFS provisionner"
	create-efs-provisionner.sh
fi

if [ ${LAUNCH_CA} != "NO" ]; then
	echo_title "Create autoscaler"
	create-autoscaler.sh ${LAUNCH_CA}
fi

if [ "${DEPLOY_COMPONENTS}" == "YES" ]; then
	# Create Pods
	if [ ${PLATEFORM} != "aws" ]; then
		echo_title "Create MetalLB"
		create-metallb.sh

		echo_title "Create NFS provisionner"
		create-nfs-provisionner.sh
	fi

	echo_title "Create CERT Manager"
	create-cert-manager.sh

	echo_title "Create Ingress Controller"
	create-ingress-controller.sh

	echo_title "Create Kubernetes dashboard"
	create-dashboard.sh

	echo_title "Create Kubernetes metric scraper"
	create-metrics.sh

	echo_title "Create Rancher"
	create-rancher.sh

	echo_title "Create Sample hello"
	create-helloworld.sh

	echo_title "Create External DNS"
	create-external-dns.sh

	if [ ${PLATEFORM} != "aws" ]; then
		NGINX_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -o json | jq -r '.status.loadBalancer.ingress[0].ip//""')

		sudo sed -i '' -e "/masterkube-${PLATEFORM}/d" /etc/hosts
		sudo bash -c "echo '${NGINX_IP} masterkube-${PLATEFORM}.${DOMAIN_NAME} ${DASHBOARD_HOSTNAME}.${DOMAIN_NAME}' >> /etc/hosts"
	fi
fi

# Add cluster config in configmap
kubectl create configmap cluster -n ${NODEGROUP_NAME} --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-file ${TARGET_CLUSTER_LOCATION}/ \
	| tee ${TARGET_DEPLOY_LOCATION}/configmap/cluster.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

kubectl create configmap config -n ${NODEGROUP_NAME} --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-file ${TARGET_CONFIG_LOCATION} \
	| tee ${TARGET_DEPLOY_LOCATION}/configmap/config.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

# Save deployment template
pushd ${TARGET_DEPLOY_LOCATION} &>/dev/null
	for DIR in $((ls -1 -d */ 2>/dev/null || true) | tr -d '/')
	do
		kubectl create configmap ${DIR} -n ${NODEGROUP_NAME} --dry-run=client -o yaml \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
			--from-file ${DIR} \
			| tee ${TARGET_DEPLOY_LOCATION}/configmap/${DIR}.yaml \
			| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
	done
popd &>/dev/null
