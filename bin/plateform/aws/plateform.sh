CMD_MANDATORIES="envsubst helm kubectl jq yq cfssl aws"
CNI_PLUGIN=aws

AUTOSCALE_MACHINE="t3a.medium"
CONTROL_PLANE_MACHINE="t3a.medium"
NGINX_MACHINE="t3a.small"
WORKER_NODE_MACHINE="t3a.medium"
PUBLIC_NODE_IP=NONE

export SEED_IMAGE_AMD64="ami-0c1c30571d2dae5c9"
export SEED_IMAGE_ARM64="ami-0c5789c17ae99a2fa"

export ACM_CERTIFICATE_ARN=
export ACM_CERTIFICATE_FORCE=NO
export ACM_CERTIFICATE_TAGGING=
export CONTROLPLANE_INSTANCEID_NLB_TARGET=
export LAUNCHED_INSTANCES=()
export OVERRIDE_SEED_IMAGE=
export PRIVATE_SUBNET_NLB_TARGET=
export PUBLIC_ADDR_IPS=()
export PUBLIC_SUBNET_NLB_TARGET=
export RESERVED_ADDR_IPS=()
export RESERVED_ENI=()
export TARGET_IMAGE_AMI=

if [ ${SEED_ARCH} == "amd64" ]; then
	AUTOSCALE_MACHINE="t3a.medium"
	CONTROL_PLANE_MACHINE="t3a.medium"
	WORKER_NODE_MACHINE="t3a.medium"
	NGINX_MACHINE="t3a.small"
else
	AUTOSCALE_MACHINE="t4g.medium"
	CONTROL_PLANE_MACHINE="t4g.medium"
	WORKER_NODE_MACHINE="t4g.medium"
	NGINX_MACHINE="t4g.small"
fi

