#!/bin/bash

if [ -z "${NFS_SERVER_ADDRESS}" ] && [ -z "${NFS_SERVER_PATH}" ]; then
	echo "Ignore nfs provisionner"
else
	export KUBERNETES_TEMPLATE=./templates/csi-nfs-provisioner
	export ETC_DIR=${TARGET_DEPLOY_LOCATION}/csi-nfs-provisioner

	mkdir -p ${ETC_DIR}

	helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
	helm repo update

	helm upgrade -i --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -n kube-system \
		csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
		--set-string controller.nodeSelector."node-role\.kubernetes\.io/control-plane"="${ANNOTE_MASTER}"

cat > ${ETC_DIR}/csi-nfs-provisioner.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${NFS_STORAGE_CLASS}
provisioner: nfs.csi.k8s.io
parameters:
  server: ${NFS_SERVER_ADDRESS}
  share: ${NFS_SERVER_PATH}
  # csi.storage.k8s.io/provisioner-secret is only needed for providing mountOptions in DeleteVolume
  # csi.storage.k8s.io/provisioner-secret-name: "mount-options"
  # csi.storage.k8s.io/provisioner-secret-namespace: "default"
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=4.1
EOF

	kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f ${ETC_DIR}/csi-nfs-provisioner.yaml

#	helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
#	helm repo update


#	helm upgrade -i --kubeconfig=${TARGET_CLUSTER_LOCATION}/config  -n kube-system \
#		nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
#		--set storageClass.name=${NFS_STORAGE_CLASS} \
#		--set storageClass.archiveOnDelete=false \
#		--set storageClass.onDelete=true \
#		--set nfs.server=${NFS_SERVER_ADDRESS} \
#		--set nfs.path=${NFS_SERVER_PATH}
fi