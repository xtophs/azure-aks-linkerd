az group create -n $RG -l $LOCATION
az aks create -n linkerdcluster -g $RG 
az aks get-credentials -n linkerdcluster -g $RG
