# Recopy config file on master node
mkdir -p ${TARGET_DEPLOY_LOCATION}/configmap
mkdir -p ${TARGET_DEPLOY_LOCATION}/secrets

if [ "${KUBERNETES_DISTRO}" == "microk8s" ] || [ "${KUBERNETES_DISTRO}" == "k3s" ] || [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
  ANNOTE_MASTER=true
fi

if [ "${USE_BIND9_SERVER}" = "true" ] && [ "${BIND9_RNDCKEY}" != "${TARGET_CLUSTER_LOCATION}/rndc.key" ]; then
	cp ${BIND9_RNDCKEY} ${TARGET_CLUSTER_LOCATION}/rndc.key
else
	touch ${TARGET_CLUSTER_LOCATION}/rndc.key
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
elif [ ${PLATEFORM} == "cloudstack" ]; then
	echo_title "Create CloudStack controller"
	create-cloudstack-controller.sh
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
	if [ ${PLATEFORM} != "aws" ] && [ ${PLATEFORM} != "openstack" ] && [ ${PLATEFORM} != "cloudstack" ]; then
		echo_title "Create MetalLB"
		create-metallb.sh
	fi

	if [ ${PLATEFORM} != "aws" ]; then
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

	echo_title "Create Kubeapps"
	create-kubeapps.sh

	echo_title "Create Sample hello"
	create-helloworld.sh

	echo_title "Create External DNS"
	create-external-dns.sh
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
