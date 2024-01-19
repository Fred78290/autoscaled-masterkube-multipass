#!/bin/bash

# This script create every thing to deploy a simple kubernetes autoscaled cluster with aws.
# It will generate:
# Custom AMI image with every thing for kubernetes
# Config file to deploy the cluster autoscaler.

set -eu

export CACHE=$HOME/.local/aws/cache

export ACM_CERTIFICATE_ARN=
export ACM_DOMAIN_NAME=
export AUTOSCALE_MACHINE="t3a.medium"
export AUTOSCALER_DESKTOP_UTILITY_ADDR=
export AUTOSCALER_DESKTOP_UTILITY_CACERT=
export AUTOSCALER_DESKTOP_UTILITY_CERT=
export AUTOSCALER_DESKTOP_UTILITY_KEY=
export AUTOSCALER_DESKTOP_UTILITY_TLS=
export CLOUD_PROVIDER_CONFIG=
export CLOUD_PROVIDER=external
export CNI_PLUGIN=aws
export CNI_VERSION=v1.4.0
export CONFIGURATION_LOCATION=${PWD}
export CONTAINER_ENGINE=containerd
export CONTROL_PLANE_MACHINE="t3a.medium"
export CONTROLNODES=1
export CORESTOTAL="0:16"
export DELETE_CREDENTIALS_CONFIG=NO
export DOMAIN_NAME=
export ETCD_DST_DIR=
export EXTERNAL_ETCD_ARGS=
export EXTERNAL_ETCD=false
export FIRSTNODE=0
export GRPC_PROVIDER=externalgrpc
export HA_CLUSTER=false
export KUBECONFIG=${HOME}/.kube/config
export KUBERNETES_DISTRO=kubeadm
export KUBERNETES_VERSION=$(curl -sSL https://dl.k8s.io/release/stable.txt)
export MASTER_PROFILE_NAME="kubernetes-master-profile"
export MAX_PODS=110
export MAXAUTOPROVISIONNEDNODEGROUPCOUNT="1"
export MAXNODES=9
export MAXTOTALNODES=${MAXNODES}
export MEMORYTOTAL="0:48"
export MINNODES=0
export NGINX_MACHINE="t3a.small"
export NODEGROUP_SET=NO
export OSDISTRO=$(uname -s)
export PREFER_SSH_PUBLICIP=NO
export REGISTRY=fred78290
export RESUME=NO
export SCALEDOWNDELAYAFTERADD="1m"
export SCALEDOWNDELAYAFTERDELETE="1m"
export SCALEDOWNDELAYAFTERFAILURE="1m"
export SCALEDOWNENABLED="true"
export SCALEDOWNUNEEDEDTIME="1m"
export SCALEDOWNUNREADYTIME="1m"
export SILENT="&> /dev/null"
export SSH_KEY_FNAME=
export SSH_KEY=$(cat ~/.ssh/id_rsa)
export SSH_KEYNAME="aws-k8s-key"
export SSH_PRIVATE_KEY=~/.ssh/id_rsa
export SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"
export TARGET_CLUSTER_LOCATION=
export TARGET_CONFIG_LOCATION=
export TARGET_DEPLOY_LOCATION=
export TARGET_IMAGE_AMI=
export TRANSPORT="tcp"
export UNREMOVABLENODERECHECKTIMEOUT="1m"
export USE_NGINX_GATEWAY=NO
export USE_NLB=NO
export USE_ZEROSSL=YES
export VOLUME_SIZE=20
export VOLUME_TYPE=gp3
export WORKER_NODE_MACHINE="t3a.medium"
export WORKER_PROFILE_NAME="kubernetes-worker-profile"
export WORKERNODES=3

# aws region eu-west1
export SEED_ARCH=amd64
export KUBERNETES_USER=ubuntu
export SEED_IMAGE_AMD64="ami-0333305f9719618c7"
export SEED_IMAGE_ARM64="ami-03d568a0c334477dd"
export CONFIGURATION_LOCATION=${PWD}
export SSL_LOCATION=${CONFIGURATION_LOCATION}/etc/ssl
export LOAD_BALANCER_PORT=80,443,6443

# defined in private vars.defs
export CERT_EMAIL=
export CERT_DOMAIN=
export MASTER_INSTANCE_PROFILE_ARN= #"<to be filled>"
export WORKER_INSTANCE_PROFILE_ARN= #"<to be filled>"
export VPC_PUBLIC_SUBNET_ID= #"<to be filled>"
export VPC_PUBLIC_SECURITY_GROUPID= #"<to be filled>"
export VPC_PRIVATE_SUBNET_ID= #"<to be filled>"
export VPC_PRIVATE_SECURITY_GROUPID= #"<to be filled>"

# optional defined in private vars.defs for debug aws-autoscaler locally
export AWS_ACCESSKEY= #"<to be filled>"
export AWS_SECRETKEY= #"<to be filled>"
export AWS_TOKEN= #"<to be filled>"

export AWS_ROUTE53_ACCESSKEY= #"<to be filled>"
export AWS_ROUTE53_SECRETKEY= #"<to be filled>"
export AWS_ROUTE53_TOKEN= #"<to be filled>"
export AWS_ROUTE53_PRIVATE_ZONE_ID= #"<to be filled>"
export AWS_ROUTE53_PUBLIC_ZONE_ID= #"<to be dtermined>"

export EXPOSE_PUBLIC_CLUSTER=false
export CONTROLPLANE_USE_PUBLICIP=false
export WORKERNODE_USE_PUBLICIP=false

export LAUNCH_CA=YES
export PRIVATE_DOMAIN_NAME=
export PUBLIC_DOMAIN_NAME=

export UPGRADE_CLUSTER=NO
export MASTER_NODE_ALLOW_DEPLOYMENT=NO

VPC_PUBLIC_SUBNET_IDS=()
VPC_PRIVATE_SUBNET_IDS=()
LAUNCHED_INSTANCES=()
RESERVED_ENI=()
PRIVATE_ADDR_IPS=()
PUBLIC_ADDR_IPS=()
DELETE_CLUSTER=NO

source ${CURDIR}/common.sh

function usage() {
cat <<EOF
$0 create a kubernetes simple cluster or HA cluster with 3 control planes
Options are:
--help | -h                                      # Display usage
--verbose | -v                                   # Verbose
--trace | -x                                     # Trace execution
--resume | -r                                    # Allow resume interrupted creation of cluster kubernetes
--delete                                         # Delete cluster and exit
--create-image-only                              # Create image only
--cache=<path>                                   # Cache location, default ${CACHE}
--upgrade                                        # Upgrade existing cluster

### Flags to set some location informations

--configuration-location=<path>                  # Specify where configuration will be stored, default ${CONFIGURATION_LOCATION}
--ssl-location=<path>                            # Specify where the etc/ssl dir is stored, default ${SSL_LOCATION}
--defs=<path>                                    # Specify the ${PLATEFORM} definitions, default ${PLATEFORMDEFS}

### Flags to set AWS informations

--profile | -p=<value>                           # Specify AWS profile, default ${AWS_PROFILE}
--region | -r=<value>                            # Specify AWS region, default ${AWS_REGION}

--route53-profile=<value>                        # Specify AWS profile for route53 if different, default ${AWS_PROFILE_ROUTE53}
--route53-zone-id=<value>                        # Specify Route53 for private DNS, default ${AWS_ROUTE53_PRIVATE_ZONE_ID}

### Design the kubernetes cluster

--k8s-distribution=<kubeadm|k3s|rke2>            # Which kubernetes distribution to use: kubeadm, k3s, rke2, default ${KUBERNETES_DISTRO}
--ha-cluster                                     # Allow to create an HA cluster, default ${HA_CLUSTER}
--worker-nodes=<value>                           # Specify the number of worker nodes created in HA cluster, default ${WORKERNODES}
--container-runtime=<docker|containerd|cri-o>    # Specify which OCI runtime to use, default ${CONTAINER_ENGINE}
--internet-facing                                # Expose the cluster on internet port: 80 443, default ${EXPOSE_PUBLIC_CLUSTER}
--no-internet-facing                             # Don't expose the cluster on internet, default ${EXPOSE_PUBLIC_CLUSTER}
--max-pods=<value>                               # Specify the max pods per created VM, default ${MAX_PODS}
--create-nginx-apigateway                        # Create NGINX instance to install an apigateway, default ${USE_NGINX_GATEWAY}
--dont-create-nginx-apigateway                   # Don't create NGINX instance to install an apigateway, default ${USE_NGINX_GATEWAY}

### Design domain

--public-domain=<value>                          # Specify the public domain to use, default ${PUBLIC_DOMAIN_NAME}
--private-domain=<value>                         # Specify the private domain to use, default ${PRIVATE_DOMAIN_NAME}
--dashboard-hostname=<value>                     # Specify the hostname for kubernetes dashboard, default ${DASHBOARD_HOSTNAME}

### Cert Manager

--cert-email=<value>                             # Specify the mail for lets encrypt, default ${CERT_EMAIL}
--use-zerossl                                    # Specify cert-manager to use zerossl, default ${USE_ZEROSSL}
--dont-use-zerossl                               # Specify cert-manager to use letsencrypt, default ${USE_ZEROSSL}
--zerossl-eab-kid=<value>                        # Specify zerossl eab kid, default ${CERT_ZEROSSL_EAB_KID}
--zerossl-eab-hmac-secret=<value>                # Specify zerossl eab hmac secret, default ${CERT_ZEROSSL_EAB_HMAC_SECRET}
--godaddy-key                                    # Specify godaddy api key
--godaddy-secret                                 # Specify godaddy api secret

### Flags to expose nodes in public AZ with public IP

--control-plane-public                           # Control plane are hosted in public subnet with public IP, default ${CONTROLPLANE_USE_PUBLICIP}
--no-control-plane-public                        # Control plane are hosted in private subnet, default ${CONTROLPLANE_USE_PUBLICIP}
--worker-node-public                             # Worker nodes are hosted in public subnet with public IP, default ${WORKERNODE_USE_PUBLICIP}
--no-worker-node-public                          # Worker nodes are hosted in private subnet, default ${WORKERNODE_USE_PUBLICIP}

### Flags in ha mode only

--create-external-etcd                           # Create an external HA etcd cluster, default ${EXTERNAL_ETCD}
--use-nlb                                        # Use AWS NLB as load balancer in public AZ
--dont-use-nlb                                   # Use NGINX as load balancer in public AZ

### Flags in both mode

--prefer-ssh-publicip                            # Allow to SSH on publicip when available, default ${PREFER_SSH_PUBLICIP}
--dont-prefer-ssh-publicip                       # Disallow to SSH on publicip when available, default ${PREFER_SSH_PUBLICIP}
--control-plane-machine=<value>                  # Override machine type used for control plane, default ${CONTROL_PLANE_MACHINE}
--worker-node-machine=<value>                    # Override machine type used for worker nodes, default ${WORKER_NODE_MACHINE}
--autoscale-machine=<value>                      # Override machine type used for auto scaling, default ${AUTOSCALE_MACHINE}
--nginx-machine=<value>                          # The instance type name to deploy front nginx node, default ${NGINX_MACHINE}
--ssh-private-key=<path>                         # Override ssh key is used, default ${SSH_PRIVATE_KEY}
--transport=<value>                              # Override the transport to be used between autoscaler and aws-autoscaler, default ${TRANSPORT}
--node-group=<value>                             # Override the node group name, default ${NODEGROUP_NAME}
--cni-plugin-version=<value>                     # Override CNI plugin version, default: ${CNI_VERSION}
--cni-plugin=<value>                             # Override CNI plugin, default: ${CNI_PLUGIN}
--kubernetes-version | -k=<value>                # Override the kubernetes version, default ${KUBERNETES_VERSION}
--volume-type=<value>                            # Override the root EBS volume type, default ${VOLUME_TYPE}
--volume-size=<value>                            # Override the root EBS volume size in Gb, default ${VOLUME_SIZE}

### Flags to configure network in aws

--public-subnet-id=<subnetid,...>                # Specify the public subnet ID for created VM, default ${VPC_PUBLIC_SUBNET_ID}
--public-sg-id=<sg-id>                           # Specify the public security group ID for VM, default ${VPC_PUBLIC_SECURITY_GROUPID}
--private-subnet-id<subnetid,...>                # Specify the private subnet ID for created VM, default ${VPC_PRIVATE_SUBNET_ID}
--private-sg-id=<sg-id>                          # Specify the private security group ID for VM, default ${VPC_PRIVATE_SECURITY_GROUPID}

### Flags to set the template vm

--target-image=<value>                           # Override the template VM image used for created VM, default ${TARGET_IMAGE}
--seed-image=<value>                             # Override the seed image name used to create template, default ${SEED_IMAGE}
--seed-user=<value>                              # Override the seed user in template, default ${KUBERNETES_USER}
--arch=<value>                                   # Specify the architecture of VM (amd64|arm64), default ${SEED_ARCH}

### Flags for autoscaler
--cloudprovider=<value>                          # autoscaler flag <grpc|externalgrpc>, default: $GRPC_PROVIDER
--max-nodes-total=<value>                        # autoscaler flag, default: ${MAXTOTALNODES}
--cores-total=<value>                            # autoscaler flag, default: ${CORESTOTAL}
--memory-total=<value>                           # autoscaler flag, default: ${MEMORYTOTAL}
--max-autoprovisioned-node-group-count=<value>   # autoscaler flag, default: ${MAXAUTOPROVISIONNEDNODEGROUPCOUNT}
--scale-down-enabled=<value>                     # autoscaler flag, default: ${SCALEDOWNENABLED}
--scale-down-delay-after-add=<value>             # autoscaler flag, default: ${SCALEDOWNDELAYAFTERADD}
--scale-down-delay-after-delete=<value>          # autoscaler flag, default: ${SCALEDOWNDELAYAFTERDELETE}
--scale-down-delay-after-failure=<value>         # autoscaler flag, default: ${SCALEDOWNDELAYAFTERFAILURE}
--scale-down-unneeded-time=<value>               # autoscaler flag, default: ${SCALEDOWNUNEEDEDTIME}
--scale-down-unready-time=<value>                # autoscaler flag, default: ${SCALEDOWNUNREADYTIME}
--unremovable-node-recheck-timeout=<value>       # autoscaler flag, default: ${UNREMOVABLENODERECHECKTIMEOUT}
EOF
}

TEMP=$(getopt -o hvxr --long upgrade,k8s-distribution:,cloudprovider:,use-zerossl,zerossl-eab-kid:,zerossl-eab-hmac-secret:,godaddy-key:,godaddy-secret:,route53-profile:,route53-zone-id:,cache:,cert-email:,public-domain:,private-domain:,dashboard-hostname:,delete,dont-prefer-ssh-publicip,prefer-ssh-publicip,dont-create-nginx-apigateway,create-nginx-apigateway,configuration-location:,ssl-location:,control-plane-machine:,worker-node-machine:,autoscale-machine:,internet-facing,no-internet-facing,control-plane-public,no-control-plane-public,create-image-only,nginx-machine:,volume-type:,volume-size:,aws-defs:,container-runtime:,cni-plugin:,trace,help,verbose,resume,ha-cluster,create-external-etcd,dont-use-nlb,use-nlb,worker-nodes:,arch:,max-pods:,profile:,region:,node-group:,target-image:,seed-image:,seed-user:,vpc-id:,public-subnet-id:,public-sg-id:,private-subnet-id:,private-sg-id:,transport:,ssh-private-key:,cni-plugin-version:,kubernetes-version:,max-nodes-total:,cores-total:,memory-total:,max-autoprovisioned-node-group-count:,scale-down-enabled:,scale-down-delay-after-add:,scale-down-delay-after-delete:,scale-down-delay-after-failure:,scale-down-unneeded-time:,scale-down-unready-time:,unremovable-node-recheck-timeout: -n "$0" -- "$@")

eval set -- "${TEMP}"

# extract options and their arguments into variables.
while true; do
    case "$1" in
    --create-nginx-apigateway)
        USE_NGINX_GATEWAY=YES
        shift 1
        ;;
    --dont-create-nginx-apigateway)
        USE_NGINX_GATEWAY=NO
        shift 1
        ;;
    --prefer-ssh-publicip)
        PREFER_SSH_PUBLICIP=YES;
        shift 1
        ;;
    --dont-prefer-ssh-publicip)
        PREFER_SSH_PUBLICIP=NO;
        shift 1
        ;;
    --private-domain)
        PRIVATE_DOMAIN_NAME=$2
        shift 2
        ;;
    --cache)
        CACHE=$2
        shift 2
        ;;
    --use-nlb)
        USE_NLB=YES
        shift 1
        ;;
    --dont-use-nlb)
        USE_NLB=NO
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

    --no-internet-facing)
        EXPOSE_PUBLIC_CLUSTER=false
        shift 1
        ;;

    --control-plane-public)
        CONTROLPLANE_USE_PUBLICIP=true
        shift 1
        ;;

    --no-control-plane-public)
        CONTROLPLANE_USE_PUBLICIP=false
        shift 1
        ;;

    --worker-node-public)
        WORKERNODE_USE_PUBLICIP=true
        shift 1
        ;;

    --no-worker-node-public)
        WORKERNODE_USE_PUBLICIP=false
        shift 1
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    --distribution)
        DISTRO=$2
        SEED_IMAGE="${DISTRO}-server-cloudimg-seed"
        ROOT_IMG_NAME=${DISTRO}-kubernetes
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
        set -x
        shift 1
        ;;
    -r|--resume)
        RESUME=YES
        shift 1
        ;;
    --delete)
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
    --dont-use-zerossl)
        USE_ZEROSSL=NO
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
            kubeadm|k3s|rke2)
                KUBERNETES_DISTRO=$2
                ;;
            *)
                echo "Unsupported kubernetes distribution: $2"
                exit 1
                ;;
        esac
        shift 2
        ;;
    -c|--ha-cluster)
        HA_CLUSTER=true
        CONTROLNODES=3
        shift 1
        ;;
    -e|--create-external-etcd)
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

    --profile)
        AWS_PROFILE="$2"
        shift 2
        ;;
    --region)
        AWS_REGION="$2"
        shift 2
        ;;

    --route53-profile)
        AWS_PROFILE_ROUTE53=$2
        shift 2
        ;;
    --max-pods)
        MAX_PODS=$2
        shift 2
        ;;

    --target-image)
        TARGET_IMAGE="$2"
        shift 2
        ;;

    --arch)
        SEED_ARCH=$2
        shift 2
        ;;

    --seed-image)
        OVERRIDE_SEED_IMAGE="$2"
        shift 2
        ;;

    --seed-user)
        KUBERNETES_USER="$2"
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
    --nginx-machine)
        OVERRIDE_NGINX_MACHINE="$2"
        shift 2
        ;;
    --control-plane-machine)
        OVERRIDE_CONTROL_PLANE_MACHINE="$2"
        shift 2
        ;;
    --worker-node-machine)
        OVERRIDE_WORKER_NODE_MACHINE="$2"
        shift 2
        ;;
    --autoscale-machine)
        OVERRIDE_AUTOSCALE_MACHINE="$2"
        shift 2
        ;;
    -s | --ssh-private-key)
        SSH_PRIVATE_KEY=$2
        shift 2
        ;;
    --cni-plugin)
        CNI_PLUGIN="$2"
        shift 2
        ;;
    -n | --cni-version)
        CNI_VERSION="$2"
        shift 2
        ;;
    -t | --transport)
        TRANSPORT="$2"
        shift 2
        ;;
    -k | --kubernetes-version)
        KUBERNETES_VERSION="$2"
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
    --scale-down-unneeded-time)
        SCALEDOWNUNEEDEDTIME="$2"
        shift 2
        ;;
    --scale-down-unready-time)
        SCALEDOWNUNREADYTIME="$2"
        shift 2
        ;;
    --unremovable-node-recheck-timeout)
        UNREMOVABLENODERECHECKTIMEOUT="$2"
        shift 2
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

