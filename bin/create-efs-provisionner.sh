#!/bin/bash
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/aws-efs-provisioner

if [ -n "${AWS_EFS_DOMAIN}" ]; then
	IFS=. read -a EFSID <<< "${AWS_EFS_DOMAIN}"

	mkdir -p ${ETC_DIR}
cat > ${ETC_DIR}/aws-efs-csi.yaml <<EOF
storageClasses:
 - name: aws-efs
   annotations:
	 storageclass.kubernetes.io/is-default-class: "true"
   mountOptions:
   - tls
   parameters:
	 provisioningMode: efs-ap
	 fileSystemId: ${EFSID[0]}
	 directoryPerms: "700"
	 gidRangeStart: "1000"
	 gidRangeEnd: "2000"
	 basePath: "/${NODEGROUP_NAME}"
   reclaimPolicy: Delete
   volumeBindingMode: Immediate
EOF

	helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver
	helm repo update
	helm upgrade -i aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--namespace kube-system \
		-f ${ETC_DIR}/aws-efs-csi.yaml 

#    helm install stable/efs-provisioner \
#        --set efsProvisioner.efsFileSystemId=${EFSID[0]} \
#        --set efsProvisioner.awsRegion=${AWS_REGION} \
#        --set efsProvisioner.provisionerName=aws-efs \
#        --set efsProvisioner.path=/data \
#        --set podAnnotations."iam.amazonaws.com"=efs-provisioner-role
fi