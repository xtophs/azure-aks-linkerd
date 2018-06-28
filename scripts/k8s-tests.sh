function wait_for_replicas_ready()
{
    local NAME=$1
    local NUMBER=$2

    while true; do
        REPLICAS=$(kubectl get replicationcontroller $NAME -o jsonpath="{.status.readyReplicas}")
        if [ $REPLICAS == $NUMBER ]; 
        then
            echo $NUMBER $NAME replicas ready
            break
        fi
        sleep 5
    done

}

function wait_for_azure_lb()
{
    local NAME=$1

    while true; do
        TMP=$(kubectl get svc $NAME -o jsonpath="{.status.loadBalancer.ingress[0]}")
        if [[ ! -z "$TMP" ]] 
        then
            break
        fi
        sleep 5
    done    
}