#===========================================================================================================================================
#
#===========================================================================================================================================
function usage() {
	common_usage
	cat <<EOF
### Flags ${PLATEFORM} plateform specific
  # Flags to set AWS informations
--profile | -p=<value>                           # Specify AWS profile, default ${AWS_PROFILE}
--region | -r=<value>                            # Specify AWS region, default ${AWS_REGION}
--route53-profile=<value>                        # Specify AWS profile for route53 if different, default ${AWS_ROUTE53_PROFILE}
--route53-zone-id=<value>                        # Specify Route53 for private DNS, default ${AWS_ROUTE53_PRIVATE_ZONE_ID}

  # Flags to set the template vm
--seed-image=<value>                             # Override the seed image name used to create template, default ${SEED_IMAGE}
--kubernetes-user=<value>                        # Override the seed user in template, default ${KUBERNETES_USER}
--arch=<value>                                   # Specify the architecture of VM (amd64|arm64), default ${SEED_ARCH}
--volume-type=<value>                            # Override the root EBS volume type, default ${VOLUME_TYPE}
--volume-size=<value>                            # Override the root EBS volume size in Gb, default ${VOLUME_SIZE}

  # Flags in ha mode only
--use-nlb                                        # Use AWS NLB as load balancer in public AZ
--create-nginx-apigateway                        # Create NGINX instance to install an apigateway, default ${USE_NGINX_GATEWAY}

  # Flags to configure network in ${PLATEFORM}
--prefer-ssh-publicip                            # Allow to SSH on publicip when available, default ${PREFER_SSH_PUBLICIP}
--internet-facing                                # Expose the cluster on internet, default ${EXPOSE_PUBLIC_CLUSTER}--public-subnet-id=<subnetid,...>                # Specify the public subnet ID for created VM, default ${VPC_PUBLIC_SUBNET_ID}
--public-sg-id=<sg-id>                           # Specify the public security group ID for VM, default ${VPC_PUBLIC_SECURITY_GROUPID}
--private-subnet-id<subnetid,...>                # Specify the private subnet ID for created VM, default ${VPC_PRIVATE_SUBNET_ID}
--private-sg-id=<sg-id>                          # Specify the private security group ID for VM, default ${VPC_PRIVATE_SECURITY_GROUPID}

  # Flags to expose nodes in public AZ with public IP
--control-plane-public                           # Control plane are hosted in public subnet with public IP, default ${CONTROLPLANE_USE_PUBLICIP}
--worker-node-public                             # Worker nodes are hosted in public subnet with public IP, default ${WORKERNODE_USE_PUBLICIP}
EOF
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function parse_arguments() {
    OPTIONS+=(
        "profile:"
        "route53-profile:"
        "region:"
        "public-subnet-id:"
        "public-sg-id:"
        "private-subnet-id:"
        "private-sg-id:"
        "create-nginx-apigatewa"y
        "prefer-ssh-publicip"
        "private-domain:"
        "use-nlb"
        "volume-size:"
        "volume-type:"
        "internet-facing"
        "control-plane-public"
        "worker-node-public"
    )

    PARAMS=$(echo ${OPTIONS[@]} | tr ' ' ',')
    TEMP=$(getopt -o hvxrdk:u:p: --long "${PARAMS}"  -n "$0" -- "$@")

    eval set -- "${TEMP}"

    # extract options and their arguments into variables.
    while true; do
        case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --distribution)
            DISTRO=$2
            SEED_IMAGE="${DISTRO}-server-cloudimg-seed"
            shift 2
            ;;
        --upgrade)
            UPGRADE_CLUSTER=YES
            shift
            ;;
        -v|--verbose)
            VERBOSE=YES
            shift 1
            ;;
        -x|--trace)
            TRACE_ARGS=--trace
            set -x
            shift 1
            ;;
        -r|--resume)
            RESUME=YES
            shift 1
            ;;
        -d|--delete)
            DELETE_CLUSTER=YES
            shift 1
            ;;
        --configuration-location)
            CONFIGURATION_LOCATION=$2
            mkdir -p ${CONFIGURATION_LOCATION}
            if [ ! -d ${CONFIGURATION_LOCATION} ]; then
                echo_red "kubernetes output : ${CONFIGURATION_LOCATION} not found"
                exit 1
            fi
            shift 2
            ;;
        --ssl-location)
            SSL_LOCATION=$2
            if [ ! -d ${SSL_LOCATION} ]; then
                echo_red "etc dir: ${SSL_LOCATION} not found"
                exit 1
            fi
            shift 2
            ;;
        --cert-email)
            CERT_EMAIL=$2
            shift 2
            ;;
        --use-zerossl)
            USE_ZEROSSL=YES
            shift 1
            ;;
        --use-self-signed-ca)
            CERT_SELFSIGNED=YES
            shift 1
            ;;
        --use-cloud-init)
            USE_CLOUDINIT_TO_CONFIGURE=true
            shift 1
            ;;
        --zerossl-eab-kid)
            CERT_ZEROSSL_EAB_KID=$2
            shift 2
            ;;
        --zerossl-eab-hmac-secret)
            CERT_ZEROSSL_EAB_HMAC_SECRET=$2
            shift 2
            ;;
        --godaddy-key)
            CERT_GODADDY_API_KEY=$2
            shift 2
            ;;
        --godaddy-secret)
            CERT_GODADDY_API_SECRET=$2
            shift 2
            ;;
        --route53-zone-id)
            AWS_ROUTE53_PRIVATE_ZONE_ID=$2
            shift 2
            ;;
        --route53-access-key)
            AWS_ROUTE53_ACCESSKEY=$2
            shift 2
            ;;
        --route53-secret-key)
            AWS_ROUTE53_SECRETKEY=$2
            shift 2
            ;;
        --dashboard-hostname)
            DASHBOARD_HOSTNAME=$2
            shift 2
            ;;
        --public-domain)
            PUBLIC_DOMAIN_NAME=$2
            shift 2
            ;;
        --external-dns-provider)
            EXTERNAL_DNS_PROVIDER=$2
            shift 2
            ;;
        --defs)
            PLATEFORMDEFS=$2
            if [ -f ${PLATEFORMDEFS} ]; then
                source ${PLATEFORMDEFS}
            else
                echo_red "${PLATEFORM} definitions: ${PLATEFORMDEFS} not found"
                exit 1
            fi
            shift 2
            ;;
        --create-image-only)
            CREATE_IMAGE_ONLY=YES
            shift 1
            ;;
        --max-pods)
            MAX_PODS=$2
            shift 2
            ;;
        --k8s-distribution)
            case "$2" in
                kubeadm|k3s|rke2|microk8s)
                    KUBERNETES_DISTRO=$2
                    ;;
                *)
                    echo "Unsupported kubernetes distribution: $2"
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        --ha-cluster)
            HA_CLUSTER=true
            shift 1
            ;;
        --create-nginx-apigateway)
            USE_NGINX_GATEWAY=YES
            shift 1
            ;;
        --create-external-etcd)
            EXTERNAL_ETCD=true
            shift 1
            ;;
        --node-group)
            NODEGROUP_NAME="$2"
            MASTERKUBE="${NODEGROUP_NAME}-masterkube"
            shift 2
            ;;
        --container-runtime)
            case "$2" in
                "docker"|"cri-o"|"containerd")
                    CONTAINER_ENGINE="$2"
                    ;;
                *)
                    echo_red_bold "Unsupported container runtime: $2"
                    exit 1
                    ;;
            esac
            shift 2;;
        --arch)
            SEED_ARCH=$2
            shift 2
            ;;
        --seed-image)
            OVERRIDE_SEED_IMAGE="$2"
            shift 2
            ;;
        --nginx-machine)
            NGINX_MACHINE="$2"
            shift 2
            ;;
        --control-plane-machine)
            CONTROL_PLANE_MACHINE="$2"
            shift 2
            ;;
        --worker-node-machine)
            WORKER_NODE_MACHINE="$2"
            shift 2
            ;;
        --autoscale-machine)
            AUTOSCALE_MACHINE="$2"
            shift 2
            ;;
        --ssh-private-key)
            SSH_PRIVATE_KEY=$2
            shift 2
            ;;
        --cni-plugin)
            CNI_PLUGIN="$2"
            shift 2
            ;;
        --cni-version)
            CNI_VERSION="$2"
            shift 2
            ;;
        --transport)
            TRANSPORT="$2"
            shift 2
            ;;
        -k|--kubernetes-version)
            KUBERNETES_VERSION="$2"
			if [ ${KUBERNETES_VERSION:0:1} != "v" ]; then
				KUBERNETES_VERSION="v${KUBERNETES_VERSION}"
			fi
            shift 2
            ;;
        -u|--kubernetes-user)
            KUBERNETES_USER="$2"
            shift 2
            ;;
        -p|--kubernetes-password)
            KUBERNETES_PASSWORD="$2"
            shift 2
            ;;
        --worker-nodes)
            WORKERNODES=$2
            shift 2
            ;;
        # Same argument as cluster-autoscaler
        --cloudprovider)
            GRPC_PROVIDER="$2"
            shift 2
            ;;
        --max-nodes-total)
            MAXTOTALNODES="$2"
            shift 2
            ;;
        --cores-total)
            CORESTOTAL="$2"
            shift 2
            ;;
        --memory-total)
            MEMORYTOTAL="$2"
            shift 2
            ;;
        --max-autoprovisioned-node-group-count)
            MAXAUTOPROVISIONNEDNODEGROUPCOUNT="$2"
            shift 2
            ;;
        --scale-down-enabled)
            SCALEDOWNENABLED="$2"
            shift 2
            ;;
        --scale-down-delay-after-add)
            SCALEDOWNDELAYAFTERADD="$2"
            shift 2
            ;;
        --scale-down-delay-after-delete)
            SCALEDOWNDELAYAFTERDELETE="$2"
            shift 2
            ;;
        --scale-down-delay-after-failure)
            SCALEDOWNDELAYAFTERFAILURE="$2"
            shift 2
            ;;
        --scale-down-utilization-threshold)
            SCALEDOWNUTILIZATIONTHRESHOLD="$2"
            shift 2
            ;;
        --scale-down-gpu-utilization-threshold)
            SCALEDOWNGPUUTILIZATIONTHRESHOLD="$2"
            shift 2
            ;;
        --scale-down-unneeded-time)
            SCALEDOWNUNEEDEDTIME="$2"
            shift 2
            ;;
        --scale-down-unready-time)
            SCALEDOWNUNREADYTIME="$2"
            shift 2
            ;;
        --max-node-provision-time)
            MAXNODEPROVISIONTIME="$2"
            shift 2
            ;;
        --unremovable-node-recheck-timeout)
            UNREMOVABLENODERECHECKTIMEOUT="$2"
            shift 2
            ;;
    ### Plateform specific
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --route53-profile)
            AWS_ROUTE53_PROFILE=$2
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --public-subnet-id)
            VPC_PUBLIC_SUBNET_ID="$2"
            shift 2
            ;;
        --public-sg-id)
            VPC_PUBLIC_SECURITY_GROUPID="$2"
            shift 2
            ;;
        --private-subnet-id)
            VPC_PRIVATE_SUBNET_ID="$2"
            shift 2
            ;;

        --private-sg-id)
            VPC_PRIVATE_SECURITY_GROUPID="$2"
            shift 2
            ;;
        --prefer-ssh-publicip)
            PREFER_SSH_PUBLICIP=YES;
            shift 1
            ;;
        --private-domain)
            PRIVATE_DOMAIN_NAME=$2
            shift 2
            ;;
        --use-nlb)
            USE_NLB=YES
            shift 1
            ;;
        --volume-size)
            VOLUME_SIZE=$2
            shift 2
            ;;
        --volume-type)
            VOLUME_TYPE=$2
            shift 2
            ;;
        --internet-facing)
            EXPOSE_PUBLIC_CLUSTER=true
            shift 1
            ;;
        --control-plane-public)
            CONTROLPLANE_USE_PUBLICIP=true
            shift 1
            ;;
        --worker-node-public)
            WORKERNODE_USE_PUBLICIP=true
            shift 1
            ;;
        --)
            shift
            break
            ;;
        *)
            echo_red "$1 - Internal error!"
            exit 1
            ;;
        esac
    done

    export REGION=${AWS_REGION}
    export AWS_DEFAULT_REGION=${AWS_REGION}
    export ECR_PASSWORD=$(aws ecr get-login-password  --profile ${AWS_PROFILE} --region us-west-2)

    IFS=, read -a VPC_PUBLIC_SUBNET_IDS <<< "${VPC_PUBLIC_SUBNET_ID}"
    IFS=, read -a VPC_PRIVATE_SUBNET_IDS <<< "${VPC_PRIVATE_SUBNET_ID}"

    if [ "${SEED_ARCH}" = "amd64" ]; then
        if [ -z "${OVERRIDE_SEED_IMAGE}" ]; then
            SEED_IMAGE=${SEED_IMAGE_AMD64}
        else
            SEED_IMAGE="${OVERRIDE_SEED_IMAGE}"
        fi
    elif [ "${SEED_ARCH}" = "arm64" ]; then
        if [ -z "${OVERRIDE_SEED_IMAGE}" ]; then
            SEED_IMAGE=${SEED_IMAGE_ARM64}
        else
            SEED_IMAGE="${OVERRIDE_SEED_IMAGE}"
        fi
    else
        echo_red "Unsupported architecture: ${SEED_ARCH}"
        exit -1
    fi

}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_image() {
    TARGET_IMAGE_AMI=$(aws ec2 describe-images --profile ${AWS_PROFILE} --filters "Name=name,Values=${TARGET_IMAGE}" | jq -r '.Images[0].ImageId // ""')

    # If the VM template doesn't exists, build it from scrash
    if [ -z "${TARGET_IMAGE_AMI}" ]; then
        echo_blue_bold "Create aws preconfigured image ${TARGET_IMAGE}"

        if [ "${CONTROLPLANE_USE_PUBLICIP}" == "true" ]; then
            SUBNETID=${VPC_PUBLIC_SUBNET_IDS[0]}
            SGID=${VPC_PUBLIC_SECURITY_GROUPID}
        else
            SUBNETID=${VPC_PRIVATE_SUBNET_IDS[0]}
            SGID=${VPC_PRIVATE_SECURITY_GROUPID}
        fi

        ./bin/create-image.sh \
            --ami="${SEED_IMAGE}" \
            --arch="${SEED_ARCH}" \
            --cni-plugin="${CNI_PLUGIN}" \
            --cni-version="${CNI_VERSION}" \
            --container-runtime=${CONTAINER_ENGINE} \
            --custom-image="${TARGET_IMAGE}" \
            --ecr-password="${ECR_PASSWORD}" \
            --k8s-distribution=${KUBERNETES_DISTRO} \
            --kubernetes-version="${KUBERNETES_VERSION}" \
            --plateform=${PLATEFORM} \
            --profile="${AWS_PROFILE}" \
            --region="${AWS_REGION}" \
            --sg-id="${SGID}" \
            --ssh-key-name="${SSH_KEYNAME}" \
            --subnet-id="${SUBNETID}" \
            --use-public-ip="${CONTROLPLANE_USE_PUBLICIP}" \
            --user="${KUBERNETES_USER}"

    fi

    TARGET_IMAGE_AMI=$(aws ec2 describe-images \
        --profile ${AWS_PROFILE} \
        --filters "Name=name,Values=${TARGET_IMAGE}" | jq -r '.Images[0].ImageId // ""')

    if [ -z "${TARGET_IMAGE_AMI}" ]; then
        echo_red "AMI ${TARGET_IMAGE} not found"
        exit -1
    fi

    if [ "${CREATE_IMAGE_ONLY}" = "YES" ]; then
        echo_blue_bold "Create image only, done..."
        exit 0
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_ssh() {
    KEYEXISTS=$(aws ec2 describe-key-pairs --profile ${AWS_PROFILE} --key-names "${SSH_KEYNAME}" 2> /dev/null | jq -r '.KeyPairs[].KeyName // ""')

    if [ -z ${KEYEXISTS} ]; then
        echo_grey "SSH Public key doesn't exist"
        aws ec2 import-key-pair \
            --profile ${AWS_PROFILE} \
            --key-name ${SSH_KEYNAME} \
            --public-key-material "$(cat ${SSH_PUBLIC_KEY} | base64 -w 0)"
    else
        echo_grey "SSH Public key already exists"
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_plateform() {
    find_public_dns_provider

    # If we use AWS CNI, install eni-max-pods.txt definition file
    if [ ${CNI_PLUGIN} = "aws" ]; then
        MAX_PODS=$(curl -s "https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/eni-max-pods.txt" | grep ^${AUTOSCALE_MACHINE} | awk '{print $2}')

        if [ -z "${MAX_PODS}" ]; then
            echo_red "No entry for ${AUTOSCALE_MACHINE} in eni-max-pods.txt. Not setting ${MAX_PODS} max pods for kubelet"
        fi
    fi

    # If no master instance profile defined, use the default
    if [ -z ${MASTER_INSTANCE_PROFILE_ARN} ]; then
        MASTER_INSTANCE_PROFILE_ARN=$(get_instance_profile ${MASTER_PROFILE_NAME})

        # If not found, create it
        if [ -z ${MASTER_INSTANCE_PROFILE_ARN} ]; then
            MASTER_INSTANCE_PROFILE_ARN=$(create_instance_profile ${MASTER_PROFILE_NAME} \
                kubernetes-master-permissions \
                templates/profile/master/trusted.json \
                templates/profile/master/permissions.json)
        fi
    fi

    # If no worker instance profile defined, use the default
    if [ -z "${WORKER_INSTANCE_PROFILE_ARN}" ]; then
        WORKER_INSTANCE_PROFILE_ARN=$(get_instance_profile ${WORKER_PROFILE_NAME})

        # If not found, create it
        if [ -z "${WORKER_INSTANCE_PROFILE_ARN}" ]; then
            WORKER_INSTANCE_PROFILE_ARN=$(create_instance_profile ${MASTER_PROFILE_NAME} \
                kubernetes-worker-permissions \
                templates/profile/worker/trusted.json \
                templates/profile/worker/permissions.json)
        fi
    fi

    # Grab domain name from route53
    if [ -z "${AWS_ROUTE53_PRIVATE_ZONE_ID}" ]; then
        if [ -n "${PRIVATE_DOMAIN_NAME}" ]; then
            AWS_ROUTE53_PRIVATE_ZONE_ID=$(zoneid_by_name ${PRIVATE_DOMAIN_NAME})

            if [ -n "${AWS_ROUTE53_PRIVATE_ZONE_ID}" ]; then
                echo_blue_bold "AWS_ROUTE53_PRIVATE_ZONE_ID will be set to ${AWS_ROUTE53_PRIVATE_ZONE_ID}"
            elif [ -n "${PUBLIC_DOMAIN_NAME}" ]; then
                echo_blue_bold "AWS_ROUTE53_PRIVATE_ZONE_ID try to be set to ${PUBLIC_DOMAIN_NAME}"
                AWS_ROUTE53_PRIVATE_ZONE_ID=$(zoneid_by_name ${PUBLIC_DOMAIN_NAME})
                PRIVATE_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
            fi

            if [ -z "${AWS_ROUTE53_PRIVATE_ZONE_ID}" ]; then
                echo_red_bold "AWS_ROUTE53_PRIVATE_ZONE_ID is not defined, exit"
                exit 1
            fi
        fi
    else
        ROUTE53_ZONE_NAME=$(aws route53 get-hosted-zone --id  ${AWS_ROUTE53_PRIVATE_ZONE_ID} \
            --profile ${AWS_ROUTE53_PROFILE} 2>/dev/null| jq -r '.HostedZone.Name // ""')

        if [ -z "${ROUTE53_ZONE_NAME}" ]; then
            echo_red_bold "The zone: ${AWS_ROUTE53_PRIVATE_ZONE_ID} does not exist, exit"
            exit 1
        fi

        ROUTE53_ZONE_NAME=${ROUTE53_ZONE_NAME%?}
        FILL_ETC_HOSTS=NO

        # Grab private domain name
        if [ -z "${PRIVATE_DOMAIN_NAME}" ]; then
            if [ -z "${ROUTE53_ZONE_NAME}" ] && [ -z "${PUBLIC_DOMAIN_NAME}" ]; then
                echo_red_bold "PRIVATE_DOMAIN_NAME is not defined, exit"
                exit 1
            fi

            if [ -n "${ROUTE53_ZONE_NAME}" ]; then
                echo_blue_bold "PRIVATE_DOMAIN_NAME will be set to ${ROUTE53_ZONE_NAME}"
                PRIVATE_DOMAIN_NAME=${ROUTE53_ZONE_NAME}
            else
                echo_blue_bold "PRIVATE_DOMAIN_NAME will be set to ${PUBLIC_DOMAIN_NAME}"
                PRIVATE_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
            fi
        fi
    fi

    # Tag VPC & Subnet
    for SUBNET in ${VPC_PUBLIC_SUBNET_IDS[@]}
    do
        TAGGED=$(aws ec2 describe-subnets \
            --profile ${AWS_PROFILE} \
            --filters "Name=subnet-id,Values=${SUBNET}" \
            | jq -r ".Subnets[].Tags[]|select(.Key == \"kubernetes.io/cluster/${NODEGROUP_NAME}\")|.Value")

        if [ -z ${TAGGED} ]; then
            aws ec2 create-tags \
                --profile ${AWS_PROFILE} \
                --resources ${SUBNET} \
                --tags "Key=kubernetes.io/cluster/${NODEGROUP_NAME},Value=owned" 2> /dev/null
        fi

        if [ -z "${PUBLIC_SUBNET_NLB_TARGET}" ]; then
            PUBLIC_SUBNET_NLB_TARGET="${SUBNET}"
        else
            PUBLIC_SUBNET_NLB_TARGET="${PUBLIC_SUBNET_NLB_TARGET},${SUBNET}"
        fi
    done

    if [ ${#VPC_PUBLIC_SUBNET_IDS[@]} = 1 ]; then
        VPC_PUBLIC_SUBNET_IDS+=(${VPC_PUBLIC_SUBNET_IDS[0]} ${VPC_PUBLIC_SUBNET_IDS[0]})
    elif [ ${#VPC_PUBLIC_SUBNET_IDS[@]} = 2 ]; then
        VPC_PUBLIC_SUBNET_IDS+=(${VPC_PUBLIC_SUBNET_IDS[1]})
    fi

    # Tag VPC & Subnet
    for SUBNET in ${VPC_PRIVATE_SUBNET_IDS[@]}
    do
        NETINFO=$(aws ec2 describe-subnets --profile ${AWS_PROFILE} --filters "Name=subnet-id,Values=${SUBNET}")
        TAGGED=$(echo "${NETINFO}" | jq -r ".Subnets[].Tags[]|select(.Key == \"kubernetes.io/cluster/${NODEGROUP_NAME}\")|.Value")
        BASE_IP=$(echo "${NETINFO}" | jq -r .Subnets[].CidrBlock | sed -E 's/(\w+\.\w+\.\w+).\w+\/\w+/\1/')

        if [ -z ${TAGGED} ]; then
            aws ec2 create-tags \
                --profile ${AWS_PROFILE} \
                --resources ${SUBNET} \
                --tags "Key=kubernetes.io/cluster/${NODEGROUP_NAME},Value=owned" 2> /dev/null
        fi

        if [ -z "${PRIVATE_SUBNET_NLB_TARGET}" ]; then
            PRIVATE_SUBNET_NLB_TARGET="${SUBNET}"
        else
            PRIVATE_SUBNET_NLB_TARGET="${PRIVATE_SUBNET_NLB_TARGET},${SUBNET}"
        fi
    done

    if [ ${#VPC_PRIVATE_SUBNET_IDS[@]} = 1 ]; then
        VPC_PRIVATE_SUBNET_IDS+=(${VPC_PRIVATE_SUBNET_IDS[0]} ${VPC_PRIVATE_SUBNET_IDS[0]})
    elif [ ${#VPC_PRIVATE_SUBNET_IDS[@]} = 2 ]; then
        VPC_PRIVATE_SUBNET_IDS+=(${VPC_PRIVATE_SUBNET_IDS[1]})
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_register_certificate() {
    local ACM_DOMAIN_NAME=$1

    # ACM Keep the wildcard
    ACM_CERTIFICATE_TAGGING=
    ACM_CERTIFICATE_ARN=$(aws acm list-certificates \
        --profile ${AWS_PROFILE} \
        --include keyTypes=RSA_1024,RSA_2048,EC_secp384r1,EC_prime256v1,EC_secp521r1,RSA_3072,RSA_4096 \
        | jq -r --arg DOMAIN_NAME "${ACM_DOMAIN_NAME}" '.CertificateSummaryList[]|select(.DomainName == $DOMAIN_NAME)|.CertificateArn // ""')

    if [ -z "${ACM_CERTIFICATE_ARN}" ] || [ ${ACM_CERTIFICATE_FORCE} == "YES" ]; then
        if [ -n "${ACM_CERTIFICATE_ARN}" ]; then
            ACM_CERTIFICATE_ARN="--certificate-arn=${ACM_CERTIFICATE_ARN}"
        else
            ACM_CERTIFICATE_TAGGING="--tags Key=Name,Value=${ACM_DOMAIN_NAME}"
        fi

        ACM_CERTIFICATE_ARN=$(aws acm import-certificate \
            ${ACM_CERTIFICATE_ARN} \
            ${ACM_CERTIFICATE_TAGGING} \
            --profile ${AWS_PROFILE} \
            --certificate fileb://${SSL_LOCATION}/cert.pem \
            --private-key fileb://${SSL_LOCATION}/privkey.pem | jq -r '.CertificateArn // ""')

        if [ -z "${ACM_CERTIFICATE_ARN}" ]; then
            echo_red "ACM_CERTIFICATE_ARN is empty after creation, something goes wrong"
            exit 1
        fi
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_plateform_nlb() {
	echo_title "Create NLB ${MASTERKUBE}"

    local CONTROLPLANE_INSTANCEID_NLB_TARGET=()
    local PUBLIC_INSTANCEID_NLB_TARGET=()
    local PRIVATE_NLB_DNS=
    local PUBLIC_NLB_DNS=

    # NLB For control plane
	for INSTANCE_INDEX in $(seq ${CONTROLNODE_INDEX} $((CONTROLNODE_INDEX + ${CONTROLNODES})))
	do
		LAUNCHED_INSTANCE=${LAUNCHED_INSTANCES[${INSTANCE_INDEX}]}
		INSTANCE_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.InstanceId // ""')

        CONTROLPLANE_INSTANCEID_NLB_TARGET+=(${INSTANCE_ID})
	done

    # NLB + NGINX Gateway
	if [ "${USE_NGINX_GATEWAY}" = "YES" ]; then
		for INSTANCE_INDEX in $(seq ${FIRSTNODE} $((FIRSTNODE + ${#VPC_PUBLIC_SUBNET_IDS[@]} - 1)))
		do
			LAUNCHED_INSTANCE=${LAUNCHED_INSTANCES[${INSTANCE_INDEX}]}
			INSTANCE_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.InstanceId // ""')
			PUBLIC_INSTANCEID_NLB_TARGET+=(${INSTANCE_ID})
		done
    else
        PUBLIC_INSTANCEID_NLB_TARGET=CONTROLPLANE_INSTANCEID_NLB_TARGET
	fi

    CONTROLPLANE_INSTANCEID_NLB_TARGET=$(echo -n ${CONTROLPLANE_INSTANCEID_NLB_TARGET[@]} | tr ' ' ',')
    PUBLIC_INSTANCEID_NLB_TARGET=$(echo -n ${PUBLIC_INSTANCEID_NLB_TARGET[@]} | tr ' ' ',')

	TARGET_VPC=$(aws ec2 describe-subnets \
		--profile ${AWS_PROFILE} \
		--filters "Name=subnet-id,Values=${VPC_PRIVATE_SUBNET_ID}" \
		| jq -r ".Subnets[0].VpcId")

	eval create-aws-nlb.sh \
		--profile=${AWS_PROFILE} \
		--region=${AWS_REGION} \
		--name=${MASTERKUBE} \
		--cert-arn=${ACM_CERTIFICATE_ARN} \
		--expose-public=${EXPOSE_PUBLIC_CLUSTER} \
		--public-subnet-id="${PUBLIC_SUBNET_NLB_TARGET}" \
		--private-subnet-id="${PRIVATE_SUBNET_NLB_TARGET}" \
		--target-vpc-id=${TARGET_VPC} \
		--target-port="${LOAD_BALANCER_PORT}" \
		--security-group=${VPC_PRIVATE_SECURITY_GROUPID} \
		--controlplane-instances-id="${CONTROLPLANE_INSTANCEID_NLB_TARGET}" \
		--public-instances-id="${PUBLIC_INSTANCEID_NLB_TARGET}" \
		${SILENT}
    
	PRIVATE_NLB_DNS=$(aws elbv2 describe-load-balancers \
        --profile=${AWS_PROFILE} \
        --region=${AWS_REGION} \
        | jq -r --arg NLB_NAME "c-${MASTERKUBE}" '.LoadBalancers[]|select(.LoadBalancerName == $NLB_NAME)|.DNSName')

	LOAD_BALANCER_IP="${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}"

	if [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
		PUBLIC_NLB_DNS=$(aws elbv2 describe-load-balancers --profile=${AWS_PROFILE} --region=${AWS_REGION} | jq -r --arg NLB_NAME "p-${MASTERKUBE}" '.LoadBalancers[]|select(.LoadBalancerName == $NLB_NAME)|.DNSName')
	else
		PUBLIC_NLB_DNS=${PRIVATE_NLB_DNS}
	fi

	# Record Masterkube in Route53 DNS
	register_nlb_dns CNAME ${PRIVATE_NLB_DNS} ${PUBLIC_NLB_DNS}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_info_vm() {
    # Empty
    echo > /dev/null
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function plateform_create_vm() {
	local INDEX=$1
	local NETWORK_INTERFACE_ID=${RESERVED_ENI[${INDEX}]}
	local IPADDR=${RESERVED_ADDR_IPS[${INDEX}]}
	local MACHINE_TYPE=${WORKER_NODE_MACHINE}
	local MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	local SUFFIX=$(named_index_suffix ${INDEX})
	local NODEINDEX=$(get_node_index ${INDEX})
	local INSTANCE_ID=

	LAUNCHED_INSTANCE=$(aws ec2  describe-instances \
		--profile ${AWS_PROFILE} \
		--filters "Name=tag:Name,Values=${MASTERKUBE_NODE}" \
		| jq -r '.Reservations[].Instances[]|select(.State.Code == 16)' )

	if [ -z $(echo ${LAUNCHED_INSTANCE} | jq '.InstanceId') ]; then
		# Cloud init user-data
		cat > ${TARGET_CONFIG_LOCATION}/userdata-${SUFFIX}.yaml <<EOF
#cloud-config
write_files:
- encoding: gzip+base64
  content: $(cat ${TARGET_CONFIG_LOCATION}/credential.yaml | gzip -c9 | base64 -w 0)
  owner: root:root
  path: ${IMAGE_CREDENTIALS_CONFIG}
  permissions: '0644'
runcmd:
  - echo "Create ${MASTERKUBE_NODE}" > /var/log/masterkube.log
  - hostnamectl set-hostname "${MASTERKUBE_NODE}"
EOF

	cat > ${TARGET_CONFIG_LOCATION}/mapping-${SUFFIX}.json <<EOF
	[
		{
			"DeviceName": "/dev/sda1",
			"Ebs": {
				"DeleteOnTermination": true,
				"VolumeType": "${VOLUME_TYPE}",
				"VolumeSize": ${VOLUME_SIZE},
				"Encrypted": false
			}
		}
	]
EOF

		# Worker options by default
		local IAM_PROFILE_OPTIONS="--iam-instance-profile Arn=${WORKER_INSTANCE_PROFILE_ARN}"
		local PUBLIC_IP_OPTIONS="--no-associate-public-ip-address"
		local VPC_LENGTH=${#VPC_PRIVATE_SUBNET_IDS[@]}
		local SUBNET_INDEX=$(( $((NODEINDEX - 1)) % ${VPC_LENGTH} ))
		local SUBNETID="${VPC_PRIVATE_SUBNET_IDS[${SUBNET_INDEX}]}"
		local SGID="${VPC_PRIVATE_SECURITY_GROUPID}"
		local PUBLICIP=false

		echo_title "Clone ${TARGET_IMAGE} to ${MASTERKUBE_NODE}"

		if [ "${HA_CLUSTER}" = "true" ]; then

			if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
				# NGINX Load blancer
				MACHINE_TYPE=${NGINX_MACHINE}

				# Use subnet public for NGINX Load balancer
				if [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ] && [ "${USE_NLB}" = "NO" ]; then
					PUBLICIP=true
					IAM_PROFILE_OPTIONS=
				fi
			elif [ ${INDEX} -lt ${WORKERNODE_INDEX} ]; then
				PUBLICIP=${CONTROLPLANE_USE_PUBLICIP}
				IAM_PROFILE_OPTIONS="--iam-instance-profile Arn=${MASTER_INSTANCE_PROFILE_ARN}"
				MACHINE_TYPE=${CONTROL_PLANE_MACHINE}
			else
				PUBLICIP=${WORKERNODE_USE_PUBLICIP}
			fi

		elif [ ${INDEX} -lt ${WORKERNODE_INDEX} ]; then

			MACHINE_TYPE=${CONTROL_PLANE_MACHINE}

			# Use subnet public for NGINX Load balancer
			if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
				if [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ] && [ "${USE_NLB}" = "NO" ]; then
					PUBLICIP=true
					IAM_PROFILE_OPTIONS=
				fi
			elif [ ${INDEX} = ${CONTROLNODE_INDEX} ]; then
				if [ "${CONTROLPLANE_USE_PUBLICIP}" = "true" ]; then
					PUBLICIP=true
					IAM_PROFILE_OPTIONS="--iam-instance-profile Arn=${MASTER_INSTANCE_PROFILE_ARN}"
				fi
			else
				PUBLICIP=${WORKERNODE_USE_PUBLICIP}
			fi

		fi
		
		if [ "${PUBLICIP}" = "true" ]; then
			PUBLIC_IP_OPTIONS=--associate-public-ip-address
			SUBNET_INDEX=$(( $((NODEINDEX - 1)) % ${#VPC_PUBLIC_SUBNET_IDS[@]} ))
			SUBNETID="${VPC_PUBLIC_SUBNET_IDS[${SUBNET_INDEX}]}"
			SGID="${VPC_PUBLIC_SECURITY_GROUPID}"
		fi

		if [ "${PUBLICIP}" = "true" ] || [ -z ${NETWORK_INTERFACE_ID} ]; then
			echo_grey "= Launch Instance ${MASTERKUBE_NODE} with subnetid ${SUBNETID} in security group ${SGID}"
			LAUNCHED_INSTANCE=$(aws ec2 run-instances \
				--profile "${AWS_PROFILE}" \
				--region "${AWS_REGION}" \
				--image-id "${TARGET_IMAGE_AMI}" \
				--count 1  \
				--instance-type "${MACHINE_TYPE}" \
				--key-name "${SSH_KEYNAME}" \
				--subnet-id "${SUBNETID}" \
				--security-group-ids "${SGID}" \
				--user-data "file://${TARGET_CONFIG_LOCATION}/userdata-${SUFFIX}.yaml" \
				--block-device-mappings "file://${TARGET_CONFIG_LOCATION}/mapping-${SUFFIX}.json" \
				--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${MASTERKUBE_NODE}},{Key=NodeGroup,Value=${NODEGROUP_NAME}},{Key=kubernetes.io/cluster/${NODEGROUP_NAME},Value=owned},{Key=KubernetesCluster,Value=${NODEGROUP_NAME}}]" \
				${PUBLIC_IP_OPTIONS} \
				${IAM_PROFILE_OPTIONS})

			LAUNCHED_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.Instances[0].InstanceId // ""')
		else
			echo_grey "= Launch Instance ${MASTERKUBE_NODE} with associated ENI ${NETWORK_INTERFACE_ID}"
			LAUNCHED_INSTANCE=$(aws ec2 run-instances \
				--profile "${AWS_PROFILE}" \
				--region "${AWS_REGION}" \
				--image-id "${TARGET_IMAGE_AMI}" \
				--count 1  \
				--instance-type "${MACHINE_TYPE}" \
				--key-name "${SSH_KEYNAME}" \
				--network-interfaces DeviceIndex=0,NetworkInterfaceId=${NETWORK_INTERFACE_ID} \
				--user-data "file://${TARGET_CONFIG_LOCATION}/userdata-${SUFFIX}.yaml" \
				--block-device-mappings "file://${TARGET_CONFIG_LOCATION}/mapping-${SUFFIX}.json" \
				--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${MASTERKUBE_NODE}},{Key=NodeGroup,Value=${NODEGROUP_NAME}},{Key=kubernetes.io/cluster/${NODEGROUP_NAME},Value=owned},{Key=KubernetesCluster,Value=${NODEGROUP_NAME}}]" \
				${IAM_PROFILE_OPTIONS})

			LAUNCHED_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.Instances[0].InstanceId // ""')
		fi

		if [ -z ${LAUNCHED_ID} ]; then
			echo_red "Something goes wrong when launching ${MASTERKUBE_NODE}"
			exit -1
		fi

		if [ ${CNI_PLUGIN} == "flannel" ]; then
			aws ec2 modify-instance-attribute \
                --profile "${AWS_PROFILE}" \
                --region "${AWS_REGION}" \
                --instance-id=${LAUNCHED_ID} \
                --no-source-dest-check
		fi

		echo_blue_bold "Wait for ${MASTERKUBE_NODE} instanceID ${LAUNCHED_ID} to boot"

		while [ ! $(aws ec2  describe-instances --profile ${AWS_PROFILE} --instance-ids "${LAUNCHED_ID}" | jq -r '.Reservations[0].Instances[0].State.Code') -eq 16 ];
		do
			sleep 1
		done

		LAUNCHED_INSTANCE=$(aws ec2  describe-instances \
			--profile ${AWS_PROFILE} \
			--instance-ids ${LAUNCHED_ID} | jq .Reservations[0].Instances[0])

		IPADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateIpAddress // ""')
		PUBADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PublicIpAddress // ""')
		PRIVATEDNS=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateDnsName // ""')

		if [ -z "${PUBADDR}" ] || [ "${PREFER_SSH_PUBLICIP}" = "NO" ]; then
			SSHADDR=${IPADDR}
		else
			SSHADDR=${PUBADDR}
		fi

		if [ "${PUBLICIP}" = "true" ] || [ -z ${NETWORK_INTERFACE_ID} ]; then
			NETWORK_INTERFACE_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.NetworkInterfaces[0].NetworkInterfaceId // ""')
			ENI=$(aws ec2 describe-network-interfaces \
				--profile ${AWS_PROFILE} \
				--filters Name=network-interface-id,Values=${NETWORK_INTERFACE_ID} 2> /dev/null \
				| jq -r '.NetworkInterfaces[0]//""')
			echo ${ENI} | jq . > ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json
		fi

		echo -n ${LAUNCHED_INSTANCE} | jq . > ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json

		echo_title "Wait ssh ready on ${KUBERNETES_USER}@${SSHADDR}"
		wait_ssh_ready ${KUBERNETES_USER}@${SSHADDR}

		echo_blue_bold "SSH is ready on ${MASTERKUBE_NODE}, private-ip=${IPADDR}, ssh-ip=${SSHADDR}, public-ip=${PUBADDR}"
	else
		IPADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateIpAddress // ""')
		PUBADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PublicIpAddress // ""')
		PRIVATEDNS=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateDnsName // ""')

		if [ -z "${PUBADDR}" ] || [ "${PREFER_SSH_PUBLICIP}" = "NO" ]; then
			SSHADDR=${IPADDR}
		else
			SSHADDR=${PUBADDR}
		fi

		echo_blue_bold "Already launched ${MASTERKUBE_NODE}, private-ip=${IPADDR}, ssh-ip=${SSHADDR}, public-ip=${PUBADDR}"

		echo -n ${LAUNCHED_INSTANCE} | jq . > ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json
	fi

    PRIVATE_ADDR_IPS[${INDEX}]=${IPADDR}
    PUBLIC_ADDR_IPS[${INDEX}]=${PUBADDR}
    PRIVATE_DNS_NAMES[${INDEX}]=${PRIVATEDNS}

	eval ssh ${SSH_OPTIONS} "${KUBERNETES_USER}@${SSHADDR}" mkdir -p /home/${KUBERNETES_USER}/cluster ${SILENT}
	eval scp ${SCP_OPTIONS} tools ${KUBERNETES_USER}@${IPADDR}:~ ${SILENT}
	eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo chown -R root:adm /home/${KUBERNETES_USER}/tools ${SILENT}
	eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo cp /home/${KUBERNETES_USER}/tools/* /usr/local/bin ${SILENT}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_network_interfaces() {
	# Create ENI to capture IP addresses before launch instances
	local INDEX=$1
	local ENI_NAME=
    local NODEINDEX=$(get_node_index ${INDEX})
    local SUFFIX=$(named_index_suffix $INDEX)
    local MASTERKUBE_NODE=$(get_vm_name ${INDEX})
	local SUBNET_INDEX=$(( $((NODEINDEX - 1)) % ${#VPC_PRIVATE_SUBNET_IDS[@]} ))
	local SUBNETID="${VPC_PRIVATE_SUBNET_IDS[${SUBNET_INDEX}]}"
	local SGID="${VPC_PRIVATE_SECURITY_GROUPID}"
	local PUBLICIP=false
	local INFID=
	local ENI=

	if [ $# -gt 1 ]; then
		ENI_NAME=$2
    else
		ENI_NAME=${MASTERKUBE_NODE}
	fi

	if [ ${HA_CLUSTER} = "true" ]; then
		if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
			# Use subnet public for NGINX Load balancer if we don't use a NLB
			if [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ] && [ "${USE_NLB}" = "NO" ]; then
				PUBLICIP=true
				SUBNET_INDEX=$(( $((NODEINDEX - 1)) % ${#VPC_PUBLIC_SUBNET_IDS[@]} ))
				SUBNETID="${VPC_PUBLIC_SUBNET_IDS[${SUBNET_INDEX}]}"
				SGID="${VPC_PUBLIC_SECURITY_GROUPID}"
			fi
		fi
	elif [ ${INDEX} -lt ${WORKERNODE_INDEX} ]; then
		if [ ${INDEX} = ${CONTROLNODE_INDEX} ] && [ "${CONTROLPLANE_USE_PUBLICIP}" = "true" ]; then
			PUBLICIP=true
			SUBNET_INDEX=$(( $((NODEINDEX - 1)) % ${#VPC_PUBLIC_SUBNET_IDS[@]} ))
			SUBNETID="${VPC_PUBLIC_SUBNET_IDS[${SUBNET_INDEX}]}"
			SGID="${VPC_PUBLIC_SECURITY_GROUPID}"
		elif [ ${INDEX} -lt ${CONTROLNODE_INDEX} ] && [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
			PUBLICIP=true
			SUBNET_INDEX=$(( $((NODEINDEX - 1)) % ${#VPC_PUBLIC_SUBNET_IDS[@]} ))
			SUBNETID="${VPC_PUBLIC_SUBNET_IDS[${SUBNET_INDEX}]}"
			SGID="${VPC_PUBLIC_SECURITY_GROUPID}"
		fi
	fi

	if [ ${PUBLICIP} != "true" ]; then
		if [ -f ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json ]; then
			INFID=$(cat ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json | jq -r '.NetworkInterfaceId')
			ENI=$(aws ec2 describe-network-interfaces \
				--profile ${AWS_PROFILE} \
				--filters Name=network-interface-id,Values=${INFID} 2> /dev/null \
				| jq -r '.NetworkInterfaces[0]//""')

			if [ -z "${ENI}" ]; then
				echo_red_bold "Reserved ENI ${ENI_NAME} not found, network-interface-id=${INFID}, recreate it"
				rm ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json
			fi
		fi

		if [ ! -f ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json ]; then

			ENI=$(aws ec2 describe-network-interfaces \
				--profile ${AWS_PROFILE} \
				--filters Name=tag:Name,Values=${ENI_NAME} \
				| jq -r '.NetworkInterfaces[0]//""')

			if [ -z "${ENI}" ]; then
				# ENI doesn't exist
				echo_blue_bold "Create Reserved ENI ${ENI_NAME}, subnetid=${SUBNETID}, security group=${SGID}"

				ENI=$(aws ec2 create-network-interface \
					--profile ${AWS_PROFILE} \
					--subnet-id ${SUBNETID} \
					--groups ${SGID} \
					--description "Reserved ENI node[${INDEX}]" | jq '.NetworkInterface')

				INFID=$(echo ${ENI} | jq -r '.NetworkInterfaceId')

				aws ec2 create-tags --resources ${INFID} --tags \
					"Key=Name,Value=${ENI_NAME}" \
					"Key=PublicIP,Value=${PUBLICIP}" \
					"Key=NodeGroup,Value=${NODEGROUP_NAME}" \
					"Key=kubernetes.io/cluster/${NODEGROUP_NAME},Value=owned" \
					"Key=KubernetesCluster,Value=${NODEGROUP_NAME}" 2> /dev/null
			else
				echo_blue_bold "Already created Reserved ENI ${ENI_NAME}"
			fi

			echo ${ENI} | jq . > ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json
		else
			echo_blue_bold "Use declared Reserved ENI ${ENI_NAME}"

			ENI=$(cat ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json)
		fi

        local IPADDR=$(echo ${ENI} | jq -r '.PrivateIpAddresses[]|select(.Primary == true)|.PrivateIpAddress')
        local PRIVATEDNS=$(echo ${ENI} | jq -r '.PrivateDnsName')
		local INFID=$(echo ${ENI} | jq -r '.NetworkInterfaceId')

        RESERVED_ENI[${INDEX}]=${INFID}
        RESERVED_ADDR_IPS[${INDEX}]=${IPADDR}
        PRIVATE_DNS_NAMES[${INDEX}]=${PRIVATEDNS}
	else
		echo_red_bold "Don't declare Reserved ENI ${ENI_NAME} because public IP required"

        RESERVED_ENI[${INDEX}]=""
        RESERVED_ADDR_IPS[${INDEX}]=""
        PRIVATE_DNS_NAMES[${INDEX}]=""

		rm -f ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json
	fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_extras_ip() {
	local VPC_LENGTH=${#VPC_PRIVATE_SUBNET_IDS[@]}
	local SUBNET_INDEX=0
	local EXTRAS_INDEX=$(($LASTNODE_INDEX + 1))

	if [ ${CONTROLNODE_INDEX} -gt 0 ]; then
		SUBNET_INDEX=$(( $((CONTROLNODE_INDEX - 1)) % ${VPC_LENGTH} ))
	fi

	for INDEX in $(seq 0 1 2)
	do
		if [ ${SUBNET_INDEX} != ${INDEX} ]; then
			local ENIINDEX=$((INDEX + ${LASTNODE_INDEX} + 1))
			local NODE_INDEX=$((INDEX + 1))

            create_network_interfaces ${ENIINDEX} ${NODEGROUP_NAME}-master-$(named_index_suffix ${NODE_INDEX})

			PRIVATE_ADDR_IPS[${EXTRAS_INDEX}]=${RESERVED_ADDR_IPS[${ENIINDEX}]}
    		PUBLIC_ADDR_IPS[${EXTRAS_INDEX}]=${PUBLIC_NODE_IP}

            EXTRAS_INDEX=$((EXTRAS_INDEX + 1))
		fi
	done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function prepare_networking() {
    local INDEX=

    for INDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
    do
	    create_network_interfaces ${INDEX}
    done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_instance_status() {
    local INSTANCE_ID=$1
    local STATUS=$2

    while [ ! $(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" | jq -r '.Reservations[0].Instances[0].State.Code') -eq ${STATUS} ];
    do
        sleep 1
    done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_instance_id() {
    local INSTANCE_ID=$1

    aws ec2 stop-instances --force --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" &>/dev/null

    wait_instance_status $INSTANCE_ID 80

    aws ec2 terminate-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${INSTANCE_ID}" &>/dev/null

    wait_instance_status $INSTANCE_ID 48

    echo_blue_bold "Terminated instance: ${INSTANCE_ID}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_instance_profile() {
	aws iam get-instance-profile \
	--profile ${AWS_PROFILE} \
		--instance-profile-name $1 2> /dev/null | jq -r '.InstanceProfile.Arn // ""'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_instance_profile() {
	local MASTER_PROFILE_NAME=$1
	local POLICY_NAME=$2
	local ROLE_POLICY=$3
	local POLICY_DOCUMENT=$4

	aws iam create-role \
		--profile ${AWS_PROFILE}\
		--role-name ${MASTER_PROFILE_NAME} \
		--assume-role-policy-document file://${ROLE_POLICY} &> /dev/null

	aws iam put-role-policy \
		--profile ${AWS_PROFILE} \
		--role-name ${MASTER_PROFILE_NAME} \
		--policy-name kubernetes-master-permissions \
		--policy-document file://${POLICY_DOCUMENT} &> /dev/null
	
	aws iam create-instance-profile \
		--profile ${AWS_PROFILE} \
		--instance-profile-name ${MASTER_PROFILE_NAME} &> /dev/null
	
	aws iam add-role-to-instance-profile \
		--profile ${AWS_PROFILE} \
		--instance-profile-name ${MASTER_PROFILE_NAME} \
		--role-name ${MASTER_PROFILE_NAME} &> /dev/null

	aws iam get-instance-profile \
		--profile ${AWS_PROFILE} \
		--instance-profile-name ${MASTER_PROFILE_NAME} | jq -r '.InstanceProfile.Arn // ""'
}
#===========================================================================================================================================
#
#===========================================================================================================================================
function describe_living_instance() {
    aws ec2  describe-instances \
        --profile ${AWS_PROFILE} \
        --region ${AWS_REGION} \
        --filters "Name=tag:Name,Values=$1" \
        | jq -r '.Reservations[].Instances[]|select(.State.Code == 16)'
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_instance() {
    local INSTANCE_NAME=$1

    local INSTANCE=$(describe_living_instance "${INSTANCE_NAME}")
    local INSTANCE_ID=$(echo ${INSTANCE} | jq -r '.InstanceId // ""')

    if [ -n "${INSTANCE_ID}" ]; then
        echo_blue_bold "Delete VM: ${INSTANCE_NAME}"
        delete_instance_id "${INSTANCE_ID}" &
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_vm_by_name() {
    local INSTANCE_NAME=$1
    local INSTANCE=$(describe_living_instance "${INSTANCE_NAME}")
    local INSTANCE_ID=$(echo ${INSTANCE} | jq -r '.InstanceId // ""')

    if [ -n "${INSTANCE_ID}" ]; then
        echo_blue_bold "Delete VM: ${INSTANCE_NAME}"
        delete_instance_id "${INSTANCE_ID}" &
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function delete_load_balancers() {
    ./bin/delete-aws-nlb.sh --profile ${AWS_PROFILE} --region ${AWS_REGION} --name ${MASTERKUBE}

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
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function update_build_env() {
    set +u

	save_buildenv

	cat >> ${TARGET_CONFIG_LOCATION}/buildenv <<EOF
export MASTER_INSTANCE_PROFILE_ARN=${MASTER_INSTANCE_PROFILE_ARN}
export MASTER_NODE_ALLOW_DEPLOYMENT=${MASTER_NODE_ALLOW_DEPLOYMENT}
export MASTER_PROFILE_NAME=${MASTER_PROFILE_NAME}
export PRIVATE_SUBNET_NLB_TARGET=${PRIVATE_SUBNET_NLB_TARGET}
export PUBLIC_SUBNET_NLB_TARGET=${PUBLIC_SUBNET_NLB_TARGET}
export RESERVED_ADDR_IPS=(${RESERVED_ADDR_IPS[@]})
export RESERVED_ENI=(${RESERVED_ENI[@]})
export VPC_PRIVATE_SECURITY_GROUPID=${VPC_PRIVATE_SECURITY_GROUPID}
export VPC_PRIVATE_SUBNET_ID=${VPC_PRIVATE_SUBNET_ID}
export VPC_PRIVATE_SUBNET_IDS=(${VPC_PRIVATE_SUBNET_IDS[@]})
export VPC_PUBLIC_SECURITY_GROUPID=${VPC_PUBLIC_SECURITY_GROUPID}
export VPC_PUBLIC_SUBNET_ID=${VPC_PUBLIC_SUBNET_ID}
export VPC_PUBLIC_SUBNET_IDS=(${VPC_PUBLIC_SUBNET_IDS[@]})
export WORKER_INSTANCE_PROFILE_ARN=${WORKER_INSTANCE_PROFILE_ARN}
export WORKER_PROFILE_NAME=${WORKER_PROFILE_NAME}
EOF
    set -u
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function update_provider_config() {
    PROVIDER_AUTOSCALER_CONFIG=$(cat ${TARGET_CONFIG_LOCATION}/provider.json)

    echo -n ${PROVIDER_AUTOSCALER_CONFIG} | jq --arg TARGET_IMAGE "${TARGET_IMAGE_AMI}" '.ami = $TARGET_IMAGE' > ${TARGET_CONFIG_LOCATION}/provider.json
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_vmuuid() {
    local VMNAME=$1

    aws ec2  describe-instances \
		--profile ${AWS_PROFILE} \
		--filters "Name=tag:Name,Values=${MASTERKUBE_NODE}" \
		| jq -r '.Reservations[0].Instances[0].InstanceId//""' 2>/dev/null
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_net_type() {
    echo -n "custom"
}