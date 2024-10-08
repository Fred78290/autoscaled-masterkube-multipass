#!/bin/bash
CURDIR=$(dirname $0)

source "${CURDIR}/echo.sh"

function deploy {
	echo "Create ${ETC_DIR}/$1.json"

	CONFIG=$(eval "cat <<EOF
$(<${KUBERNETES_TEMPLATE}/$1.json)
EOF")

	if [ -z "${PUBLIC_DOMAIN_NAME}" ] || [ "${CERT_SELFSIGNED}" == "YES" ]; then
		echo ${CONFIG} | jq . > ${ETC_DIR}/cluster-issuer.json
	elif [ "${USE_ZEROSSL}" = "YES" ]; then
		echo ${CONFIG} | jq \
			--arg SERVER "https://acme.zerossl.com/v2/DV90" \
			--arg CERT_ZEROSSL_EAB_KID ${CERT_ZEROSSL_EAB_KID} \
			'.spec.acme.server = $SERVER | .spec.acme.externalAccountBinding = {"keyID": $CERT_ZEROSSL_EAB_KID, "keyAlgorithm": "HS256", "keySecretRef": { "name": "zero-ssl-eabsecret", "key": "secret"}}' > ${ETC_DIR}/cluster-issuer.json
	else
		echo ${CONFIG} | jq \
			--arg SERVER "https://acme-v02.api.letsencrypt.org/directory" \
			--arg CERT_EMAIL ${CERT_EMAIL} \
			'.spec.acme.server = $SERVER | .spec.acme.email = $CERT_EMAIL' > ${ETC_DIR}/cluster-issuer.json
	fi

	kubectl apply -f ${ETC_DIR}/cluster-issuer.json --kubeconfig=${TARGET_CLUSTER_LOCATION}/config
}

echo_blue_bold "Install cert-manager"

export NAMESPACE=cert-manager
export ETC_DIR=${TARGET_DEPLOY_LOCATION}/cert-manager
export KUBERNETES_TEMPLATE=./templates/cert-manager

KUBERNETES_MINOR_RELEASE=$(echo -n ${KUBERNETES_VERSION} | awk -F. '{ print $2 }')

case ${KUBERNETES_MINOR_RELEASE} in
	26)
		CERT_MANAGER_VERSION=v1.11.5
		;;
	27)
		CERT_MANAGER_VERSION=v1.12.7
		;;
	28)
		CERT_MANAGER_VERSION=v1.13.3
		;;
	29)
		CERT_MANAGER_VERSION=v1.14.4
		;;
	30)
		CERT_MANAGER_VERSION=v1.14.4
		;;
	31)
		CERT_MANAGER_VERSION=v1.16.0
		;;
	*)
		echo_red_bold "Unsupported k8s release: ${KUBERNETES_VERSION}"
		exit 1
esac

mkdir -p ${ETC_DIR}

kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	| tee ${ETC_DIR}/namespace.yaml \
	| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade -i ${NAMESPACE} jetstack/cert-manager \
	--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
	--namespace ${NAMESPACE} \
	--version ${CERT_MANAGER_VERSION} \
	--set installCRDs=true

if [ -z "${PUBLIC_DOMAIN_NAME}" ] || [ "${CERT_SELFSIGNED}" == "YES" ]; then
	echo_blue_bold "Register CA self signed issuer"
	kubectl create secret generic ca-key-pair --dry-run=client -o yaml \
		--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
		--namespace ${NAMESPACE} \
		--from-file=tls.crt=${CA_LOCATION}/masterkube.pem \
		--from-file=tls.key=${CA_LOCATION}/masterkube.key \
		| tee ${ETC_DIR}/ca-key-pair.yaml \
		| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

	deploy cluster-issuer-selfsigned
