echo setting up RBAC 
kubectl create -f ./k8s-resources/linkerd-rbac.yaml

echo deploying namerd
kubectl create -f ./k8s-resources/namerd.yaml 

echo deploying linkerd
kubectl create -f ./k8s-resources/linkerd.yaml 

# Wait for LBs
echo waiting for Load Balancers to come up

. ./scripts/k8s-tests.sh

wait_for_azure_lb namerd
wait_for_azure_lb l5d

export NAMERD_INGRESS_LB=$(kubectl get svc namerd -o jsonpath="{.status.loadBalancer.ingress[0].*}")    
echo Namerd Load Balancer Address is $NAMERD_INGRESS_LB
curl $NAMERD_INGRESS_LB:9991

export L5D_INGRESS_LB=$(kubectl get svc l5d -o jsonpath="{.status.loadBalancer.ingress[0].*}")
echo Linkerd Load Balancer Address is $L5D_INGRESS_LB
curl $L5D_INGRESS_LB:9990

echo Linkerd and Namerd Running!

