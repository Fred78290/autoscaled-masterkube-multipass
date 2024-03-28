#!/bin/bash

export KUBERNETES_TEMPLATE=./templates/openstack
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/openstack

OSENV=(
	"OS_AUTH_URL"
	"OS_USERNAME"
	"OS_USERID"
	"OS_PASSWORD"
	"OS_PASSCODE"
	"OS_TENANT_ID"
	"OS_TENANT_NAME"
	"OS_DOMAIN_ID"
	"OS_DOMAIN_NAME"
	"OS_APPLICATION_CREDENTIAL_ID"
	"OS_APPLICATION_CREDENTIAL_NAME"
	"OS_APPLICATION_CREDENTIAL_SECRET"
	"OS_SYSTEM_SCOPE"
	"OS_PROJECT_ID"
	"OS_PROJECT_NAME"
	"OS_CLOUD"
)

echo -n > ${ETC_DIR}/openstack.env

for NAME in ${OSENV[@]}
do
	VALUE=${!NAME}
	if [ -n "${VALUE}" ]; then
		echo "${NAME}=${VALUE}" >> ${ETC_DIR}/openstack.env
	fi
done

cat > ${ETC_DIR}/cloud.conf <<EOF
[Global]
use-clouds=true
cloud=${OS_CLOUD}
EOF

if [ -n "${VC_NETWORK_PUBLIC}" ]; then
	FLOATING_NETWORK_ID=$(openstack network show ${VC_NETWORK_PUBLIC} -f json 2>/dev/null | jq -r '.id // ""')

	cat >> ${ETC_DIR}/cloud.conf <<EOF

[LoadBalancer]
lb-provider=octavia
floating-network-id=${FLOATING_NETWORK_ID}

[Networking]
public-network-name=${VC_NETWORK_PUBLIC}
InternalNetworkName=${VC_NETWORK_PRIVATE}
EOF
fi

cat > ${ETC_DIR}/clouds.yaml <<EOF
clouds:
  ${OS_CLOUD}:
    auth:
      auth_url: ${OS_AUTH_URL}
      username: ${OS_USERNAME}
      password: ${OS_PASSWORD}
      project_id: ${OS_PROJECT_ID}
      project_name: ${OS_PROJECT_NAME}
      user_domain_name: ${OS_USER_DOMAIN_NAME}
    region_name: ${OS_REGION_NAME}
    interface: "public"
    verify: false
    identity_api_version: 3
EOF

for 
kubectl create configmap openstack-env -n kube-system --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-env-file=${ETC_DIR}/openstack.env \
	| tee ${ETC_DIR}/openstack-env | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

kubectl create configmap openstack-cloud-config -n kube-system --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--from-file=${ETC_DIR}/clouds.yaml \
	--from-file=${ETC_DIR}/cloud.conf | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f ${ETC_DIR}/cpi-${NODEGROUP_NAME}-secret.yaml

kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	-f ${KUBERNETES_TEMPLATE}/controller/cloud-controller-manager-role-bindings.yaml

kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	-f ${KUBERNETES_TEMPLATE}/controller/cloud-controller-manager-roles.yaml

cat ${KUBERNETES_TEMPLATE}/openstack-cloud-controller-manager-ds.yaml | sed \
	-e "s/__ANNOTE_MASTER__/${ANNOTE_MASTER}/g" \
	| tee ${ETC_DIR}/controller/openstack-cloud-controller-manager-ds.yaml \
	| kubectl --kubeconfig=${TARGET_CLUSTER_LOCATION}/config apply -f -

kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	-f ${KUBERNETES_TEMPLATE}/cinder-csi/cinder-csi-controllerplugin-rbac.yaml

kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	-f ${KUBERNETES_TEMPLATE}/cinder-csi/cinder-csi-nodeplugin-rbac.yaml

kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	-f ${KUBERNETES_TEMPLATE}/cinder-csi/cinder-csi-controllerplugin.yaml

kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	-f ${KUBERNETES_TEMPLATE}/cinder-csi/cinder-csi-nodeplugin.yaml

kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	-f ${KUBERNETES_TEMPLATE}/cinder-csi/cinder-3csi-driver.yaml
