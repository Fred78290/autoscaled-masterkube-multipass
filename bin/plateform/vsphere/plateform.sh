CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl govc"
VC_NETWORK_PRIVATE="VM Private"
VC_NETWORK_PUBLIC="VM Network"
SEED_ARCH=amd64

if [ "${OSDISTRO}" == "Darwin" ]; then
    VMWAREWM=".vmwarevm"
    PATH=${HOME}/Library/DesktopAutoscalerUtility:${PATH}
else
    VMWAREWM=""
    PATH=${HOME}/.local/vmware:${PATH}
fi

if [ "${GOVC_INSECURE}" == "1" ]; then
	export INSECURE=true
else
	export INSECURE=false
fi

function delete_vm_by_name() {
    local VMNAME=$1

    if [ "$(govc vm.info ${VMNAME} 2>&1)" ]; then
        echo_blue_bold "Delete VM: ${VMNAME}"
        govc vm.power -persist-session=false -s ${VMNAME} || echo_blue_bold "Already power off"
        govc vm.destroy ${VMNAME}
    fi

    delete_host "${VMNAME}"
}

function unregister_dns() {
    echo
}

function update_build_env() {
cat ${PLATEFORMDEFS} > ${TARGET_CONFIG_LOCATION}/buildenv

cat > ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
	cat ${PLATEFORMDEFS} > ${TARGET_CONFIG_LOCATION}/buildenv
	cat > ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
export AUTOSCALE_MACHINE=${AUTOSCALE_MACHINE}
export AUTOSCALER_DESKTOP_UTILITY_ADDR=${AUTOSCALER_DESKTOP_UTILITY_ADDR}
export AUTOSCALER_DESKTOP_UTILITY_CACERT=${AUTOSCALER_DESKTOP_UTILITY_CACERT}
export AUTOSCALER_DESKTOP_UTILITY_CERT=${AUTOSCALER_DESKTOP_UTILITY_CERT}
export AUTOSCALER_DESKTOP_UTILITY_KEY=${AUTOSCALER_DESKTOP_UTILITY_CERT}
export AUTOSCALER_DESKTOP_UTILITY_TLS=${AUTOSCALER_DESKTOP_UTILITY_TLS}
export AWS_ACCESSKEY=${AWS_ACCESSKEY}
export AWS_ROUTE53_ACCESSKEY=${AWS_ROUTE53_ACCESSKEY}
export AWS_ROUTE53_PUBLIC_ZONE_ID=${AWS_ROUTE53_PUBLIC_ZONE_ID}
export AWS_ROUTE53_SECRETKEY=${AWS_ROUTE53_SECRETKEY}
export AWS_SECRETKEY=${AWS_SECRETKEY}
export CERT_GODADDY_API_KEY=${CERT_GODADDY_API_KEY}
export CERT_GODADDY_API_SECRET=${CERT_GODADDY_API_SECRET}
export CERT_ZEROSSL_EAB_HMAC_SECRET=${CERT_ZEROSSL_EAB_HMAC_SECRET}
export CERT_ZEROSSL_EAB_KID=${CERT_ZEROSSL_EAB_KID}
export CLOUD_PROVIDER_CONFIG=${CLOUD_PROVIDER_CONFIG}
export CLOUD_PROVIDER=${CLOUD_PROVIDER}
export CNI_PLUGIN=${CNI_PLUGIN}
export CNI_VERSION=${CNI_VERSION}
export CONFIGURATION_LOCATION=${CONFIGURATION_LOCATION}
export CONTAINER_ENGINE=${CONTAINER_ENGINE}
export CONTROL_PLANE_MACHINE=${CONTROL_PLANE_MACHINE}
export CONTROLNODES=${CONTROLNODES}
export CORESTOTAL="${CORESTOTAL}"
export DELETE_CREDENTIALS_CONFIG=${DELETE_CREDENTIALS_CONFIG}
export DOMAIN_NAME=${DOMAIN_NAME}
export EXTERNAL_ETCD=${EXTERNAL_ETCD}
export FIRSTNODE=${FIRSTNODE}
export GRPC_PROVIDER=${GRPC_PROVIDER}
export HA_CLUSTER=${HA_CLUSTER}
export KUBECONFIG=${KUBECONFIG}
export KUBERNETES_DISTRO=${KUBERNETES_DISTRO}
export KUBERNETES_PASSWORD=${KUBERNETES_PASSWORD}
export KUBERNETES_USER=${KUBERNETES_USER}
export KUBERNETES_VERSION=${KUBERNETES_VERSION}
export LAUNCH_CA=${LAUNCH_CA}
export LOAD_BALANCER_PORT=${LOAD_BALANCER_PORT}
export MASTER_NODE_ALLOW_DEPLOYMENT=${MASTER_NODE_ALLOW_DEPLOYMENT}
export MASTERKUBE="${MASTERKUBE}"
export MAXAUTOPROVISIONNEDNODEGROUPCOUNT=${MAXAUTOPROVISIONNEDNODEGROUPCOUNT}
export MAXNODES=${MAXNODES}
export MAXTOTALNODES=${MAXTOTALNODES}
export MEMORYTOTAL="${MEMORYTOTAL}"
export METALLB_IP_RANGE=${METALLB_IP_RANGE}
export MINNODES=${MINNODES}
export NET_DNS=${NET_DNS}
export NET_DOMAIN=${NET_DOMAIN}
export NET_GATEWAY=${NET_GATEWAY}
export NET_IF=${NET_IF}
export NET_IP=${NET_IP}
export NET_MASK_CIDR=${NET_MASK_CIDR}
export NET_MASK=${NET_MASK}
export NETWORK_PRIVATE_ROUTES=(${NETWORK_PRIVATE_ROUTES[@]})
export NETWORK_PUBLIC_ROUTES=(${NETWORK_PUBLIC_ROUTES})
export NFS_SERVER_ADDRESS=${NFS_SERVER_ADDRESS}
export NFS_SERVER_PATH=${NFS_SERVER_PATH}
export NFS_STORAGE_CLASS=${NFS_STORAGE_CLASS}
export NGINX_MACHINE=${NGINX_MACHINE}
export NODEGROUP_NAME="${NODEGROUP_NAME}"
export OSDISTRO=${OSDISTRO}
export PLATEFORM="${PLATEFORM}"
export PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
export PUBLIC_IP="${PUBLIC_IP}"
export REGION=${REGION}
export REGISTRY=${REGISTRY}
export RESUME=${RESUME}
export ROOT_IMG_NAME=${ROOT_IMG_NAME}
export SCALEDNODES_DHCP=${SCALEDNODES_DHCP}
export SCALEDOWNDELAYAFTERADD=${SCALEDOWNDELAYAFTERADD}
export SCALEDOWNDELAYAFTERDELETE=${SCALEDOWNDELAYAFTERDELETE}
export SCALEDOWNDELAYAFTERFAILURE=${SCALEDOWNDELAYAFTERFAILURE}
export SCALEDOWNENABLED=${SCALEDOWNENABLED}
export SCALEDOWNUNEEDEDTIME=${SCALEDOWNUNEEDEDTIME}
export SCALEDOWNUNREADYTIME=${SCALEDOWNUNREADYTIME}
export SEED_ARCH=${SEED_ARCH}
export SEED_IMAGE="${SEED_IMAGE}"
export SEED_USER=${SEED_USER}
export SILENT="${SILENT}"
export SSH_KEY_FNAME=${SSH_KEY_FNAME}
export SSH_KEY="${SSH_KEY}"
export SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}
export SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}
export SSL_LOCATION=${SSL_LOCATION}
export TARGET_CLUSTER_LOCATION=${TARGET_CLUSTER_LOCATION}
export TARGET_CONFIG_LOCATION=${TARGET_CONFIG_LOCATION}
export TARGET_DEPLOY_LOCATION=${TARGET_DEPLOY_LOCATION}
export TARGET_IMAGE=${TARGET_IMAGE}
export TRANSPORT=${TRANSPORT}
export UNREMOVABLENODERECHECKTIMEOUT=${UNREMOVABLENODERECHECKTIMEOUT}
export UPGRADE_CLUSTER=${UPGRADE_CLUSTER}
export USE_DHCP_ROUTES_PRIVATE=${USE_DHCP_ROUTES_PRIVATE}
export USE_DHCP_ROUTES_PUBLIC=${USE_DHCP_ROUTES_PUBLIC}
export USE_KEEPALIVED=${USE_KEEPALIVED}
export USE_ZEROSSL=${USE_ZEROSSL}
export VC_NETWORK_PRIVATE=${VC_NETWORK_PRIVATE}
export VC_NETWORK_PUBLIC=${VC_NETWORK_PUBLIC}
export WORKERNODES=${WORKERNODES}
export ZONEID=${ZONEID}
EOF
}

function update_provider_config() {
    PROVIDER_AUTOSCALER_CONFIG=$(cat ${TARGET_CONFIG_LOCATION}/provider.json)

    echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE "${TARGET_IMAGE}" '.template-name = $TARGET_IMAGE' > ${TARGET_CONFIG_LOCATION}/provider.json
}

function get_vmuuid() {
    local VMNAME=$1

    echo -n $(govc vm.info -json ${VMNAME} 2>/dev/null | jq -r '.virtualMachines[0].config.uuid//""')
}

function get_net_type() {
    echo -n "custom"
}