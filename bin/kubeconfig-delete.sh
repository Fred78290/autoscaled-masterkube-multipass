#!/bin/sh

kubectl config delete-context $1
kubectl config delete-cluster $1
kubectl config delete-user admin@$1
kubectl config delete-user $1