else
	if [ "${USE_ZEROSSL}" = "YES" ]; then
		kubectl create secret generic zero-ssl-eabsecret -n ${NAMESPACE} --dry-run=client -o yaml \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
			--from-literal secret="${CERT_ZEROSSL_EAB_HMAC_SECRET}" \
			| tee ${ETC_DIR}/zero-ssl-eabsecret.yaml \
			| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -
	fi

	if [ "${EXTERNAL_DNS_PROVIDER}" == "aws" ]; then
		if [ -n "${AWS_ROUTE53_PUBLIC_ZONE_ID}" ]; then
			echo_blue_bold "Register route53 issuer"
			kubectl create secret generic route53-credentials-secret -n ${NAMESPACE} --dry-run=client -o yaml \
				--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
				--from-literal=secret=${AWS_ROUTE53_SECRETKEY} \
				| tee ${ETC_DIR}/route53-credentials-secret.yaml \
				| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

			deploy cluster-issuer-route53
		fi
	elif [ "${EXTERNAL_DNS_PROVIDER}" == "godaddy" ]; then
		echo_blue_bold "Register godaddy issuer"

		case ${KUBERNETES_MINOR_RELEASE} in
			26)
				GODADDY_WEBHOOK_VERSION=v1.26.1
				;;
			27)
				GODADDY_WEBHOOK_VERSION=v1.27.2
				;;
			28)
				GODADDY_WEBHOOK_VERSION=v1.28.4
				;;
			29)
				GODADDY_WEBHOOK_VERSION=v1.29.0
				;;
			30)
				GODADDY_WEBHOOK_VERSION=v1.29.0
				;;
			*)
				echo_red_bold "Unsupported k8s release: ${KUBERNETES_VERSION}"
				exit 1
		esac

		helm repo add godaddy-webhook https://fred78290.github.io/cert-manager-webhook-godaddy/
		helm repo update
		helm upgrade -i godaddy-webhook godaddy-webhook/godaddy-webhook \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
			--version ${GODADDY_WEBHOOK_VERSION} \
			--set groupName=${PUBLIC_DOMAIN_NAME} \
			--set dnsPolicy=ClusterFirst \
			--namespace cert-manager

		kubectl create secret generic godaddy-api-key-prod -n ${NAMESPACE} --dry-run=client -o yaml \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
			--from-literal=key=${CERT_GODADDY_API_KEY} \
			--from-literal=secret=${CERT_GODADDY_API_SECRET} \
			| tee ${ETC_DIR}/godaddy-api-key-prod.yaml \
			| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/config -f -

		deploy cluster-issuer-godaddy
	elif [ "${EXTERNAL_DNS_PROVIDER}" == "designate" ]; then
		helm repo add designate-certmanager-webhook https://fred78290.github.io/designate-certmanager/
		helm repo update

		helm upgrade -i godaddy-webhook godaddy-webhook/godaddy-webhook \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
			--set groupName=${PUBLIC_DOMAIN_NAME} \
			--set dnsPolicy=ClusterFirst \
			--namespace cert-manager

		FROM_LITERAL=()
		OSENV=(
			"OS_AUTH_URL"
			"OS_DOMAIN_NAME"
			"OS_REGION_NAME"
			"OS_PROJECT_ID"
			"OS_USERNAME"
			"OS_PASSWORD"
			"OS_APPLICATION_CREDENTIAL_ID"
			"OS_APPLICATION_CREDENTIAL_NAME"
			"OS_APPLICATION_CREDENTIAL_SECRET"
		)

		for NAME in ${OSENV[@]}
		do
			VALUE=${!NAME}
			if [ -n "${VALUE}" ]; then
				FROM_LITERAL+=("--from-literal=${NAME}=${VALUE}")
			fi
		done

		kubectl --namespace cert-manager create secret generic cloud-credentials --dry-run=client -o yaml ${FROM_LITERAL[@]} \
			--kubeconfig=${TARGET_CLUSTER_LOCATION}/config \
			| tee ${ETC_DIR}/cloud-credentials.yaml \
			| kubectl apply --kubeconfig=${TARGET_CLUSTER_LOCATION}/cloud-credentials -f -

		deploy cluster-issuer-designate
	fi
fi
