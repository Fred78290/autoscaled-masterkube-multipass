#!/bin/sh

kubectl config delete-context $1
kubectl config delete-cluster $1
kubectl config delete-user kubernetes-admin@$1
