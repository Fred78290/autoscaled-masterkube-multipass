CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl aws"
CNI_PLUGIN=aws
ACM_CERTIFICATE_FORCE=NO

AUTOSCALE_MACHINE="t3a.medium"
CONTROL_PLANE_MACHINE="t3a.medium"
NGINX_MACHINE="t3a.small"
WORKER_NODE_MACHINE="t3a.medium"

SEED_IMAGE_AMD64="ami-0333305f9719618c7"
SEED_IMAGE_ARM64="ami-03d568a0c334477dd"

function wait_instance_status() {
    local INSTANCE_ID=$1
    local STATUS=$2

    while [ ! $(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" | jq -r '.Reservations[0].Instances[0].State.Code') -eq ${STATUS} ];
    do
        sleep 1
    done
}

function delete_instance_id() {
    local INSTANCE_ID=$1

    aws ec2 stop-instances --force --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" &>/dev/null

    wait_instance_status $INSTANCE_ID 80

    aws ec2 terminate-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" &>/dev/null

    wait_instance_status $INSTANCE_ID 48

    echo_blue_bold "Terminated instance: ${INSTANCE_ID}"
}

function describe_living_instance() {
    aws ec2  describe-instances \
        --profile ${AWS_PROFILE} \
        --region ${AWS_REGION} \
        --filters "Name=tag:Name,Values=$1" \
        | jq -r '.Reservations[].Instances[]|select(.State.Code == 16)'
}

function delete_instance() {
    local INSTANCE_NAME=$1

    local INSTANCE=$(describe_living_instance "${INSTANCE_NAME}")
    local INSTANCE_ID=$(echo ${INSTANCE} | jq -r '.InstanceId // ""')

    if [ -n "${INSTANCE_ID}" ]; then
        echo_blue_bold "Delete VM: ${INSTANCE_NAME}"
        delete_instance_id "${INSTANCE_ID}" &
    fi
}

function delete_vm_by_name() {
    local INSTANCE_NAME=$1
    local INSTANCE=$(describe_living_instance "${INSTANCE_NAME}")
    local INSTANCE_ID=$(echo ${INSTANCE} | jq -r '.InstanceId // ""')

    if [ -n "${INSTANCE_ID}" ]; then
        echo_blue_bold "Delete VM: ${INSTANCE_NAME}"
        delete_instance_id "${INSTANCE_ID}" &
    fi
}

function unregister_dns() {
    ./bin/delete-aws-nlb.sh --profile ${AWS_PROFILE} --region ${AWS_REGION} --name ${MASTERKUBE}

    # Delete DNS entries
    for FILE in ${TARGET_CONFIG_LOCATION}/dns-*.json
    do
        if [ -f ${FILE} ]; then
            DNS=$(cat ${FILE} | jq '.Changes[0].Action = "DELETE"')
            DNSNAME=$(echo ${DNS} | jq -r '.Changes[0].ResourceRecordSet.Name')

            echo ${DNS} | jq . > ${FILE}

            echo_blue_bold "Delete DNS entry: ${DNSNAME}"
            if [[ "${DNSNAME}" == *.${PUBLIC_DOMAIN_NAME} ]]; then
                ZONEID=${AWS_ROUTE53_PUBLIC_ZONE_ID}
            else
                ZONEID=${AWS_ROUTE53_PRIVATE_ZONE_ID}
            fi

            aws route53 change-resource-record-sets \
                --profile ${AWS_PROFILE_ROUTE53} \
                --region ${AWS_REGION} \
                --hosted-zone-id ${ZONEID} \
                --change-batch file://${FILE} &> /dev/null || true
            delete_host "${DNSNAME}"
        fi
    done

    # Delete ENI entries
    for FILE in ${TARGET_CONFIG_LOCATION}/eni-*.json
    do
        if [ -f ${FILE} ]; then
            ENI=$(cat ${FILE} | jq -r '.NetworkInterfaceId')
            echo_blue_bold "Delete ENI: ${ENI}"
            aws ec2 delete-network-interface \
                --profile ${AWS_PROFILE} \
                --region ${AWS_REGION} \
                --network-interface-id ${ENI} &> /dev/null || true
        fi
    done

    if [ -n "${CERT_GODADDY_API_KEY}" ] && [ -n "${PUBLIC_DOMAIN_NAME}" ] && [ -z "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then
        echo_blue_bold "Delete DNS ${MASTERKUBE} in godaddy"

        if [ "${USE_NLB}" = "YES" ]; then
            curl -s -X DELETE -H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
                "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/CNAME/${MASTERKUBE}" > /dev/null
        else
            curl -s -X DELETE -H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
                "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/A/${MASTERKUBE}" > /dev/null
        fi

        echo_blue_bold "Delete DNS ${DASHBOARD_HOSTNAME} in godaddy"
        curl -s -X DELETE -H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
            "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/CNAME/${DASHBOARD_HOSTNAME}" > /dev/null

        echo_blue_bold "Delete DNS helloworld-aws in godaddy"
        curl -s -X DELETE -H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
            "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/CNAME/helloworld-aws" > /dev/null
    fi
}

function update_build_env() {
    set +u
    EVAL=$(cat ${PLATEFORMDEFS} | sed -e '/MASTER_INSTANCE_PROFILE_ARN/d' -e '/WORKER_INSTANCE_PROFILE_ARN/d' > ${TARGET_CONFIG_LOCATION}/buildenv)

cat > ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
export ACM_CERTIFICATE_ARN=${ACM_CERTIFICATE_ARN}
export ACM_DOMAIN_NAME=${ACM_DOMAIN_NAME}
export AUTOSCALE_MACHINE=${AUTOSCALE_MACHINE}
export AUTOSCALER_DESKTOP_UTILITY_ADDR=${AUTOSCALER_DESKTOP_UTILITY_ADDR}
export AUTOSCALER_DESKTOP_UTILITY_CACERT=${AUTOSCALER_DESKTOP_UTILITY_CACERT}
export AUTOSCALER_DESKTOP_UTILITY_CERT=${AUTOSCALER_DESKTOP_UTILITY_CERT}
export AUTOSCALER_DESKTOP_UTILITY_KEY=${AUTOSCALER_DESKTOP_UTILITY_CERT}
export AUTOSCALER_DESKTOP_UTILITY_TLS=${AUTOSCALER_DESKTOP_UTILITY_TLS}
export AWS_ACCESSKEY=${AWS_ACCESSKEY}
export AWS_ROUTE53_ACCESSKEY=${AWS_ROUTE53_ACCESSKEY}
export AWS_ROUTE53_PRIVATE_ZONE_ID=${AWS_ROUTE53_PRIVATE_ZONE_ID}
export AWS_ROUTE53_PUBLIC_ZONE_ID=${AWS_ROUTE53_PUBLIC_ZONE_ID}
export AWS_ROUTE53_SECRETKEY=${AWS_ROUTE53_SECRETKEY}
export AWS_ROUTE53_TOKEN=${AWS_ROUTE53_TOKEN}
export AWS_SECRETKEY=${AWS_SECRETKEY}
export AWS_TOKEN=${AWS_TOKEN}
export CERT_GODADDY_API_KEY=${CERT_GODADDY_API_KEY}
export CERT_GODADDY_API_SECRET=${CERT_GODADDY_API_SECRET}
export CERT_ZEROSSL_EAB_HMAC_SECRET=${CERT_ZEROSSL_EAB_HMAC_SECRET}
export CERT_ZEROSSL_EAB_KID=${CERT_ZEROSSL_EAB_KID}
export CLOUD_PROVIDER_CONFIG=${CLOUD_PROVIDER_CONFIG}
export CLOUD_PROVIDER=${CLOUD_PROVIDER}
export CLUSTER_NODES=${CLUSTER_NODES}
export CNI_PLUGIN=${CNI_PLUGIN}
export CNI_VERSION=${CNI_VERSION}
export CONFIGURATION_LOCATION=${CONFIGURATION_LOCATION}
export CONTAINER_ENGINE=${CONTAINER_ENGINE}
export CONTROL_PLANE_MACHINE=${CONTROL_PLANE_MACHINE}
export CONTROLNODES=${CONTROLNODES}
export CONTROLPLANE_USE_PUBLICIP=${CONTROLPLANE_USE_PUBLICIP}
export CORESTOTAL="${CORESTOTAL}"
export DASHBOARD_HOSTNAME=${DASHBOARD_HOSTNAME}
export DOMAIN_NAME=${DOMAIN_NAME}
export ETCD_DST_DIR=${ETCD_DST_DIR}
export EXPOSE_PUBLIC_CLUSTER=${EXPOSE_PUBLIC_CLUSTER}
export EXTERNAL_ETCD_ARGS=${EXTERNAL_ETCD_ARGS}
export EXTERNAL_ETCD=${EXTERNAL_ETCD}
export FIRSTNODE=${FIRSTNODE}
export GRPC_PROVIDER=${GRPC_PROVIDER}
export HA_CLUSTER=${HA_CLUSTER}
export KUBECONFIG=${KUBECONFIG}
export KUBERNETES_DISTRO=${KUBERNETES_DISTRO}
export KUBERNETES_USER=${KUBERNETES_USER}
export KUBERNETES_VERSION=${KUBERNETES_VERSION}
export LAUNCH_CA=${LAUNCH_CA}
export MASTER_INSTANCE_PROFILE_ARN=${MASTER_INSTANCE_PROFILE_ARN}
export MASTER_NODE_ALLOW_DEPLOYMENT=${MASTER_NODE_ALLOW_DEPLOYMENT}
export MASTER_PROFILE_NAME=${MASTER_PROFILE_NAME}
export MASTERKUBE=${MASTERKUBE}
export MAX_PODS=${MAX_PODS}
export MAXAUTOPROVISIONNEDNODEGROUPCOUNT=${MAXAUTOPROVISIONNEDNODEGROUPCOUNT}
export MAXNODES=${MAXNODES}
export MAXTOTALNODES=${MAXTOTALNODES}
export MEMORYTOTAL="${MEMORYTOTAL}"
export MINNODES=${MINNODES}
export NGINX_MACHINE=${NGINX_MACHINE}
export NODEGROUP_NAME=${NODEGROUP_NAME}
export OSDISTRO=${OSDISTRO}
export PLATEFORM=${PLATEFORM}
export PREFER_SSH_PUBLICIP=${PREFER_SSH_PUBLICIP}
export PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}
export PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
export REGISTRY=${REGISTRY}
export RESUME=${RESUME}
export ROOT_IMG_NAME=${ROOT_IMG_NAME}
export SCALEDOWNDELAYAFTERADD=${SCALEDOWNDELAYAFTERADD}
export SCALEDOWNDELAYAFTERDELETE=${SCALEDOWNDELAYAFTERDELETE}
export SCALEDOWNDELAYAFTERFAILURE=${SCALEDOWNDELAYAFTERFAILURE}
export SCALEDOWNENABLED=${SCALEDOWNENABLED}
export SCALEDOWNUNEEDEDTIME=${SCALEDOWNUNEEDEDTIME}
export SCALEDOWNUNREADYTIME=${SCALEDOWNUNREADYTIME}
export SEED_ARCH=${SEED_ARCH}
export SEED_IMAGE_AMD64=${SEED_IMAGE_AMD64}
export SEED_IMAGE_ARM64=${SEED_IMAGE_ARM64}
export SILENT="${SILENT}"
export SSH_KEYNAME=${SSH_KEYNAME}
export SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}
export SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}
export SSL_LOCATION=${SSL_LOCATION}
export TARGET_CLUSTER_LOCATION=${TARGET_CLUSTER_LOCATION}
export TARGET_CONFIG_LOCATION=${TARGET_CONFIG_LOCATION}
export TARGET_DEPLOY_LOCATION=${TARGET_DEPLOY_LOCATION}
export TARGET_IMAGE_AMI=${TARGET_IMAGE_AMI}
export TARGET_IMAGE=${TARGET_IMAGE}
export TRANSPORT=${TRANSPORT}
export UNREMOVABLENODERECHECKTIMEOUT=${UNREMOVABLENODERECHECKTIMEOUT}
export UPGRADE_CLUSTER=${UPGRADE_CLUSTER}
export USE_NGINX_GATEWAY=${USE_NGINX_GATEWAY}
export USE_NLB=${USE_NLB}
export USE_ZEROSSL=${USE_ZEROSSL}
export VOLUME_SIZE=${VOLUME_SIZE}
export VOLUME_TYPE=${VOLUME_TYPE}
export VPC_PRIVATE_SECURITY_GROUPID=${VPC_PRIVATE_SECURITY_GROUPID}
export VPC_PRIVATE_SUBNET_ID=${VPC_PRIVATE_SUBNET_ID}
export VPC_PUBLIC_SECURITY_GROUPID=${VPC_PUBLIC_SECURITY_GROUPID}
export VPC_PUBLIC_SUBNET_ID=${VPC_PUBLIC_SUBNET_ID}
export WORKER_INSTANCE_PROFILE_ARN=${WORKER_INSTANCE_PROFILE_ARN}
export WORKER_NODE_MACHINE=${WORKER_NODE_MACHINE}
export WORKER_PROFILE_NAME=${WORKER_PROFILE_NAME}
export WORKERNODE_USE_PUBLICIP=${WORKERNODE_USE_PUBLICIP}
export WORKERNODES=${WORKERNODES}
EOF
    set -u
}

function update_provider_config() {
    PROVIDER_AUTOSCALER_CONFIG=$(cat ${TARGET_CONFIG_LOCATION}/provider.json)

    echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE "${TARGET_IMAGE_AMI}" '.ami = $TARGET_IMAGE' > ${TARGET_CONFIG_LOCATION}/provider.json
}