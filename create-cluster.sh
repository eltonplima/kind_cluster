#!/bin/bash
set -o errexit

declare -r CLUSTER_NAME="${1}"

function create_k8s_cluster() {
  # create registry container unless it already exists
  reg_name='kind-registry'
  reg_port='5000'
  running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
  if [ "${running}" != 'true' ]; then
    docker run \
      -d --restart=always -p "${reg_port}:5000" --name "${reg_name}" \
      registry:2
  fi

  # create a cluster with the local registry enabled in containerd
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_name}:${reg_port}"]
# patch the generated kubeadm config with some extra settings
kubeadmConfigPatches:
  - |
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    evictionHard:
      nodefs.available: "0%"
# patch it further using a JSON 6902 patch
kubeadmConfigPatchesJSON6902:
  - group: kubeadm.k8s.io
    version: v1beta2
    kind: ClusterConfiguration
    patch: |
      - op: add
        path: /apiServer/certSANs/-
        value: my-hostname
# 1 control plane node and 3 workers
nodes:
  # the control plane node config
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  # the three workers
  - role: worker
  - role: worker
  - role: worker
EOF

  # connect the registry to the cluster network
  # (the network may already be connected)
  # echo "Creating cluster registry"
  # docker network connect "kind" "${reg_name}" || true

  # Document the local registry
  # https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
}

function adjust_file_permissions() {
  printf '=%.0s' {1..100} && echo ""
  echo "Adjusting .kube/config permissions"
  printf '=%.0s' {1..100} && echo ""
  chmod 600 ~/.kube/config
}

function install_ambassador() {
  printf '=%.0s' {1..100} && echo ""
  echo "Preparing ingress [ambassador]"
  printf '=%.0s' {1..100} && echo ""
  #  kubectl apply -f https://github.com/datawire/ambassador-operator/releases/latest/download/ambassador-operator-crds.yaml
  #  kubectl apply -n ambassador -f https://github.com/datawire/ambassador-operator/releases/latest/download/ambassador-operator-kind.yaml
  #  kubectl wait --timeout=180s -n ambassador --for=condition=deployed ambassadorinstallations/ambassador
  helm repo add datawire https://www.getambassador.io
  kubectl create namespace ambassador && helm install ambassador --namespace ambassador datawire/ambassador
}

function install_helm() {
  printf '=%.0s' {1..100} && echo ""
  echo "Installing helm3"
  printf '=%.0s' {1..100} && echo ""
  curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
  helm repo add "kubernetes-dashboard" "https://kubernetes.github.io/dashboard/"
  helm repo add "stable" "https://charts.helm.sh/stable" --force-update
}

function install_k8s_dashboard() {
  printf '=%.0s' {1..100} && echo ""
  echo "Installing k8s dashboard"
  printf '=%.0s' {1..100} && echo ""
  helm install dashboard kubernetes-dashboard/kubernetes-dashboard -n kubernetes-dashboard --create-namespace

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
}
function install_fission() {
  printf '=%.0s' {1..100} && echo ""
  echo "Installing fission"
  printf '=%.0s' {1..100} && echo ""
  export FISSION_NAMESPACE="fission"
  kubectl create namespace "${FISSION_NAMESPACE}"
  helm install --namespace "${FISSION_NAMESPACE}" --name-template fission \
    https://github.com/fission/fission/releases/download/1.11.2/fission-all-1.11.2.tgz
}

function test_fission() {
  printf '=%.0s' {1..100} && echo ""
  echo "Testing fission installation"
  printf '=%.0s' {1..100} && echo ""
  declare -r FISSION_TEST_ENV_NAME=nodejs
  declare -r FISSION_TEST_FUNCTION_NAME=hello
  fission env create --name "${FISSION_TEST_ENV_NAME}" --image fission/node-env:latest &&
    curl https://raw.githubusercontent.com/fission/fission/master/examples/nodejs/hello.js >"${FISSION_TEST_FUNCTION_NAME}".js &&
    fission function create --name "${FISSION_TEST_FUNCTION_NAME}" --env "${FISSION_TEST_ENV_NAME}" --code hello.js &&
    sleep 5 &&
    fission function test --name "${FISSION_TEST_FUNCTION_NAME}" && echo -e "\033[32;1mFission validated with success\033[0m" || echo -e "\033[31;1mA problem was detected with fission\033[0m"
  fission function delete --name "${FISSION_TEST_FUNCTION_NAME}"
  fission env delete --name "${FISSION_TEST_ENV_NAME}"
  rm "${FISSION_TEST_FUNCTION_NAME}".js
}

create_k8s_cluster
adjust_file_permissions
install_helm
#install_ambassador
install_k8s_dashboard
install_fission
test_fission

echo "kubectl proxy"
