#!/bin/bash
CURDIR=$(dirname $0)

#===========================================================================================================================================
#
#===========================================================================================================================================
function echo_red_bold() {
	# echo message in blue and bold
	>&2 echo -e "\x1B[90m= $(date '+%Y-%m-%d %T') \x1B[31m\x1B[1m\x1B[31m$1\x1B[0m\x1B[39m"
}

pushd ${CURDIR}/../ &>/dev/null

export ETC_DIR=${TARGET_DEPLOY_LOCATION}/external-dns
export KUBERNETES_TEMPLATE=./templates/external-dns

mkdir -p ${ETC_DIR}

if [ "${EXTERNAL_DNS_PROVIDER}" == "aws" ]; then
	if [ -n "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then
		cat > ${ETC_DIR}/credentials <<EOF
[default]
aws_access_key_id =  ${AWS_ROUTE53_ACCESSKEY} 
aws_secret_access_key = ${AWS_ROUTE53_SECRETKEY}
EOF

		kubectl create ns external-dns --dry-run=client -o yaml \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

		kubectl create configmap config-external-dns -n external-dns --dry-run=client -o yaml \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
			--from-literal=DOMAIN_NAME=${DOMAIN_NAME} \
			--from-literal=AWS_REGION=${AWS_REGION} | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

		kubectl create secret generic aws-external-dns -n external-dns --dry-run=client -o yaml \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
			--from-file ${ETC_DIR}/credentials | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

		[ "${DOMAIN_NAME}" = "${PRIVATE_DOMAIN_NAME}" ] && ZONE_TYPE=private || ZONE_TYPE=public

		sed -e "s/__ZONE_TYPE__/${ZONE_TYPE}/g" \
			-e "s/__AWS_REGION__/${AWS_REGION}/g" \
			-e "s/__DOMAIN_NAME__/${DOMAIN_NAME}/g" \
			-e "s/__PLATEFORM__/${PLATEFORM}/g" \
			${KUBERNETES_TEMPLATE}/deploy-route53.yaml | tee ${ETC_DIR}/deploy.yaml | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
	else
		echo "AWS_ROUTE53_PUBLIC_ZONE_ID is not defined"
	fi

elif [ "${EXTERNAL_DNS_PROVIDER}" == "godaddy" ]; then
	sed -e "s/__DOMAIN_NAME__/${DOMAIN_NAME}/g" \
		-e "s/__GODADDY_API_KEY__/${CERT_GODADDY_API_KEY}/g" \
		-e "s/__GODADDY_API_SECRET__/${CERT_GODADDY_API_SECRET}/g" \
		-e "s/__NODEGROUP_NAME__/${NODEGROUP_NAME}/g" \
		-e "s/__PLATEFORM__/${PLATEFORM}/g" \
		${KUBERNETES_TEMPLATE}/deploy-godaddy.yaml \
		| tee ${ETC_DIR}/deploy.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
elif [ "${EXTERNAL_DNS_PROVIDER}" == "designate" ]; then
	kubectl create ns external-dns --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config | kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

	kubectl get cm openstack-env --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -n kube-system -o yaml \
		| sed -e 's/kube-system/external-dns/g' \
		| tee ${ETC_DIR}/openstack-env.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

	sed -e "s/__DOMAIN_NAME__/${DOMAIN_NAME}/g" \
		-e "s/__NODEGROUP_NAME__/${NODEGROUP_NAME}/g" \
		-e "s/__PLATEFORM__/${PLATEFORM}/g" \
		${KUBERNETES_TEMPLATE}/deploy-designate.yaml \
			| tee ${ETC_DIR}/deploy.yaml \
			| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

elif [ "${EXTERNAL_DNS_PROVIDER}" == "rfc2136" ]; then

	TSIG_KEYNAME=$(grep 'key' ${BIND9_RNDCKEY} | cut -d '"' -f 2)
	TSIG_ALGO=$(grep 'algorithm' ${BIND9_RNDCKEY} | cut -d ' ' -f 2 | cut -d ';' -f 1)
	TSIG_SECRET=$(grep 'secret' ${BIND9_RNDCKEY} | cut -d '"' -f 2)

	sed -e "s/__DOMAIN_NAME__/${DOMAIN_NAME}/g" \
		-e "s/__NODEGROUP_NAME__/${NODEGROUP_NAME}/g" \
		-e "s/__PLATEFORM__/${PLATEFORM}/g" \
		-e "s/__DNSHOST__/${PRIVATE_DNS}/g" \
		-e "s/__DNSPORT__/${BIND9_PORT}/g" \
		-e "s/__TSIG_SECRET__/${TSIG_SECRET}/g" \
		-e "s/__TSIG_ALGO__/${TSIG_ALGO}/g" \
		-e "s/__TSIG_KEYNAME__/${TSIG_KEYNAME}/g" \
		${KUBERNETES_TEMPLATE}/deploy-rfc2136.yaml \
			| tee ${ETC_DIR}/deploy.yaml \
			| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

fi
