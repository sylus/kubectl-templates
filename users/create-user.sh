#!/usr/bin/env sh

set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 user namespace" 1>&2
  exit 1
fi

USER=$1
NAMESPACE=$2

# Create service account
kubectl -n default create sa "$USER"
sleep 1
secret=$(kubectl -n default get sa "$USER" -o json | jq -r '.secrets[].name')
# Collect information needed to create the kubeconfig
kubectl -n default get secret $secret -o json | jq -r '.data["ca.crt"]' | base64 --decode > ca.crt
user_token=$(kubectl -n default get secret $secret -o json | jq -r '.data["token"]' | base64 --decode)
c=$(kubectl config current-context)
name=$(kubectl config get-contexts $c | awk '{print $3}' | tail -n 1)
endpoint=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"$name\")].cluster.server}")

# Create kubeconfig
KUBECONFIG=kubeconfig kubectl config set-cluster $c --embed-certs=true --server=$endpoint --certificate-authority=./ca.crt
KUBECONFIG=kubeconfig kubectl config set-credentials "$USER" --token=$user_token
KUBECONFIG=kubeconfig kubectl config set-context $c --cluster=$c --user="$USER" "--namespace=$NAMESPACE"
KUBECONFIG=kubeconfig kubectl config use-context $c

# Create roles
cat <<EOF | kubectl -n "$NAMESPACE" apply -f -
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: limited-user
rules:
  - apiGroups: [""]
    resources:
      - nodes
    verbs:
      - get
      - list
      - watch
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: limited-user
rules:
  - apiGroups:
      - ""
      - apps
      - extensions
    resources:
      - deployments
      - cronjobs
      - jobs
      - secrets
      - services
      - persistentvolumeclaims
      - pods
      - pods/attach
      - pods/exec
      - pods/log
      - configmaps
      - ingresses
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
      - edit
      - exec

EOF

# Create role bindings
cat <<EOF | kubectl -n "$NAMESPACE" apply -f -
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $USER-limited-user
subjects:
  - kind: ServiceAccount
    name: $USER
    namespace: default
roleRef:
  kind: ClusterRole
  name: limited-user
  apiGroup: rbac.authorization.k8s.io
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: $USER-limited-user
subjects:
  - kind: ServiceAccount
    name: $USER
    namespace: default
roleRef:
  kind: Role
  name: limited-user
  apiGroup: rbac.authorization.k8s.io
EOF
