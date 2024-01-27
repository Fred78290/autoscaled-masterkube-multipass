#!/bin/sh
export KUBECONFIG=/tmp/k8s-$1.config

#cat $2 | sed -e "s/kubernetes/k8s-$1/g" > ${KUBECONFIG}
cat $2 | sed -e "s/kubernetes-admin@//g" > ${KUBECONFIG}

mkdir -p ~/.kube

if [ -f ~/.kube/config ]; then
	cp ~/.kube/config ~/.kube/config.old

	KUBECONFIG="${KUBECONFIG}:${HOME}/.kube/config.old"
fi

kubectl config view --flatten > ~/.kube/config