if [ ${NODEGROUP_SET} == "NO" ]; then
    NODEGROUP_NAME="aws-ca-${KUBERNETES_DISTRO}"
    MASTERKUBE="${NODEGROUP_NAME}-masterkube"
fi

if [ "${VERBOSE}" == "YES" ]; then
    SILENT=
else
    SSH_OPTIONS="${SSH_OPTIONS} -q"
    SCP_OPTIONS="${SCP_OPTIONS} -q"
fi

if [ "${GRPC_PROVIDER}" != "grpc" ] && [ "${GRPC_PROVIDER}" != "externalgrpc" ]; then
    echo_red_bold "Unsupported cloud provider: ${GRPC_PROVIDER}, only grpc|externalgrpc, exit"
    exit
fi

if [ "${USE_ZEROSSL}" = "YES" ]; then
    if [ -z "${CERT_ZEROSSL_EAB_KID}" ] || [ -z "${CERT_ZEROSSL_EAB_HMAC_SECRET}" ]; then
        echo_red_bold "CERT_ZEROSSL_EAB_KID or CERT_ZEROSSL_EAB_HMAC_SECRET is empty, exit"
        exit 1
    fi
fi

if [ ${HA_CLUSTER} = "false" ]; then
    if [ "${USE_NLB}" = "YES" ]; then
        echo_red_bold "NLB usage is not available for single plane cluster"
        exit 1
    fi

    if [ "${USE_NGINX_GATEWAY}" = "NO" ] && [ "${CONTROLPLANE_USE_PUBLICIP}" = "false" ] && [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
        echo_red_bold "Single plane cluster can not be exposed to internet because because control plane require public IP or require NGINX gateway in front"
        exit
    fi
fi

if [ "${CONTROLPLANE_USE_PUBLICIP}" = "true" ]; then
    PREFER_SSH_PUBLICIP=NO

    if [ "${USE_NGINX_GATEWAY}" = "YES" ] || [ "${USE_NLB}" = "YES" ] || [ "${EXPOSE_PUBLIC_CLUSTER}" = "false" ]; then
        echo_red_bold "Control plane can not have public IP because nginx gatewaway or NLB is required or cluster must not be exposed to internet"
        exit 1
    fi

    if [ "${WORKERNODE_USE_PUBLICIP}" = "true" ]; then
        echo_red_bold "Worker node can not have a public IP when control plane does not have public IP"
        exit 1
    fi

fi

[ -z "${AWS_PROFILE_ROUTE53}" ] && AWS_PROFILE_ROUTE53=${AWS_PROFILE}
[ -z "${AWS_ROUTE53_ACCESSKEY}" ] && AWS_ROUTE53_ACCESSKEY=${AWS_ACCESSKEY}
[ -z "${AWS_ROUTE53_SECRETKEY}" ] && AWS_ROUTE53_SECRETKEY=${AWS_SECRETKEY}
[ -z "${AWS_ROUTE53_TOKEN}" ] && AWS_ROUTE53_TOKEN=${AWS_TOKEN}

if [ "${SEED_ARCH}" = "amd64" ]; then
    if [ -z "${OVERRIDE_SEED_IMAGE}" ]; then
        SEED_IMAGE=${SEED_IMAGE_AMD64}
    else
        SEED_IMAGE="${OVERRIDE_SEED_IMAGE}"
    fi

    if [ -n "${OVERRIDE_CONTROL_PLANE_MACHINE}" ]; then
        CONTROL_PLANE_MACHINE="${OVERRIDE_CONTROL_PLANE_MACHINE}"
    fi

    if [ -n "${OVERRIDE_WORKER_NODE_MACHINE}" ]; then
        WORKER_NODE_MACHINE="${OVERRIDE_WORKER_NODE_MACHINE}"
    fi

    if [ -n "${OVERRIDE_AUTOSCALE_MACHINE}" ]; then
        AUTOSCALE_MACHINE="${OVERRIDE_AUTOSCALE_MACHINE}"
    fi

    if [ -n "${OVERRIDE_NGINX_MACHINE}" ]; then
        NGINX_MACHINE="${OVERRIDE_NGINX_MACHINE}"
    fi
elif [ "${SEED_ARCH}" = "arm64" ]; then
    if [ -z "${OVERRIDE_SEED_IMAGE}" ]; then
        SEED_IMAGE=${SEED_IMAGE_ARM64}
    else
        SEED_IMAGE="${OVERRIDE_SEED_IMAGE}"
    fi

    if [ -n "${OVERRIDE_CONTROL_PLANE_MACHINE}" ]; then
        CONTROL_PLANE_MACHINE="${OVERRIDE_CONTROL_PLANE_MACHINE}"
    fi

    if [ -n "${OVERRIDE_WORKER_NODE_MACHINE}" ]; then
        WORKER_NODE_MACHINE="${OVERRIDE_WORKER_NODE_MACHINE}"
    fi

    if [ -n "${OVERRIDE_AUTOSCALE_MACHINE}" ]; then
        AUTOSCALE_MACHINE="${OVERRIDE_AUTOSCALE_MACHINE}"
    fi

    if [ -n "${OVERRIDE_AUTOSCALE_MACHINE}" ]; then
        AUTOSCALE_MACHINE="${OVERRIDE_AUTOSCALE_MACHINE}"
    fi

    if [ -n "${OVERRIDE_NGINX_MACHINE}" ]; then
        NGINX_MACHINE="${OVERRIDE_NGINX_MACHINE}"
    fi
else
    echo_red "Unsupported architecture: ${SEED_ARCH}"
    exit -1
fi

if [ "${UPGRADE_CLUSTER}" == "YES" ] && [ "${DELETE_CLUSTER}" = "YES" ]; then
    echo_red_bold "Can't upgrade deleted cluster, exit"
    exit
fi

if [ "${GRPC_PROVIDER}" != "grpc" ] && [ "${GRPC_PROVIDER}" != "externalgrpc" ]; then
    echo_red_bold "Unsupported cloud provider: ${GRPC_PROVIDER}, only grpc|externalgrpc, exit"
    exit
fi

if [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
    LOAD_BALANCER_PORT="${LOAD_BALANCER_PORT},9345"
    EXTERNAL_ETCD=false
fi

if [ "${HA_CLUSTER}" = "true" ]; then
    CONTROLNODES=3
else
    CONTROLNODES=1
fi

if [ "${KUBERNETES_DISTRO}" == "k3s" ] || [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
    WANTED_KUBERNETES_VERSION=${KUBERNETES_VERSION}
    IFS=. read K8S_VERSION K8S_MAJOR K8S_MINOR <<< "${KUBERNETES_VERSION}"

    if [ ${K8S_MAJOR} -eq 28 ] && [ ${K8S_MINOR} -lt 5 ]; then 
        DELETE_CREDENTIALS_CONFIG=YES
    fi

    if [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
        RANCHER_CHANNEL=$(curl -s https://update.rke2.io/v1-release/channels)
    else
        RANCHER_CHANNEL=$(curl -s https://update.k3s.io/v1-release/channels)
    fi

    KUBERNETES_VERSION=$(echo -n "${RANCHER_CHANNEL}" | jq -r --arg KUBERNETES_VERSION "${K8S_VERSION}.${K8S_MAJOR}" '.data[]|select(.id == $KUBERNETES_VERSION)|.latest//""')

    if [ -z "${KUBERNETES_VERSION}" ]; then
        KUBERNETES_VERSION=$(echo -n "${RANCHER_CHANNEL}" | jq -r '.data[]|select(.id == "latest")|.latest//""')
        echo_red_bold "${KUBERNETES_DISTRO} ${WANTED_KUBERNETES_VERSION} not available, use latest ${KUBERNETES_VERSION}"
    else
        echo_blue_bold "${KUBERNETES_DISTRO} ${WANTED_KUBERNETES_VERSION} found, use ${KUBERNETES_DISTRO} ${KUBERNETES_VERSION}"
    fi
fi

if [ "${VERBOSE}" == "YES" ]; then
    SILENT=
else
    SSH_OPTIONS="${SSH_OPTIONS} -q"
    SCP_OPTIONS="${SCP_OPTIONS} -q"
fi

if [ -z "${TARGET_IMAGE}" ]; then
    ROOT_IMG_NAME=$(aws ec2 describe-images --image-ids ${SEED_IMAGE} | jq -r '.Images[0].Name//""' | sed -E 's/.+ubuntu-(\w+)-.+/\1-k8s/')

    if [ "${ROOT_IMG_NAME}" = "-k8s" ]; then
        echo_red_bold "AMI: ${SEED_IMAGE} not found or not ubuntu, exit"
        exit
    fi

fi

if [ "${KUBERNETES_DISTRO}" == "k3s" ] || [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
    TARGET_IMAGE=$(echo -n "${ROOT_IMG_NAME}-${KUBERNETES_DISTRO}-${KUBERNETES_VERSION}-${SEED_ARCH}" | tr '+' '-')
else
    TARGET_IMAGE="${ROOT_IMG_NAME}-cni-${CNI_PLUGIN}-${KUBERNETES_VERSION}-${CONTAINER_ENGINE}-${SEED_ARCH}"
fi
MACHINES_TYPES=$(jq --argjson VOLUME_SIZE ${VOLUME_SIZE} --arg VOLUME_TYPE ${VOLUME_TYPE} 'with_entries(.value += {"diskType": $VOLUME_TYPE, "diskSize": $VOLUME_SIZE})' templates/machines/${SEED_ARCH}.json)

SSH_KEY_FNAME="$(basename ${SSH_PRIVATE_KEY})"
SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub"

TARGET_CONFIG_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/config
TARGET_DEPLOY_LOCATION=${CONFIGURATION_LOCATION}/config/${NODEGROUP_NAME}/deployment
TARGET_CLUSTER_LOCATION=${CONFIGURATION_LOCATION}/cluster/${NODEGROUP_NAME}

if [ "${EXTERNAL_ETCD}" = "true" ]; then
    EXTERNAL_ETCD_ARGS="--use-external-etcd"
    ETCD_DST_DIR="/etc/etcd/ssl"
else
    EXTERNAL_ETCD_ARGS="--no-use-external-etcd"
    ETCD_DST_DIR="/etc/kubernetes/pki/etcd"
fi

# Check if we can resume the creation process
if [ "${DELETE_CLUSTER}" = "YES" ]; then
    delete-masterkube.sh --configuration-location=${CONFIGURATION_LOCATION} --defs=${PLATEFORMDEFS} --node-group=${NODEGROUP_NAME}
    exit
elif [ ! -f ${TARGET_CONFIG_LOCATION}/buildenv ] && [ "${RESUME}" = "YES" ]; then
    echo_red "Unable to resume, building env is not found"
    exit -1
fi

# Check if ssh private key exists
if [ ! -f ${SSH_PRIVATE_KEY} ]; then
    echo_red "The private ssh key: ${SSH_PRIVATE_KEY} is not found"
    exit -1
fi

# Check if ssh public key exists
if [ ! -f ${SSH_PUBLIC_KEY} ]; then
    echo_red "The private ssh key: ${SSH_PUBLIC_KEY} is not found"
    exit -1
fi

SSH_KEY=$(cat "${SSH_PUBLIC_KEY}")

# If we use AWS CNI, install eni-max-pods.txt definition file
if [ ${CNI_PLUGIN} = "aws" ]; then
    MAX_PODS=$(curl -s "https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/eni-max-pods.txt" | grep ^${AUTOSCALE_MACHINE} | awk '{print $2}')

    if [ -z "${MAX_PODS}" ]; then
        echo_red "No entry for ${AUTOSCALE_MACHINE} in eni-max-pods.txt. Not setting ${MAX_PODS} max pods for kubelet"
    fi
fi

# If no master instance profile defined, use the default
if [ -z ${MASTER_INSTANCE_PROFILE_ARN} ]; then
    MASTER_INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-profile-name ${MASTER_PROFILE_NAME} 2> /dev/null | jq -r '.InstanceProfile.Arn // ""')

    # If not found, create it
    if [ -z ${MASTER_INSTANCE_PROFILE_ARN} ]; then
        aws iam create-role --profile ${AWS_PROFILE} --region ${AWS_REGION} --role-name ${MASTER_PROFILE_NAME} --assume-role-policy-document file://templates/profile/master/trusted.json &> /dev/null
        aws iam put-role-policy --profile ${AWS_PROFILE} --region ${AWS_REGION} --role-name ${MASTER_PROFILE_NAME} --policy-name kubernetes-master-permissions --policy-document file://templates/profile/master/permissions.json &> /dev/null
        aws iam create-instance-profile --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-profile-name ${MASTER_PROFILE_NAME} &> /dev/null
        aws iam add-role-to-instance-profile --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-profile-name ${MASTER_PROFILE_NAME} --role-name ${MASTER_PROFILE_NAME} &> /dev/null

        MASTER_INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-profile-name ${MASTER_PROFILE_NAME} | jq -r '.InstanceProfile.Arn // ""')
    fi
fi

# If no worker instance profile defined, use the default
if [ -z ${WORKER_INSTANCE_PROFILE_ARN} ]; then
    WORKER_INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-profile-name ${WORKER_PROFILE_NAME} 2> /dev/null | jq -r '.InstanceProfile.Arn // ""')

    # If not found, create it
    if [ -z ${WORKER_INSTANCE_PROFILE_ARN} ]; then
        aws iam create-role --profile ${AWS_PROFILE} --region ${AWS_REGION} --role-name ${WORKER_PROFILE_NAME} --assume-role-policy-document file://templates/profile/worker/trusted.json &> /dev/null
        aws iam put-role-policy --profile ${AWS_PROFILE} --region ${AWS_REGION} --role-name ${WORKER_PROFILE_NAME} --policy-name kubernetes-worker-permissions --policy-document file://templates/profile/worker/permissions.json &> /dev/null
        aws iam create-instance-profile --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-profile-name ${WORKER_PROFILE_NAME} &> /dev/null
        aws iam add-role-to-instance-profile --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-profile-name ${WORKER_PROFILE_NAME} --role-name ${WORKER_PROFILE_NAME} &> /dev/null

        WORKER_INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-profile-name ${WORKER_PROFILE_NAME} | jq -r '.InstanceProfile.Arn // ""')
    fi
fi

# Grab domain name from route53
if [ -n "${AWS_ROUTE53_PRIVATE_ZONE_ID}" ]; then
    ROUTE53_ZONE_NAME=$(aws route53 get-hosted-zone --id  ${AWS_ROUTE53_PRIVATE_ZONE_ID} --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} 2>/dev/null| jq -r '.HostedZone.Name // ""')

    if [ -z "${ROUTE53_ZONE_NAME}" ]; then
        echo_red_bold "The zone: ${AWS_ROUTE53_PRIVATE_ZONE_ID} does not exist, exit"
        exit 1
    fi

    ROUTE53_ZONE_NAME=${ROUTE53_ZONE_NAME%?}
fi

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

# Tag VPC & Subnet
IFS=, read -a VPC_PUBLIC_SUBNET_IDS <<< "${VPC_PUBLIC_SUBNET_ID}"

for SUBNET in ${VPC_PUBLIC_SUBNET_IDS[*]}
do
    TAGGED=$(aws ec2 describe-subnets --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=subnet-id,Values=${SUBNET}" | jq -r ".Subnets[].Tags[]|select(.Key == \"kubernetes.io/cluster/${NODEGROUP_NAME}\")|.Value")
    if [ -z ${TAGGED} ]; then
        aws ec2 create-tags --profile ${AWS_PROFILE} --region ${AWS_REGION} --resources ${SUBNET} --tags "Key=kubernetes.io/cluster/${NODEGROUP_NAME},Value=owned" 2> /dev/null
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
IFS=, read -a VPC_PRIVATE_SUBNET_IDS <<< "${VPC_PRIVATE_SUBNET_ID}"

for SUBNET in ${VPC_PRIVATE_SUBNET_IDS[*]}
do
    NETINFO=$(aws ec2 describe-subnets --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=subnet-id,Values=${SUBNET}")
    TAGGED=$(echo "${NETINFO}" | jq -r ".Subnets[].Tags[]|select(.Key == \"kubernetes.io/cluster/${NODEGROUP_NAME}\")|.Value")
    BASE_IP=$(echo "${NETINFO}" | jq -r .Subnets[].CidrBlock | sed -E 's/(\w+\.\w+\.\w+).\w+\/\w+/\1/')

    if [ -z ${TAGGED} ]; then
        aws ec2 create-tags --profile ${AWS_PROFILE} --region ${AWS_REGION} --resources ${SUBNET} --tags "Key=kubernetes.io/cluster/${NODEGROUP_NAME},Value=owned" 2> /dev/null
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

KEYEXISTS=$(aws ec2 describe-key-pairs --profile ${AWS_PROFILE} --region ${AWS_REGION} --key-names "${SSH_KEYNAME}" | jq -r '.KeyPairs[].KeyName // ""')
ECR_PASSWORD=$(aws ecr get-login-password  --profile ${AWS_PROFILE} --region us-west-2)

if [ -z ${KEYEXISTS} ]; then
    echo_grey "SSH Public key doesn't exist"
    aws ec2 import-key-pair --profile ${AWS_PROFILE} --region ${AWS_REGION} --key-name ${SSH_KEYNAME} --public-key-material "file://${SSH_PUBLIC_KEY}"
else
    echo_grey "SSH Public key already exists"
fi

# GRPC network endpoint
if [ "${LAUNCH_CA}" != "YES" ]; then
    SSH_PRIVATE_KEY_LOCAL="${SSH_PRIVATE_KEY}"

    if [ "${TRANSPORT}" == "unix" ]; then
        LISTEN="unix:/var/run/cluster-autoscaler/autoscaler.sock"
        CONNECTTO="unix:/var/run/cluster-autoscaler/autoscaler.sock"
    elif [ "${TRANSPORT}" == "tcp" ]; then
        LISTEN="tcp://${LOCAL_IPADDR}:5200"
        CONNECTTO="${LOCAL_IPADDR}:5200"
    else
        echo_red "Unknown transport: ${TRANSPORT}, should be unix or tcp"
        exit -1
    fi
else
    SSH_PRIVATE_KEY_LOCAL="/etc/ssh/id_rsa"
    TRANSPORT=unix
    LISTEN="unix:/var/run/cluster-autoscaler/autoscaler.sock"
    CONNECTTO="unix:/var/run/cluster-autoscaler/autoscaler.sock"
fi

echo_blue_bold "Transport set to:${TRANSPORT}, listen endpoint at ${LISTEN}"

# If CERT doesn't exist, create one autosigned
if [ ! -f ${SSL_LOCATION}/privkey.pem ]; then
    if [ -z "${PUBLIC_DOMAIN_NAME}" ]; then
        ACM_DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}
    else
        ACM_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
    fi

    echo_blue_bold "Create autosigned certificat for domain: ${ACM_DOMAIN_NAME}"
    ${CURDIR}/create-cert.sh --domain ${ACM_DOMAIN_NAME} --ssl-location ${SSL_LOCATION} --cert-email ${CERT_EMAIL}
fi

if [ ! -f ${SSL_LOCATION}/cert.pem ]; then
    echo_red "${SSL_LOCATION}/cert.pem not found, exit"
    exit 1
fi

if [ ! -f ${SSL_LOCATION}/fullchain.pem ]; then
    echo_red "${SSL_LOCATION}/fullchain.pem not found, exit"
    exit 1
fi

TARGET_IMAGE_AMI=$(aws ec2 describe-images --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=name,Values=${TARGET_IMAGE}" | jq -r '.Images[0].ImageId // ""')

# Extract the domain name from CERT
ACM_DOMAIN_NAME=$(openssl x509 -noout -subject -in ${SSL_LOCATION}/cert.pem -nameopt sep_multiline | grep 'CN=' | awk -F= '{print $2}' | sed -e 's/^[\s\t]*//')

# Drop wildcard
DOMAIN_NAME=$(echo -n $ACM_DOMAIN_NAME | sed 's/\*\.//g')
CERT_DOMAIN=${DOMAIN_NAME}

if [ "${DOMAIN_NAME}" != "${PRIVATE_DOMAIN_NAME}" ] && [ "${DOMAIN_NAME}" != "${PUBLIC_DOMAIN_NAME}" ]; then
    echo_red "Warning: The provided domain ${CERT_DOMAIN} from certificat does not target domain ${PRIVATE_DOMAIN_NAME} or ${PUBLIC_DOMAIN_NAME}"

    if [ -z "${PUBLIC_DOMAIN_NAME}" ]; then
        DOMAIN_NAME=${PRIVATE_DOMAIN_NAME}
    else
        DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}
    fi
fi

# ACM Keep the wildcard
ACM_CERTIFICATE_ARN=$(aws acm list-certificates --profile ${AWS_PROFILE} --region ${AWS_REGION} --include keyTypes=RSA_1024,RSA_2048,EC_secp384r1,EC_prime256v1,EC_secp521r1,RSA_3072,RSA_4096 \
    | jq -r --arg DOMAIN_NAME "${ACM_DOMAIN_NAME}" '.CertificateSummaryList[]|select(.DomainName == $DOMAIN_NAME)|.CertificateArn // ""')

if [ -n "${ACM_CERTIFICATE_ARN}" ]; then
	ACM_CERTIFICATE_ARN="--certificate-arn=${ACM_CERTIFICATE_ARN}"
else
	ACM_CERTIFICATE_TAGGING="--tags Key=Name,Value=${ACM_DOMAIN_NAME}"
fi

ACM_CERTIFICATE_ARN=$(aws acm import-certificate ${ACM_CERTIFICATE_ARN} ${ACM_CERTIFICATE_TAGGING} \
		--profile ${AWS_PROFILE} --region ${AWS_REGION} \
        --certificate fileb://${SSL_LOCATION}/cert.pem \
		--private-key fileb://${SSL_LOCATION}/privkey.pem | jq -r '.CertificateArn // ""')

if [ -z "${ACM_CERTIFICATE_ARN}" ]; then
    echo_red "ACM_CERTIFICATE_ARN is empty after creation, something goes wrong"
    exit 1
fi

# If the VM template doesn't exists, build it from scrash
if [ -z "${TARGET_IMAGE_AMI}" ]; then
    echo_blue_bold "Create aws preconfigured image ${TARGET_IMAGE}"

    if [ ${CONTROLPLANE_USE_PUBLICIP} == "true" ]; then
        SUBNETID=${VPC_PUBLIC_SUBNET_IDS[0]}
        SGID=${VPC_PUBLIC_SECURITY_GROUPID}
    else
        SUBNETID=${VPC_PRIVATE_SUBNET_IDS[0]}
        SGID=${VPC_PRIVATE_SECURITY_GROUPID}
    fi

    ./bin/create-image.sh \
		--plateform=${PLATEFORM} \
        --k8s-distribution=${KUBERNETES_DISTRO} \
        --profile="${AWS_PROFILE}" \
        --region="${AWS_REGION}" \
        --cni-plugin-version="${CNI_VERSION}" \
        --cni-plugin="${CNI_PLUGIN}" \
        --ecr-password="${ECR_PASSWORD}" \
        --custom-image="${TARGET_IMAGE}" \
        --kubernetes-version="${KUBERNETES_VERSION}" \
        --container-runtime=${CONTAINER_ENGINE} \
        --cache=${CACHE} \
        --arch="${SEED_ARCH}" \
        --ami="${SEED_IMAGE}" \
        --user="${KUBERNETES_USER}" \
        --ssh-key-name="${SSH_KEYNAME}" \
        --subnet-id="${SUBNETID}" \
        --sg-id="${SGID}" \
        --use-public-ip="${CONTROLPLANE_USE_PUBLICIP}"
fi

if [ "${CREATE_IMAGE_ONLY}" = "YES" ]; then
    echo_blue_bold "Create image only, done..."
    exit 0
fi

TARGET_IMAGE_AMI=$(aws ec2 describe-images --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=name,Values=${TARGET_IMAGE}" | jq -r '.Images[0].ImageId // ""')

if [ ${GRPC_PROVIDER} = "grpc" ]; then
    CLOUD_PROVIDER_CONFIG=grpc-config.json
else
    CLOUD_PROVIDER_CONFIG=grpc-config.yaml
fi

if [ -z "${TARGET_IMAGE_AMI}" ]; then
    echo_red "AMI ${TARGET_IMAGE} not found"
    exit -1
fi

# Delete previous existing version
if [ "$RESUME" = "NO" ] && [ "${UPGRADE_CLUSTER}" == "NO" ]; then
    echo_title "Launch custom ${MASTERKUBE} instance with ${TARGET_IMAGE}" > /dev/stderr
    delete-masterkube.sh --configuration-location=${CONFIGURATION_LOCATION} --aws-defs=${PLATEFORMDEFS} --node-group=${NODEGROUP_NAME}
elif [ "${UPGRADE_CLUSTER}" == "NO" ]; then
    echo_title "Resume custom ${MASTERKUBE} instance with ${TARGET_IMAGE}" > /dev/stderr
else
    echo_title "Upgrade ${MASTERKUBE} instance with ${TARGET_IMAGE}"
	./bin/upgrade-cluster.sh
	exit
fi

mkdir -p ${TARGET_CONFIG_LOCATION}
mkdir -p ${TARGET_DEPLOY_LOCATION}
mkdir -p ${TARGET_CLUSTER_LOCATION}

if [ "${RESUME}" = "NO" ]; then
    if [ -n "${PUBLIC_DOMAIN_NAME}" ]; then
        AWS_ROUTE53_PUBLIC_ZONE_ID=$(aws route53 list-hosted-zones-by-name --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} --dns-name ${PUBLIC_DOMAIN_NAME} | jq --arg DNSNAME "${PUBLIC_DOMAIN_NAME}." -r '.HostedZones[]|select(.Name == $DNSNAME)|.Id//""' | sed -E 's/\/hostedzone\/(\w+)/\1/')
        if [ -z "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then
            echo_red_bold "No Route53 for PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME}"
        else
            echo_blue_bold "Found PUBLIC_DOMAIN_NAME=${PUBLIC_DOMAIN_NAME} AWS_ROUTE53_PUBLIC_ZONE_ID=$AWS_ROUTE53_PUBLIC_ZONE_ID"
            echo_red_bold "Route53 will be used to register public domain hosts"
            # Disable GoDaddy registration
            CERT_GODADDY_API_KEY=
            CERT_GODADDY_API_SECRET=
        fi
    fi

    update_build_env
else
    source ${TARGET_CONFIG_LOCATION}/buildenv
fi

EVAL=$(sed -i '/NODE_INDEX/d' ${TARGET_CONFIG_LOCATION}/buildenv)

if [ ${WORKERNODES} -eq 0 ]; then
    MASTER_NODE_ALLOW_DEPLOYMENT=YES
else
    MASTER_NODE_ALLOW_DEPLOYMENT=NO
fi

if [ ${HA_CLUSTER} = "true" ]; then
    if [ "${USE_NLB}" = "YES" ]; then
        FIRSTNODE=1
        if [ "${USE_NGINX_GATEWAY}" = "YES" ]; then
            CONTROLNODE_INDEX=$((FIRSTNODE + ${#VPC_PUBLIC_SUBNET_IDS[*]}))
            LASTNODE_INDEX=$((WORKERNODES + ${CONTROLNODES} + ${#VPC_PUBLIC_SUBNET_IDS[*]}))
        else
            CONTROLNODE_INDEX=1
            LASTNODE_INDEX=$((WORKERNODES + ${CONTROLNODES}))
        fi
    elif [ "${CONTROLPLANE_USE_PUBLICIP}" = "true" ]; then
        CONTROLNODE_INDEX=0
        LASTNODE_INDEX=$((WORKERNODES + ${CONTROLNODES} -1))
    else
        CONTROLNODE_INDEX=${#VPC_PUBLIC_SUBNET_IDS[*]}
        LASTNODE_INDEX=$((WORKERNODES + ${CONTROLNODES} + ${#VPC_PUBLIC_SUBNET_IDS[*]} - 1))
    fi
else
    CONTROLNODES=1
    CONTROLNODE_INDEX=0
    LASTNODE_INDEX=${WORKERNODES}
    EXTERNAL_ETCD=false

    if [ "${EXPOSE_PUBLIC_CLUSTER}" != "${CONTROLPLANE_USE_PUBLICIP}" ]; then
        if [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then

            if [ ${USE_NLB} = "YES" ]; then
                FIRSTNODE=1
            fi

            CONTROLNODE_INDEX=1
            LASTNODE_INDEX=$((LASTNODE_INDEX + 1))
        fi
    fi
fi

WORKERNODE_INDEX=$((CONTROLNODE_INDEX + ${CONTROLNODES}))

echo "export FIRSTNODE=$FIRSTNODE" >> ${TARGET_CONFIG_LOCATION}/buildenv
echo "export LASTNODE_INDEX=$LASTNODE_INDEX" >> ${TARGET_CONFIG_LOCATION}/buildenv
echo "export CONTROLNODE_INDEX=$CONTROLNODE_INDEX" >> ${TARGET_CONFIG_LOCATION}/buildenv
echo "export WORKERNODE_INDEX=$WORKERNODE_INDEX" >> ${TARGET_CONFIG_LOCATION}/buildenv

#===========================================================================================================================================
#
#===========================================================================================================================================
function named_index_suffix() {
    local INDEX=$1

    local SUFFIX="0${INDEX}"

    echo ${SUFFIX:(-2)}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function wait_nlb_ready() {
    echo_blue_dot_title "Wait for ELB start on IP: ${CONTROL_PLANE_ENDPOINT}:6443"

    while :
    do
        echo_blue_dot
        curl -s -k --connect-timeout 1 "https://${CONTROL_PLANE_ENDPOINT}:6443" &> /dev/null && break
        sleep 1
    done
    echo

    echo_line

    echo -n ${CONTROL_PLANE_ENDPOINT}:6443 > ${TARGET_CLUSTER_LOCATION}/manager-ip
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_instance_name() {
    local INDEX=$1
    local SUFFIX=$(named_index_suffix $INDEX)
    local NODEINDEX=
    local MASTERKUBE_NODE=

    if [ ${HA_CLUSTER} = "true" ]; then
        if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
            if [ $FIRSTNODE -eq 0 ]; then
                NODEINDEX=$((INDEX + 1))
            else
                NODEINDEX=$INDEX
            fi

            if [ ${CONTROLNODE_INDEX} -gt 1 ]; then
                MASTERKUBE_NODE="${MASTERKUBE}-$(named_index_suffix $NODEINDEX)"
            else
                MASTERKUBE_NODE="${MASTERKUBE}"
            fi
        elif [ ${INDEX} -lt $((CONTROLNODE_INDEX + ${CONTROLNODES})) ]; then
            NODEINDEX=$((INDEX - ${CONTROLNODE_INDEX} + 1))
            MASTERKUBE_NODE="${NODEGROUP_NAME}-master-$(named_index_suffix $NODEINDEX)"
        else
            NODEINDEX=$((INDEX - ${CONTROLNODES} - ${CONTROLNODE_INDEX} + 1))
            MASTERKUBE_NODE="${NODEGROUP_NAME}-worker-$(named_index_suffix $NODEINDEX)"
        fi
    else
        if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
            NODEINDEX=1
            MASTERKUBE_NODE="${MASTERKUBE}"
        elif [ ${INDEX} -eq ${CONTROLNODE_INDEX} ]; then
            NODEINDEX=1
            MASTERKUBE_NODE="${NODEGROUP_NAME}-master-01"
        else
            NODEINDEX=$((INDEX - ${CONTROLNODE_INDEX}))
            MASTERKUBE_NODE="${NODEGROUP_NAME}-worker-$(named_index_suffix $NODEINDEX)"
        fi
    fi

    echo -n "${NODEINDEX} ${SUFFIX} ${MASTERKUBE_NODE}"
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_vm() {
    local INDEX=$1
    local NETWORK_INTERFACE_ID=${RESERVED_ENI[$INDEX]}
    local IPADDR=${PRIVATE_ADDR_IPS[$INDEX]}
    local MACHINE_TYPE=${WORKER_NODE_MACHINE}
    local MASTERKUBE_NODE=
    local SUFFIX=
    local INSTANCE_ID=
    local NODEINDEX=
    local ROUTE53_ENTRY=

    read NODEINDEX SUFFIX MASTERKUBE_NODE <<< "$(get_instance_name ${INDEX})"

    LAUNCHED_INSTANCE=$(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=tag:Name,Values=${MASTERKUBE_NODE}" | jq -r '.Reservations[].Instances[]|select(.State.Code == 16)' )

    if [ -z $(echo ${LAUNCHED_INSTANCE} | jq '.InstanceId') ]; then
        # Cloud init user-data
        cat > ${TARGET_CONFIG_LOCATION}/userdata-${SUFFIX}.yaml <<EOF
#cloud-config
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
        local SUBNET_INDEX=$(( $((NODEINDEX - 1)) % $VPC_LENGTH ))
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
            aws ec2 modify-instance-attribute --profile "${AWS_PROFILE}" --region "${AWS_REGION}" --instance-id=${LAUNCHED_ID} --no-source-dest-check
        fi

        echo_blue_bold "Wait for ${MASTERKUBE_NODE} instanceID ${LAUNCHED_ID} to boot"

        while [ ! $(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids "${LAUNCHED_ID}" | jq -r '.Reservations[0].Instances[0].State.Code') -eq 16 ];
        do
            sleep 1
        done

        LAUNCHED_INSTANCE=$(aws ec2  describe-instances --profile ${AWS_PROFILE} --region ${AWS_REGION} --instance-ids ${LAUNCHED_ID} | jq .Reservations[0].Instances[0])

        IPADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateIpAddress // ""')
        PUBADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PublicIpAddress // ""')
        PRIVATEDNS=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateDnsName // ""')

        if [ -z "${PUBADDR}" ] || [ "${PREFER_SSH_PUBLICIP}" = "NO" ]; then
            SSHADDR=${IPADDR}
        else
            SSHADDR=$(echo ${LAUNCHED_INSTANCE} | jq -r '.PublicIpAddress // ""')
        fi

        if [ "${PUBLICIP}" = "true" ] || [ -z ${NETWORK_INTERFACE_ID} ]; then
            NETWORK_INTERFACE_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.NetworkInterfaces[0].NetworkInterfaceId // ""')
            ENI=$(aws ec2 describe-network-interfaces --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters Name=network-interface-id,Values=${NETWORK_INTERFACE_ID} 2> /dev/null | jq -r '.NetworkInterfaces[0]//""')
            echo $ENI | jq . > ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json
        fi

        ROUTE53_ENTRY=$(cat <<EOF
{
    "Comment": "${MASTERKUBE_NODE} private DNS entry",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}",
                "Type": "A",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "${IPADDR}"
                    }
                ]
            }
        }
    ]
}
EOF
)
        add_host "${IPADDR} ${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}"

        # Record kubernetes node in Route53 DNS
        if [ -n "${AWS_ROUTE53_PRIVATE_ZONE_ID}" ]; then

            echo ${ROUTE53_ENTRY} | jq --arg HOSTNAME "${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}" '.Changes[0].ResourceRecordSet.Name = $HOSTNAME' >  ${TARGET_CONFIG_LOCATION}/dns-private-${SUFFIX}.json

            aws route53 change-resource-record-sets --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} --hosted-zone-id ${AWS_ROUTE53_PRIVATE_ZONE_ID} \
                --change-batch file://${TARGET_CONFIG_LOCATION}/dns-private-${SUFFIX}.json > /dev/null

        elif [ ${INDEX} -ge ${CONTROLNODE_INDEX} ] && [ -n "${PUBLIC_DOMAIN_NAME}" ]; then

            # Register node in public zone DNS if we don't use private DNS

            if [ -n "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then

                # Register kubernetes nodes in route53
                echo ${ROUTE53_ENTRY} | jq --arg HOSTNAME "${MASTERKUBE_NODE}.${PUBLIC_DOMAIN_NAME}" '.Changes[0].ResourceRecordSet.Name = $HOSTNAME' > ${TARGET_CONFIG_LOCATION}/dns-public-${SUFFIX}.json
                aws route53 change-resource-record-sets --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} \
                    --hosted-zone-id ${AWS_ROUTE53_PUBLIC_ZONE_ID} \
                    --change-batch file://${TARGET_CONFIG_LOCATION}/dns-public-${SUFFIX}.json > /dev/null

            elif [ -n ${CERT_GODADDY_API_KEY} ]; then

                # Register kubernetes nodes in godaddy if we don't use route53
                curl -s -X PUT "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/A/${MASTERKUBE_NODE}" \
                    -H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
                    -H "Content-Type: application/json" -d "[{\"data\": \"${IPADDR}\"}]"

            fi

        fi

        echo -n ${LAUNCHED_INSTANCE} | jq . > ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json

        echo_blue_bold "Wait for ssh ready on ${MASTERKUBE_NODE}, private-ip=${IPADDR}, ssh-ip=${SSHADDR}, public-ip=${PUBADDR}"

        sleep 5

        while :
        do
            ssh ${SSH_OPTIONS} -o ConnectTimeout=1 "${KUBERNETES_USER}@${SSHADDR}" sudo hostnamectl set-hostname "${MASTERKUBE_NODE}" 2>/dev/null && break
            sleep 1
        done

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

    ssh ${SSH_OPTIONS} "${KUBERNETES_USER}@${SSHADDR}" mkdir -p /home/${KUBERNETES_USER}/cluster 2>/dev/null
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function get_ssh_ip() {
    local INDEX=$1

    if [ ${PREFER_SSH_PUBLICIP} = "NO" ] || [ -z "${PUBLIC_ADDR_IPS[$INDEX]}" ]; then
        echo -n ${PRIVATE_ADDR_IPS[$INDEX]}
    else
        echo -n ${PUBLIC_ADDR_IPS[$INDEX]}
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================

function register_nlb_dns() {
    local PRIVATE_NLB_DNS=$1
    local PUBLIC_NLB_DNS=$2

    if [ -n ${AWS_ROUTE53_PRIVATE_ZONE_ID} ]; then
        echo_title "Register dns ${MASTERKUBE} in route53: ${AWS_ROUTE53_PRIVATE_ZONE_ID}"

        cat > ${TARGET_CONFIG_LOCATION}/dns-nlb.json <<EOF
{
    "Comment": "${MASTERKUBE} private DNS entry",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}",
                "Type": "CNAME",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "${PRIVATE_NLB_DNS}"
                    }
                ]
            }
        }
    ]
}
EOF

        aws route53 change-resource-record-sets --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} --hosted-zone-id ${AWS_ROUTE53_PRIVATE_ZONE_ID} \
            --change-batch file://${TARGET_CONFIG_LOCATION}/dns-nlb.json > /dev/null

        add_host "${PRIVATE_NLB_DNS} ${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}"
    fi

    if [ -n "${PUBLIC_DOMAIN_NAME}" ]; then
        if [ -n "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then
            echo_title "Register public dns ${MASTERKUBE} in route53: ${AWS_ROUTE53_PUBLIC_ZONE_ID}"

            cat > ${TARGET_CONFIG_LOCATION}/dns-public.json <<EOF
        {
            "Comment": "${MASTERKUBE} public DNS entry",
            "Changes": [
                {
                    "Action": "UPSERT",
                    "ResourceRecordSet": {
                        "Name": "${MASTERKUBE}.${PUBLIC_DOMAIN_NAME}",
                        "Type": "CNAME",
                        "TTL": 60,
                        "ResourceRecords": [
                            {
                                "Value": "${PUBLIC_NLB_DNS}"
                            }
                        ]
                    }
                }
            ]
        }
EOF

            aws route53 change-resource-record-sets --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} --hosted-zone-id ${AWS_ROUTE53_PUBLIC_ZONE_ID} \
                --change-batch file://${TARGET_CONFIG_LOCATION}/dns-public.json > /dev/null

        elif [ -n "${CERT_GODADDY_API_KEY}" ]; then
            curl -s -X PUT "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/CNAME/${MASTERKUBE}" \
                -H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
                -H "Content-Type: application/json" \
                -d "[{\"data\": \"${PUBLIC_NLB_DNS}\"}]"
        fi
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_load_balancer() {
    if [ "${HA_CLUSTER}" = "true" ] && [ "${USE_NLB}" = "YES" ]; then
        echo_title "Create NLB ${MASTERKUBE}"

        TARGET_VPC=$(aws ec2 describe-subnets --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters "Name=subnet-id,Values=${VPC_PRIVATE_SUBNET_ID}" | jq -r ".Subnets[0].VpcId")

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

        PRIVATE_NLB_DNS=$(aws elbv2 describe-load-balancers --profile=${AWS_PROFILE} --region=${AWS_REGION} | jq -r --arg NLB_NAME "c-${MASTERKUBE}" '.LoadBalancers[]|select(.LoadBalancerName == $NLB_NAME)|.DNSName')

        LOAD_BALANCER_IP="${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}"

        if [ "${EXPOSE_PUBLIC_CLUSTER}" = "true" ]; then
            PUBLIC_NLB_DNS=$(aws elbv2 describe-load-balancers --profile=${AWS_PROFILE} --region=${AWS_REGION} | jq -r --arg NLB_NAME "p-${MASTERKUBE}" '.LoadBalancers[]|select(.LoadBalancerName == $NLB_NAME)|.DNSName')
        else
            PUBLIC_NLB_DNS=${PRIVATE_NLB_DNS}
        fi

        # Record Masterkube in Route53 DNS
        register_nlb_dns ${PRIVATE_NLB_DNS} ${PUBLIC_NLB_DNS}
    fi

    echo "export PRIVATE_NLB_DNS=${PRIVATE_NLB_DNS}" >> ${TARGET_CONFIG_LOCATION}/buildenv
    echo "export PUBLIC_NLB_DNS=${PUBLIC_NLB_DNS}" >> ${TARGET_CONFIG_LOCATION}/buildenv

    if [ "${EXTERNAL_ETCD}" = "true" ]; then
        echo_title "Created etcd cluster: ${MASTER_NODES}"

        eval prepare-etcd.sh --node-group=${NODEGROUP_NAME} --cluster-nodes="${MASTER_NODES}" ${SILENT}

        for INDEX in $(seq 1 ${CONTROLNODES})
        do
            SUFFIX=$(named_index_suffix $INDEX)

            if [ ! -f ${TARGET_CONFIG_LOCATION}/etdc-${SUFFIX}-prepared ]; then
                INSTANCE_INDEX=$((${INDEX} + ${CONTROLNODE_INDEX} - 1))
                IPADDR=$(get_ssh_ip ${INSTANCE_INDEX})

                echo_title "Start etcd node: ${IPADDR}"
                
                eval scp ${SCP_OPTIONS} bin ${KUBERNETES_USER}@${IPADDR}:~ ${SILENT}
                eval scp ${SCP_OPTIONS} cluster/${NODEGROUP_NAME}/* ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}
                eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo cp /home/${KUBERNETES_USER}/bin/* /usr/local/bin ${SILENT}

                eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-etcd.sh \
                    --user=${KUBERNETES_USER} \
                    --cluster-nodes="${MASTER_NODES}" \
                    --node-index="${INDEX}" ${SILENT}

                touch ${TARGET_CONFIG_LOCATION}/etdc-${SUFFIX}-prepared
            fi
        done
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function start_kubernes_on_instances() {
    local MASTER_IP=

    for INDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
    do
        local LAUNCHED_INSTANCE=LAUNCHED_INSTANCES[${INDEX}]
        local MASTERKUBE_NODE=
        local CERT_EXTRA_SANS=
        local NODEINDEX=
        local SUFFIX=

        read NODEINDEX SUFFIX MASTERKUBE_NODE <<< "$(get_instance_name $INDEX)"

        if [ -f ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}-prepared ]; then
            echo_title "Already prepared VM ${MASTERKUBE_NODE}"
        else
            IPADDR=$(get_ssh_ip ${INDEX})

            echo_title "Prepare VM ${MASTERKUBE_NODE} with IP:${IPADDR}"

            eval scp ${SCP_OPTIONS} bin ${KUBERNETES_USER}@${IPADDR}:~ ${SILENT}
            eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo mv /home/${KUBERNETES_USER}/bin/* /usr/local/bin ${SILENT}
            eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo chown root:root /usr/local/bin ${SILENT}

            NODEINDEX=$((INDEX - ${CONTROLNODE_INDEX}))

            if [ "${HA_CLUSTER}" = "true" ]; then
                # Start nginx load balancer
                if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
                    echo_blue_bold "Configure load balancer ${MASTERKUBE_NODE} instance in cluster mode"

                    eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-load-balancer.sh \
                        --master-nodes="${MASTER_NODES}" \
                        --control-plane-endpoint=${CONTROL_PLANE_ENDPOINT} \
                        --listen-port=${LOAD_BALANCER_PORT} \
                        --listen-ip="0.0.0.0" ${SILENT}

                    echo_blue_bold "Done configuring load balancer ${MASTERKUBE_NODE} instance in cluster mode"
                # Start join worker node
                elif [ ${INDEX} -ge $((CONTROLNODE_INDEX + ${CONTROLNODES})) ]; then
                    echo_blue_bold "Join node ${MASTERKUBE_NODE} instance worker node number ${NODEINDEX} in cluster mode, master-ip=${MASTER_IP}, kubernetes version=${KUBERNETES_VERSION}"

                    eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/*  ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

                    eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh \
                        --plateform=${PLATEFORM} \
                        --cloud-provider=external \
                        --k8s-distribution=${KUBERNETES_DISTRO} \
                        --delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
                        --join-master=${MASTER_IP} \
                        --tls-san="${CERT_SANS}" \
                        --use-external-etcd=${EXTERNAL_ETCD} \
                        --node-group=${NODEGROUP_NAME} \
                        --node-index=${NODEINDEX} ${SILENT}

                    echo_blue_bold "Worker node ${MASTERKUBE_NODE} joined cluster in cluster mode"
                # Start create first master node
                elif [ ${INDEX} = ${CONTROLNODE_INDEX} ]; then
                    echo_blue_bold "Start kubernetes ${MASTERKUBE_NODE} instance master node number ${NODEINDEX} in cluster mode, kubernetes version=${KUBERNETES_VERSION}"

                    ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo create-cluster.sh \
                        --plateform=${PLATEFORM} \
                        --cloud-provider=external \
                        --plateform=${PLATEFORM} \
                        --cloud-provider=external \
                        --k8s-distribution=${KUBERNETES_DISTRO} \
                        --delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
                        --max-pods=${MAX_PODS} \
                        --ecr-password=${ECR_PASSWORD} \
                        --allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
                        --private-zone-id="${AWS_ROUTE53_PRIVATE_ZONE_ID}" \
                        --private-zone-name="${PRIVATE_DOMAIN_NAME}" \
                        --use-external-etcd=${EXTERNAL_ETCD} \
                        --node-group=${NODEGROUP_NAME} \
                        --node-index=${NODEINDEX} \
                        --load-balancer-ip=${LOAD_BALANCER_IP} \
                        --tls-san="${CERT_SANS}" \
                        --container-runtime=${CONTAINER_ENGINE} \
                        --cluster-nodes="${CLUSTER_NODES}" \
                        --control-plane-endpoint="${CONTROL_PLANE_ENDPOINT}" \
                        --etcd-endpoint="${ETCD_ENDPOINT}" \
                        --ha-cluster=true \
                        --cni-plugin="${CNI_PLUGIN}" \
                        --kubernetes-version="${KUBERNETES_VERSION}" ${SILENT}

                    eval scp ${SCP_OPTIONS} ${KUBERNETES_USER}@${IPADDR}:/etc/cluster/* ${TARGET_CLUSTER_LOCATION}  ${SILENT}

                    wait_nlb_ready

                    MASTER_IP=${IPADDR}:6443

                    echo_blue_bold "Master ${MASTERKUBE_NODE} started in cluster mode, master-ip=${MASTER_IP}"
                # Start control-plane join master node
                else
                    echo_blue_bold "Join control-plane ${MASTERKUBE_NODE} instance master node number ${NODEINDEX} in cluster mode, master-ip=${MASTER_IP}, kubernetes version=${KUBERNETES_VERSION}"

                    eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/*  ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

                    eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh \
                        --plateform=${PLATEFORM} \
                        --cloud-provider=external \
                        --k8s-distribution=${KUBERNETES_DISTRO} \
                        --delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
                        --max-pods=${MAX_PODS} \
                        --join-master=${MASTER_IP} \
                        --tls-san="${CERT_SANS}" \
                        --allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
                        --control-plane=true \
                        --use-external-etcd=${EXTERNAL_ETCD} \
                        --node-group=${NODEGROUP_NAME} \
                        --node-index=${NODEINDEX} ${SILENT}

                    echo_blue_bold "Node control-plane ${MASTERKUBE_NODE} joined master node in cluster mode, master-ip=${MASTER_IP}"
                fi
            else
                # Start nginx load balancer
                if [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
                    echo_blue_bold "Configure load balancer ${MASTERKUBE_NODE} instance with ${MASTER_NODES}"

                    eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo install-load-balancer.sh \
                        --master-nodes="${MASTER_NODES}" \
                        --control-plane-endpoint=${CONTROL_PLANE_ENDPOINT} \
                        --listen-ip="0.0.0.0" ${SILENT}

                    echo_blue_bold "Done configuring load balancer ${MASTERKUBE_NODE} instance"
                # Single instance master node
                elif [ ${INDEX} = ${CONTROLNODE_INDEX} ]; then
                    echo_blue_bold "Start kubernetes ${MASTERKUBE_NODE} single instance master node number ${NODEINDEX}, kubernetes version=${KUBERNETES_VERSION}"

                    eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo create-cluster.sh \
                        --plateform=${PLATEFORM} \
                        --cloud-provider=external \
                        --k8s-distribution=${KUBERNETES_DISTRO} \
                        --delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
                        --max-pods=${MAX_PODS} \
                        --ecr-password=${ECR_PASSWORD} \
                        --allow-deployment=${MASTER_NODE_ALLOW_DEPLOYMENT} \
                        --private-zone-id="${AWS_ROUTE53_PRIVATE_ZONE_ID}" \
                        --private-zone-name="${PRIVATE_DOMAIN_NAME}" \
                        --tls-san="${CERT_SANS}" \
                        --container-runtime=${CONTAINER_ENGINE} \
                        --cluster-nodes="${CLUSTER_NODES}" \
                        --control-plane-endpoint="${CONTROL_PLANE_ENDPOINT}" \
                        --etcd-endpoint="${ETCD_ENDPOINT}" \
                        --node-group=${NODEGROUP_NAME} \
                        --node-index=${NODEINDEX} \
                        --cni-plugin="${CNI_PLUGIN}" \
                        --kubernetes-version="${KUBERNETES_VERSION}" ${SILENT}

                    eval scp ${SCP_OPTIONS} ${KUBERNETES_USER}@${IPADDR}:/etc/cluster/* ${CONFIGURATION_LOCATION}/cluster/${NODEGROUP_NAME}  ${SILENT}

                    MASTER_IP=${IPADDR}:6443

                    echo_blue_bold "Master ${MASTERKUBE_NODE} started master-ip=${MASTER_IP}"
                else
                    echo_blue_bold "Join node ${MASTERKUBE_NODE} instance worker node number ${NODEINDEX}, kubernetes version=${KUBERNETES_VERSION}"

                    eval scp ${SCP_OPTIONS} ${TARGET_CLUSTER_LOCATION}/*  ${KUBERNETES_USER}@${IPADDR}:~/cluster ${SILENT}

                    eval ssh ${SSH_OPTIONS} ${KUBERNETES_USER}@${IPADDR} sudo join-cluster.sh \
                        --plateform=${PLATEFORM} \
                        --cloud-provider=external \
                        --k8s-distribution=${KUBERNETES_DISTRO} \
                        --delete-credentials-provider=${DELETE_CREDENTIALS_CONFIG} \
                        --tls-san="${CERT_SANS}" \
                        --max-pods=${MAX_PODS} \
                        --join-master=${MASTER_IP} \
                        --control-plane=false \
                        --use-external-etcd=${EXTERNAL_ETCD} \
                        --node-group=${NODEGROUP_NAME} \
                        --node-index=${NODEINDEX} ${SILENT}

                    echo_blue_bold "Worker node ${MASTERKUBE_NODE} joined cluster"
                fi
            fi

            echo ${MASTERKUBE_NODE} > ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}-prepared
        fi

        echo_separator
    done
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_network_interfaces() {
    # Create ENI to capture IP addresses before launch instances

    local INDEX=$1
    local ENI_NAME=$2

    read NODEINDEX SUFFIX MASTERKUBE_NODE <<< "$(get_instance_name $INDEX)"

    local SUBNET_INDEX=$(( $((NODEINDEX - 1)) % ${#VPC_PRIVATE_SUBNET_IDS[@]} ))
    local SUBNETID="${VPC_PRIVATE_SUBNET_IDS[${SUBNET_INDEX}]}"
    local SGID="${VPC_PRIVATE_SECURITY_GROUPID}"
    local PUBLICIP=false
    local INFID=
    local ENI=

    if [ -z "${ENI_NAME}" ]; then
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
            ENI=$(aws ec2 describe-network-interfaces --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters Name=network-interface-id,Values=${INFID} 2> /dev/null | jq -r '.NetworkInterfaces[0]//""')

            if [ -z "${ENI}" ]; then
                echo_red_bold "Reserved ENI ${ENI_NAME} not found, network-interface-id=${INFID}, recreate it"
                rm ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json
            fi
        fi

        if [ ! -f ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json ]; then

            ENI=$(aws ec2 describe-network-interfaces --profile ${AWS_PROFILE} --region ${AWS_REGION} --filters Name=tag:Name,Values=${ENI_NAME} | jq -r '.NetworkInterfaces[0]//""')

            if [ -z "$ENI" ]; then
                # ENI doesn't exist
                echo_blue_bold "Create Reserved ENI ${ENI_NAME}, subnetid=${SUBNETID}, security group=${SGID}"

                ENI=$(aws ec2 create-network-interface --profile ${AWS_PROFILE} --region ${AWS_REGION} --subnet-id ${SUBNETID} --groups ${SGID} \
                    --description "Reserved ENI node[${INDEX}]" | jq '.NetworkInterface')

                INFID=$(echo $ENI | jq -r '.NetworkInterfaceId')

                aws ec2 create-tags --resources ${INFID} --tags \
                    "Key=Name,Value=${ENI_NAME}" \
                    "Key=PublicIP,Value=${PUBLICIP}" \
                    "Key=NodeGroup,Value=${NODEGROUP_NAME}" \
                    "Key=kubernetes.io/cluster/${NODEGROUP_NAME},Value=owned" \
                    "Key=KubernetesCluster,Value=${NODEGROUP_NAME}" 2> /dev/null
            else
                echo_blue_bold "Already created Reserved ENI ${ENI_NAME}"
            fi

            echo $ENI | jq . > ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json
        else
            echo_blue_bold "Use declared Reserved ENI ${ENI_NAME}"

            ENI=$(cat ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json)
        fi
    else
        echo_red_bold "Don't declare Reserved ENI ${ENI_NAME} because public IP required"

        rm -f ${TARGET_CONFIG_LOCATION}/eni-${SUFFIX}.json
    fi
}

#===========================================================================================================================================
#
#===========================================================================================================================================
function create_2_extras_eni() {
    local MORE_ADDRESSES=()
    local VPC_LENGTH=${#VPC_PRIVATE_SUBNET_IDS[@]}
    local SUBNET_INDEX=0

    if [ $CONTROLNODE_INDEX -gt 0 ]; then
        SUBNET_INDEX=$(( $((CONTROLNODE_INDEX - 1)) % $VPC_LENGTH ))
    fi

    for INDEX in $(seq 0 1 2)
    do
        if [ ${SUBNET_INDEX} != ${INDEX} ]; then
            local ENIINDEX=$((INDEX + ${LASTNODE_INDEX} + 1))
            local NODE_INDEX=$((INDEX + 1))

            create_network_interfaces ${ENIINDEX} ${NODEGROUP_NAME}-master-$(named_index_suffix $NODE_INDEX)

            local ENI=$(cat ${TARGET_CONFIG_LOCATION}/eni-$(named_index_suffix ${ENIINDEX}).json)
            local IPADDR=$(echo $ENI | jq -r '.PrivateIpAddresses[]|select(.Primary == true)|.PrivateIpAddress')
            local PRIVATEDNS=$(echo $ENI | jq -r '.PrivateDnsName')

            MORE_ADDRESSES+=(${IPADDR})
            MORE_ADDRESSES+=(${PRIVATEDNS})
        fi
    done

    echo ${MORE_ADDRESSES[@]}
}

#===========================================================================================================================================
#
#===========================================================================================================================================
for INDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
do
    create_network_interfaces ${INDEX}

    if [ -f ${TARGET_CONFIG_LOCATION}/eni-$(named_index_suffix ${INDEX}).json ]; then
        ENI=$(cat ${TARGET_CONFIG_LOCATION}/eni-$(named_index_suffix ${INDEX}).json)
        IPADDR=$(echo $ENI | jq -r '.PrivateIpAddresses[]|select(.Primary == true)|.PrivateIpAddress//""')
        INFID=$(echo $ENI | jq -r '.NetworkInterfaceId // ""')
    else
        IPADDR=
        INFID=
    fi

    RESERVED_ENI[$INDEX]=${INFID}
    PRIVATE_ADDR_IPS[$INDEX]=${IPADDR}

    create_vm ${INDEX} &
done

wait_jobs_finish

LOAD_BALANCER_IP=
GODADDY_REGISTER="[]"
PRIVATE_ROUTE53_REGISTER=$(cat << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}",
                "Type": "A",
                "TTL": 60,
                "ResourceRecords": [
                ]
            }
        }
    ]
}
EOF
)

PUBLIC_ROUTE53_REGISTER=$(cat << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${MASTERKUBE}.${PUBLIC_DOMAIN_NAME}",
                "Type": "A",
                "TTL": 60,
                "ResourceRecords": [
                ]
            }
        }
    ]
}
EOF
)

for INDEX in $(seq ${FIRSTNODE} ${LASTNODE_INDEX})
do
    SUFFIX=$(named_index_suffix $INDEX)
    LAUNCHED_INSTANCES[${INDEX}]=$(cat ${TARGET_CONFIG_LOCATION}/instance-${SUFFIX}.json)
    IPADDR=$(echo ${LAUNCHED_INSTANCES[${INDEX}]} | jq -r '.PrivateIpAddress // ""')
    PUBLICIPADDR=$(echo ${LAUNCHED_INSTANCES[${INDEX}]} | jq --arg IPADDR ${IPADDR} -r '.PublicIpAddress // $IPADDR')
    PRIVATE_ADDR_IPS[$INDEX]=${IPADDR}
    PUBLIC_ADDR_IPS[$INDEX]=${PUBLICIPADDR}
    REGISTER_IPADDR=NO

    if [ ${INDEX} -lt ${WORKERNODE_INDEX} ] && [ ${INDEX} -ge ${CONTROLNODE_INDEX} ] && [ ${EXPOSE_PUBLIC_CLUSTER} = "true" ] && [ "${CONTROLPLANE_USE_PUBLICIP}" = "true" ] && [ "${USE_NLB}" = "NO" ] && [ "${USE_NGINX_GATEWAY}" = "NO" ]; then
        REGISTER_IPADDR=YES
    elif [ ${INDEX} -eq 0 ] || [ ${INDEX} -lt ${CONTROLNODE_INDEX} ]; then
        REGISTER_IPADDR=YES
    fi

    if [ ${REGISTER_IPADDR} = "YES" ]; then
        PRIVATE_ROUTE53_REGISTER=$(echo ${PRIVATE_ROUTE53_REGISTER} | jq --arg IPADDR "${IPADDR}" '.Changes[0].ResourceRecordSet.ResourceRecords += [ { "Value": $IPADDR } ]')

        if [ -z "${PUBLICIPADDR}" ]; then
            GODADDY_REGISTER=$(echo ${GODADDY_REGISTER} | jq --arg IPADDR "${IPADDR}" '. += [ { "data": $IPADDR } ]')
            PUBLIC_ROUTE53_REGISTER=$(echo ${PUBLIC_ROUTE53_REGISTER} | jq --arg IPADDR "${IPADDR}" '.Changes[0].ResourceRecordSet.ResourceRecords += [ { "Value": $IPADDR } ]')
        else
            GODADDY_REGISTER=$(echo ${GODADDY_REGISTER} | jq --arg IPADDR "${PUBLICIPADDR}" '. += [ { "data": $IPADDR } ]')
            PUBLIC_ROUTE53_REGISTER=$(echo ${PUBLIC_ROUTE53_REGISTER} | jq --arg IPADDR "${PUBLICIPADDR}" '.Changes[0].ResourceRecordSet.ResourceRecords += [ { "Value": $IPADDR } ]')
        fi

        if [ -z ${LOAD_BALANCER_IP} ]; then
            LOAD_BALANCER_IP=${IPADDR}
        else
            LOAD_BALANCER_IP=${LOAD_BALANCER_IP},${IPADDR}
        fi
    fi
done

if [ "${USE_NLB}" = "NO" ] || [ "${HA_CLUSTER}" = "false" ]; then
    # Register in Route53 IP addresses point in private IP
    if [ -n ${AWS_ROUTE53_PRIVATE_ZONE_ID} ]; then
        echo ${PRIVATE_ROUTE53_REGISTER} | jq . > ${TARGET_CONFIG_LOCATION}/dns-nlb.json
        aws route53 change-resource-record-sets --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} \
            --hosted-zone-id ${AWS_ROUTE53_PRIVATE_ZONE_ID} \
            --change-batch file://${TARGET_CONFIG_LOCATION}/dns-nlb.json > /dev/null

        for IPADDR in $(echo ${LOAD_BALANCER_IP} | tr ',' ' ')
        do
            add_host "${IPADDR} ${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}"
        done
    fi

    if [ -n "${PUBLIC_DOMAIN_NAME}" ]; then
        if [ -n "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then
        
            # Register in Route53 IP addresses point in public IP
            echo ${PUBLIC_ROUTE53_REGISTER} | jq --arg HOSTNAME "${MASTERKUBE}.${PUBLIC_DOMAIN_NAME}" '.Changes[0].ResourceRecordSet.Name = $HOSTNAME' > ${TARGET_CONFIG_LOCATION}/dns-public.json
            aws route53 change-resource-record-sets --profile ${AWS_PROFILE_ROUTE53} --region ${AWS_REGION} \
                --hosted-zone-id ${AWS_ROUTE53_PUBLIC_ZONE_ID} \
                --change-batch file://${TARGET_CONFIG_LOCATION}/dns-public.json > /dev/null

        elif [ -n ${CERT_GODADDY_API_KEY} ]; then

            # Register in godaddy IP addresses point in public IP
            curl -s -X PUT "https://api.godaddy.com/v1/domains/${PUBLIC_DOMAIN_NAME}/records/A/${MASTERKUBE}" \
                -H "Authorization: sso-key ${CERT_GODADDY_API_KEY}:${CERT_GODADDY_API_SECRET}" \
                -H "Content-Type: application/json" \
                -d "${GODADDY_REGISTER}"

        fi
    fi
fi

CLUSTER_NODES=
CONTROLPLANE_INSTANCEID_NLB_TARGET=
ETCD_ENDPOINT=

EVAL=$(sed -i -e '/CLUSTER_NODES/d' -e '/NLB_DNS/d' -e '/MASTER_NODES/d' ${TARGET_CONFIG_LOCATION}/buildenv)

CONTROL_PLANE_ENDPOINT=${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}

if [ "${HA_CLUSTER}" = "true" ]; then

    IPADDR="${PRIVATE_ADDR_IPS[${CONTROLNODE_INDEX}]}"
    JOIN_IP="${IPADDR}:6443"

    for INDEX in $(seq 1 ${CONTROLNODES})
    do
        SUFFIX=$(named_index_suffix $INDEX)
        INSTANCE_INDEX=$((${INDEX} + ${CONTROLNODE_INDEX} - 1))
        LAUNCHED_INSTANCE=${LAUNCHED_INSTANCES[${INSTANCE_INDEX}]}
        INSTANCE_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.InstanceId // ""')
        MASTERKUBE_NODE="${NODEGROUP_NAME}-master-${SUFFIX}"
        IPADDR="${PRIVATE_ADDR_IPS[${INSTANCE_INDEX}]}"
        NODE_DNS="${MASTERKUBE_NODE}.${PRIVATE_DOMAIN_NAME}:${IPADDR}"
        PRIVATEDNS="$(echo ${LAUNCHED_INSTANCE} | jq -r '.PrivateDnsName // ""')"

        if [ -z "${CLUSTER_NODES}" ]; then
            CLUSTER_NODES="${NODE_DNS},${PRIVATEDNS}"
            MASTER_NODES="${NODE_DNS}"
        else
            CLUSTER_NODES="${CLUSTER_NODES},${NODE_DNS},${PRIVATEDNS}"
            MASTER_NODES="${MASTER_NODES},${NODE_DNS}"
        fi

        if [ "$EXTERNAL_ETCD" = "true" ]; then
            if [ -z "${ETCD_ENDPOINT}" ]; then
                ETCD_ENDPOINT="https://${IPADDR}:2379"
            else
                ETCD_ENDPOINT="${ETCD_ENDPOINT},https://${IPADDR}:2379"
            fi
        fi

        if [ -z ${CONTROLPLANE_INSTANCEID_NLB_TARGET} ]; then
            CONTROLPLANE_INSTANCEID_NLB_TARGET="${INSTANCE_ID}"
        else
            CONTROLPLANE_INSTANCEID_NLB_TARGET="${CONTROLPLANE_INSTANCEID_NLB_TARGET},${INSTANCE_ID}"
        fi

    done

    PUBLIC_INSTANCEID_NLB_TARGET=${CONTROLPLANE_INSTANCEID_NLB_TARGET}

    if [ "${USE_NGINX_GATEWAY}" = "YES" ]; then
        PUBLIC_INSTANCEID_NLB_TARGET=

        for INSTANCE_INDEX in $(seq ${FIRSTNODE} $((FIRSTNODE + ${#VPC_PUBLIC_SUBNET_IDS[*]} - 1)))
        do
            SUFFIX=$(named_index_suffix $INDEX)
            LAUNCHED_INSTANCE=${LAUNCHED_INSTANCES[${INSTANCE_INDEX}]}
            INSTANCE_ID=$(echo ${LAUNCHED_INSTANCE} | jq -r '.InstanceId // ""')

            if [ -z ${CONTROLPLANE_INSTANCEID_NLB_TARGET} ]; then
                PUBLIC_INSTANCEID_NLB_TARGET="${INSTANCE_ID}"
            else
                PUBLIC_INSTANCEID_NLB_TARGET="${PUBLIC_INSTANCEID_NLB_TARGET},${INSTANCE_ID}"
            fi

        done
    fi

    create_load_balancer
else
    # Allows to migrate single cluster to HA cluster with 2 more control plane
    echo_blue_bold "Create two extras ENI"
    read IPRESERVED2 PRIVATEDNS2 IPRESERVED3 PRIVATEDNS3 <<< "$(create_2_extras_eni)"

    LOAD_BALANCER_IP=${PRIVATE_ADDR_IPS[0]}
    IPADDR="${PRIVATE_ADDR_IPS[${CONTROLNODE_INDEX}]}"
    PRIVATEDNS=$(echo ${LAUNCHED_INSTANCES[${CONTROLNODE_INDEX}]} | jq -r '.PrivateDnsName')
    JOIN_IP="${IPADDR}:6443"

    echo_grey "IPADDR=${PRIVATEDNS}:${IPADDR} IPRESERVED2=${PRIVATEDNS2}:${IPRESERVED2} IPRESERVED3=${PRIVATEDNS3}:${IPRESERVED3}"

    CLUSTER_NODES="${NODEGROUP_NAME}-master-01.${PRIVATE_DOMAIN_NAME}:${IPADDR},${NODEGROUP_NAME}-master-02.${PRIVATE_DOMAIN_NAME}:${IPRESERVED2},${NODEGROUP_NAME}-master-03.${PRIVATE_DOMAIN_NAME}:${IPRESERVED3}"
    CLUSTER_NODES="${CLUSTER_NODES},${PRIVATEDNS}:${IPADDR},${PRIVATEDNS2}:${IPRESERVED2},${PRIVATEDNS3}:${IPRESERVED3}"
    MASTER_NODES="${MASTERKUBE}.${DOMAIN_NAME}:${IPADDR}"
fi

export CERT_SANS=$(collect_cert_sans "${LOAD_BALANCER_IP}" "${CLUSTER_NODES}" "${MASTERKUBE}.${DOMAIN_NAME},${MASTERKUBE}.${PRIVATE_DOMAIN_NAME}")

echo "export CLUSTER_NODES=${CLUSTER_NODES}" >> ${TARGET_CONFIG_LOCATION}/buildenv
echo "export MASTER_NODES=${MASTER_NODES}" >> ${TARGET_CONFIG_LOCATION}/buildenv
echo "export CERT_SANS=${CERT_SANS}" >> ${TARGET_CONFIG_LOCATION}/buildenv

### Bootstrap kubernetes
start_kubernes_on_instances

kubeconfig-merge.sh ${MASTERKUBE} ${TARGET_CLUSTER_LOCATION}/config

echo_blue_bold "create cluster done"

MASTER_IP=$(cat ${TARGET_CLUSTER_LOCATION}/manager-ip)
TOKEN=$(cat ${TARGET_CLUSTER_LOCATION}/token)
CACERT=$(cat ${TARGET_CLUSTER_LOCATION}/ca.cert)

if [ -z "${PUBLIC_DOMAIN_NAME}" ]; then
    kubectl create secret tls kube-system -n kube-system --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--key ${SSL_LOCATION}/privkey.pem \
		--cert ${SSL_LOCATION}/fullchain.pem | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
fi

kubectl create secret generic autoscaler-ssh-keys -n kube-system --dry-run=client -o yaml \
    --kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
    --from-file=id_rsa="${SSH_PRIVATE_KEY}" \
    --from-file=id_rsa.pub="${SSH_PUBLIC_KEY}" | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

echo_title "Write ${PLATEFORM} autoscaler provider config"

if [ ${GRPC_PROVIDER} = "grpc" ]; then
    cat > ${TARGET_CONFIG_LOCATION}/${CLOUD_PROVIDER_CONFIG} <<EOF
    {
        "address": "${CONNECTTO}",
        "secret": "${PLATEFORM}",
        "timeout": 300
    }
EOF
else
    echo "address: ${CONNECTTO}" > ${TARGET_CONFIG_LOCATION}/${CLOUD_PROVIDER_CONFIG}
fi

if [ "${KUBERNETES_DISTRO}" == "rke2" ]; then
    SERVER_ADDRESS="${MASTER_IP%%:*}:9345"
else
    SERVER_ADDRESS="${MASTER_IP}"
fi

if [ "${DELETE_CREDENTIALS_CONFIG}" == "YES" ]; then
    DELETE_CREDENTIALS_CONFIG=true
else
    DELETE_CREDENTIALS_CONFIG=false
fi

echo ${MACHINE_DEFS} | jq . > ${TARGET_CONFIG_LOCATION}/machines.json

echo $(eval "cat <<EOF
$(<${PWD}/templates/setup/autoscaler.json)
EOF") | jq . > ${TARGET_CONFIG_LOCATION}/autoscaler.json

PROVIDER_CONFIG=$(cat ../template/setup/provider.json)
IFS=, read -a VPC_PRIVATE_SUBNET_IDS <<< "${VPC_PRIVATE_SUBNET_ID}"
for SUBNET in ${VPC_PRIVATE_SUBNET_IDS[*]}
do
    PROVIDER_CONFIG=$(echo ${PROVIDER_CONFIG} | jq --arg SUBNET ${SUBNET} '.network.eni[0].subnets += [ $SUBNET ]')
done

echo "${PROVIDER_CONFIG}" | jq . > ${TARGET_CONFIG_LOCATION}/provider.json

source ./bin/create-deployment.sh
