. ./scripts/k8s-tests.sh

export NAMERD_INGRESS_LB=$(kubectl get svc namerd -o jsonpath="{.status.loadBalancer.ingress[0].*}")    
export L5D_INGRESS_LB=$(kubectl get svc l5d -o jsonpath="{.status.loadBalancer.ingress[0].*}")

if [ -z $(which namerctl) ]; then

    if [ -z $(which go) ]; then
        echo Setting up golang
        sudo apt-get update -y
        sudo apt-get install golang

        MYGOPATH=/home/azureuser/gopath
        mkdir -p $MYGOPATH
        export GOPATH=$MYGOPATH
        export PATH=$PATH:$GOPATH
    else
        echo go already installed
        go version
    fi

    echo Installing namerd CLI
    go get  -u github.com/linkerd/namerctl
    go install github.com/linkerd/namerctl
else
    echo Namerd CLI already installed
fi 
export NAMERCTL_BASE_URL=http://$NAMERD_INGRESS_LB:4180
namerctl dtab get internal

echo Deploying into kubernetes
kubectl create -f ./k8s-resources/hello-world.yaml
kubectl create -f ./k8s-resources/world-v2.yaml 

echo Waiting for pods
wait_for_replicas_ready hello 3
wait_for_replicas_ready world-v1 3
wait_for_replicas_ready world-v2 3


echo Testing traffic shape NO TRAFFIC goes to canary 
for i in {1..10}; do curl $L5D_INGRESS_LB; echo ""; done

echo all traffic should be going to world-v1.
namerctl dtab update internal ./routing/dtab-canary.txt

echo Testing new traffic shape 30% go to canary
for i in {1..10}; do curl $L5D_INGRESS_LB; echo ""; done

echo about 30% of all traffic should be going to world-v2. 
