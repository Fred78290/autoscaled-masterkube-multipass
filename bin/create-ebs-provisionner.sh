#!/bin/bash
ETC_DIR=${TARGET_DEPLOY_LOCATION}/aws-ebs-provisioner

mkdir -p ${ETC_DIR}

cat > ${ETC_DIR}/aws-ebs-csi.yaml <<EOF
storageClasses:
 - name: aws-ebs
   annotations:
     storageclass.kubernetes.io/is-default-class: "false"
   volumeBindingMode: WaitForFirstConsumer
   reclaimPolicy: Delete
   parameters:
     encrypted: "false"
   parameters:
     encrypted: "false"
EOF

helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
    --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
    --namespace kube-system \
    -f ${ETC_DIR}/aws-ebs-csi.yaml 
