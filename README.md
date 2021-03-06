# Kind cluster

Create a local k8s cluster using kind.

The following services is part of this cluster:

* fission

* k8s dashboard

* helm3

## Create a new cluster

```shell
./create-cluster.sh <NAME>
```

## k8s dashboard
### Start proxy

```shell
kubectl proxy
```

### Get dashboard token

```shell
dashboard_token_name=$(kubectl describe serviceaccount admin-user -n kubernetes-dashboard | grep Tokens | cut -d : -f 2 | awk '{$1=$1;print}') && \
    kubectl describe secret "${dashboard_token_name}" -n kubernetes-dashboard | grep token: | cut -d : -f 2 | awk '{$1=$1;print}'
```

## Nginx ingress

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml && \
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

kubectl --namespace ingress-nginx port-forward service/ingress-nginx-controller 3000:80

## [WIP]Ambassador

```shell
sudo curl -fL https://metriton.datawire.io/downloads/linux/edgectl -o /usr/local/bin/edgectl && sudo chmod a+x /usr/local/bin/edgectl
edgectl install
```
