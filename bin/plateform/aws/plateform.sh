CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl aws"

function wait_instance_status() {
    local INSTANCE_ID=$1
    local STATUS=$2

    while [ ! $(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" | jq -r '.Reservations[0].Instances[0].State.Code') -eq ${STATUS} ];
    do
        sleep 1
    done
}

function delete_instance() {
    local INSTANCE_NAME=$1

    local INSTANCE=$(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=tag:Name,Values=$INSTANCE_NAME" | jq -r '.Reservations[].Instances[]|select(.State.Code == 16)')
    local INSTANCE_ID=$(echo $INSTANCE | jq -r '.InstanceId // ""')

    if [ -n "$INSTANCE_ID" ]; then
        echo_blue_bold "Delete VM: $MASTERKUBE_NODE"
        delete_instance_id "${INSTANCE_ID}" &
    fi

    aws ec2 stop-instances --force --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" &>/dev/null

    wait_instance_status $INSTANCE_ID 80

    aws ec2 terminate-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" &>/dev/null

    wait_instance_status $INSTANCE_ID 48

    echo_blue_bold "Terminated instance: ${INSTANCE_ID}"
}

function delete_vm_by_name() {
    local INSTANCE_NAME=$1
    local INSTANCE=$(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=tag:Name,Values=$INSTANCE_NAME" | jq -r '.Reservations[].Instances[]|select(.State.Code == 16)')
    local INSTANCE_ID=$(echo $INSTANCE | jq -r '.InstanceId // ""')

    if [ -n "$INSTANCE_ID" ]; then
        echo_blue_bold "Delete VM: $MASTERKUBE_NODE"
        delete_instance_id "${INSTANCE_ID}" &
    fi
}

function unregister_dns() {
    ./bin/delete-aws-nlb.sh --profile ${AWS_PROFILE} --region ${AWS_REGION} --name ${MASTERKUBE}

    # Delete DNS entries
    for FILE in ${TARGET_CONFIG_LOCATION}/dns-*.json
    do
        if [ -f $FILE ]; then
            DNS=$(cat $FILE | jq '.Changes[0].Action = "DELETE"')
            DNSNAME=$(echo $DNS | jq -r '.Changes[0].ResourceRecordSet.Name')

            echo $DNS | jq . > $FILE

            echo_blue_bold "Delete DNS entry: ${DNSNAME}"
            if [[ "${DNSNAME}" == *.${PUBLIC_DOMAIN_NAME} ]]; then
                ZONEID=${AWS_ROUTE53_PUBLIC_ZONE_ID}
            else
                ZONEID=${AWS_ROUTE53_ZONE_ID}
            fi

            aws route53 change-resource-record-sets --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} \
                --hosted-zone-id ${ZONEID} \
                --change-batch file://${FILE} &> /dev/null
            delete_host "${DNSNAME}"
        fi
    done

    # Delete ENI entries
    for FILE in ${TARGET_CONFIG_LOCATION}/eni-*.json
    do
        if [ -f $FILE ]; then
            ENI=$(cat $FILE | jq -r '.NetworkInterfaceId')
            echo_blue_bold "Delete ENI: ${ENI}"
            aws ec2 delete-network-interface --profile ${AWS_PROFILE} --region ${AWS_REGION} --network-interface-id ${ENI} &> /dev/null
        fi
    done

    if [ -n "${GODADDY_API_KEY}" ] && [ -n "${PUBLIC_DOMAIN_NAME}" ] && [ -z "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then
        echo_blue_bold "Delete DNS ${MASTERKUBE} in godaddy"

        if [ "${USE_NLB}" = "YES" ]; then
            curl -s -X DELETE -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/CNAME/${MASTERKUBE}" > /dev/null
        else
            curl -s -X DELETE -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/A/${MASTERKUBE}" > /dev/null
        fi

        echo_blue_bold "Delete DNS ${DASHBOARD_HOSTNAME} in godaddy"
        curl -s -X DELETE -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/CNAME/${DASHBOARD_HOSTNAME}" > /dev/null

        echo_blue_bold "Delete DNS helloworld-aws in godaddy"
        curl -s -X DELETE -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/CNAME/helloworld-aws" > /dev/null
    fi
}

function update_build_env() {
cat ${PLATEFORMDEFS} > ${TARGET_CONFIG_LOCATION}/buildenv

cat > ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
export AUTOSCALE_MACHINE=${AUTOSCALE_MACHINE}
export AWS_ROUTE53_ACCESSKEY=${AWS_ROUTE53_ACCESSKEY}
export AWS_ROUTE53_PUBLIC_ZONE_ID=${AWS_ROUTE53_PUBLIC_ZONE_ID}
export AWS_ROUTE53_SECRETKEY=${AWS_ROUTE53_SECRETKEY}
export CLOUDPROVIDER_CONFIG=${CLOUDPROVIDER_CONFIG}
export CLUSTER_NODES=${CLUSTER_NODES}
export CNI_PLUGIN=${CNI_PLUGIN}
export CNI_VERSION=${CNI_VERSION}
export CONTROL_PLANE_MACHINE=${CONTROL_PLANE_MACHINE}
export CONTROLNODES=${CONTROLNODES}
export CONTROLPLANE_USE_PUBLICIP=${CONTROLPLANE_USE_PUBLICIP}
export CORESTOTAL="${CORESTOTAL}"
export DASHBOARD_HOSTNAME=${DASHBOARD_HOSTNAME}
export DOMAIN_NAME=${DOMAIN_NAME}
export EXPOSE_PUBLIC_CLUSTER=${EXPOSE_PUBLIC_CLUSTER}
export EXTERNAL_ETCD=${EXTERNAL_ETCD}
export FIRSTNODE=${FIRSTNODE}
export GODADDY_API_KEY=${GODADDY_API_KEY}
export GODADDY_API_SECRET=${GODADDY_API_SECRET}
export GRPC_PROVIDER=${GRPC_PROVIDER}
export HA_CLUSTER=${HA_CLUSTER}
export KUBECONFIG=${KUBECONFIG}
export KUBERNETES_DISTRO=${KUBERNETES_DISTRO}
export KUBERNETES_USER=${KUBERNETES_USER}
export KUBERNETES_VERSION=${KUBERNETES_VERSION}
export LAUNCH_CA=${LAUNCH_CA}
export MASTER_INSTANCE_PROFILE_ARN=${MASTER_INSTANCE_PROFILE_ARN}
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
export PREFER_SSH_PUBLICIP=${PREFER_SSH_PUBLICIP}
export PRIVATE_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}
export PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
export REGISTRY=${REGISTRY}
export ROOT_IMG_NAME=${ROOT_IMG_NAME}
export SCALEDOWNDELAYAFTERADD=${SCALEDOWNDELAYAFTERADD}
export SCALEDOWNDELAYAFTERDELETE=${SCALEDOWNDELAYAFTERDELETE}
export SCALEDOWNDELAYAFTERFAILURE=${SCALEDOWNDELAYAFTERFAILURE}
export SCALEDOWNENABLED=${SCALEDOWNENABLED}
export SCALEDOWNUNEEDEDTIME=${SCALEDOWNUNEEDEDTIME}
export SCALEDOWNUNREADYTIME=${SCALEDOWNUNREADYTIME}
export PLATEFORM=${PLATEFORM}
export SEED_ARCH=${SEED_ARCH}
export SEED_IMAGE_AMD64=${SEED_IMAGE_AMD64}
export SEED_IMAGE_ARM64=${SEED_IMAGE_ARM64}
export SSH_KEYNAME=${SSH_KEYNAME}
export SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}
export SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY}
export SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}
export SSL_LOCATION=${SSL_LOCATION}
export TARGET_CLUSTER_LOCATION=${TARGET_CLUSTER_LOCATION}
export TARGET_CONFIG_LOCATION=${TARGET_CONFIG_LOCATION}
export TARGET_DEPLOY_LOCATION=${TARGET_DEPLOY_LOCATION}
export TARGET_IMAGE=${TARGET_IMAGE}
export TRANSPORT=${TRANSPORT}
export UNREMOVABLENODERECHECKTIMEOUT=${UNREMOVABLENODERECHECKTIMEOUT}
export USE_NGINX_GATEWAY=${USE_NGINX_GATEWAY}
export USE_NLB=${USE_NLB}
export USE_ZEROSSL=${USE_ZEROSSL}
export VOLUME_SIZE=${VOLUME_SIZE}
export VOLUME_TYPE=${VOLUME_TYPE}
export WORKER_INSTANCE_PROFILE_ARN=${WORKER_INSTANCE_PROFILE_ARN}
export WORKER_NODE_MACHINE=${WORKER_NODE_MACHINE}
export WORKER_PROFILE_NAME=${WORKER_PROFILE_NAME}
export WORKERNODE_USE_PUBLICIP=${WORKERNODE_USE_PUBLICIP}
export WORKERNODES=${WORKERNODES}
export ZEROSSL_EAB_HMAC_SECRET=${ZEROSSL_EAB_HMAC_SECRET}
export ZEROSSL_EAB_KID=${ZEROSSL_EAB_KID}
EOF
}

function update_provider_config() {
    PROVIDER_AUTOSCALER_CONFIG=$(cat ${TARGET_CONFIG_LOCATION}/provider.json)

    echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE "${TARGET_IMAGE_AMI}" '.ami = ${TARGET_IMAGE}' > ${TARGET_CONFIG_LOCATION}/provider.json
}