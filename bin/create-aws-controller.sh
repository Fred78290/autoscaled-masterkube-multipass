#!/bin/bash
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/cloud-provider-aws

mkdir -p ${ETC_DIR}

helm repo add aws-cloud-controller-manager https://kubernetes.github.io/cloud-provider-aws
helm repo update aws-cloud-controller-manager

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | awk -F. '{ print $2 }')

case ${KUBERNETES_MINOR_RELEASE} in
		26)
				AWS_CONTROLLER_VERSION=v1.26.0
				;;
		27)
				AWS_CONTROLLER_VERSION=v1.27.1
				;;
		28)
				AWS_CONTROLLER_VERSION=v1.28.1
				;;
		29)
				AWS_CONTROLLER_VERSION=v1.29.2
				;;
		30)
				AWS_CONTROLLER_VERSION=v1.30.0
				;;
esac


if [ "${KUBERNETES_DISTRO}" == "k3s" ] || [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
	cat > ${ETC_DIR}/aws-cloud-controller.yaml <<EOF
args:
  - --v=2
  - --cloud-provider=aws
  - --configure-cloud-routes=false
image:
  tag: ${AWS_CONTROLLER_VERSION}
nodeSelector:
  node-role.kubernetes.io/control-plane: "true"
EOF
	else
		cat > ${ETC_DIR}/aws-cloud-controller.yaml <<EOF
args:
  - --v=2
  - --cloud-provider=aws
  - --configure-cloud-routes=false
image:
  tag: ${AWS_CONTROLLER_VERSION}
EOF
	fi

helm upgrade aws-cloud-controller-manager aws-cloud-controller-manager/aws-cloud-controller-manager \
		--install \
		-f ${ETC_DIR}/aws-cloud-controller.yaml
		