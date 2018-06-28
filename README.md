# Deploying and Configuring Linkerd in Azure AKS kubernetes cluster
This article shows how to manage canary deployments in kubernetes clusters provisioned by Azure's AKS.

[Linkerd](https://linkerd.io/) and [namerd](https://linkerd.io/advanced/namerd/) manage the traffic directed to the canary deployment. In this article, the canary receives 10% of all traffic.

## Deploy kubernetes in AKS default configuration
First, deploy a kubernetes cluster into Azure. This article deploys the cluster using the Azure Kubernetes Service with all default settings.

```
az group create --location eastus -n xtoph-aks-linkerd

$ az aks create -g xtoph-aks-linkerd -n linkerdcluster
{
  "agentPoolProfiles": [
...
    }
}

$ az aks get-credentials -g xtoph-aks-linkerd -n linkerdcluster
Merged "linkerdcluster" as current context in /home/csc/.kube/config
```

## Deploy Linkerd and Namerd
Now that we have a kubernetes cluster, let's install linkerd and namerd. All deployment and configuration work is done via `kubectl`. You don't have to `ssh` into the master node. If you follow the steps above, your new AKS cluster should already be selected as the current kubernetes context.

First we deploy RBAC rules required by linkerd.
```
$ kubectl create -f linkerd-rbac.yml

clusterrole "linkerd-endpoints-reader" created
clusterrole "namerd-dtab-storage" created
clusterrolebinding "linkerd-role-binding" created
clusterrolebinding "namerd-role-binding" created
```

Then we deploy namerd, the engine that will serve the routing rules to linkerd. Serving rules via namerd avoids restarting the linkerd every time you have a new routing configuration.

```
$ kubectl create -f namerd.yml 
customresourcedefinition "dtabs.l5d.io" created
configmap "namerd-config" created
replicationcontroller "namerd" created
service "namerd" created
configmap "namerctl-script" created
job "namerctl" created
```

Finally, we install linkerd itself.
```
$ kubectl create -f linkerd.yml 
configmap "l5d-config" created
daemonset "l5d" created
service "l5d" created
```

Take a quick look to double-check that deployments were successful.
```
$ kubectl get pods
NAME           READY     STATUS    RESTARTS   AGE
l5d-8cmdf      2/2       Running   0          3m
l5d-sx2p6      2/2       Running   0          3m
l5d-vx8km      2/2       Running   0          3m
namerd-lkb4c   2/2       Running   0          3m
```

In this example, both linkerd and namerd are configured to be accessed from the outside. That makes sense for managing canary deployments of public facing services - but you can also configure different a different service type to restrict access to internal only. 

The Azure Load Balancers can take a few minutes to come up. Make sure you wait until you see an `EXTERNAL_IP` before you proceed.

```
$ kubectl get svc
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)                                                       AGE
kubernetes   ClusterIP      10.0.0.1       <none>          443/TCP                                                       2h
l5d          LoadBalancer   10.0.212.180   13.68.132.101   80:31756/TCP,4140:30090/TCP,4141:30076/TCP,9990:32650/TCP     4m
namerd       LoadBalancer   10.0.187.155   40.117.250.76   4100:31373/TCP,4180:31984/TCP,4321:31935/TCP,9991:30419/TCP   5m
```

Once the linkerd service is up and running, verify that linkerd is operational. You can do this by checking the linkerd admin UI, for example via curl.

```
$ L5D_INGRESS_LB=$(kubectl get svc l5d -o jsonpath="{.status.loadBalancer.ingress[0].*}")
$ curl $L5D_INGRESS_LB:9990

      <!doctype html>
      <html>
        <head>
          <title>linkerd admin</title>
          <link type="text/css" href="files/css/lib/bootstrap.min.css" rel="stylesheet"/>

```

For extra precaution, you can also verify that namerd is running by checking the namerd admin UI:
```
$ NAMERD_INGRESS_LB=$(kubectl get svc namerd -o jsonpath="{.status.loadBalancer.ingress[0].*}")
$ curl $NAMERD_INGRESS_LB:9991

      <!doctype html>
      <html>
        <head>
          <title>namerd admin</title>
```

Now you have LinkerD and NamerD running. To modify the routing rules, you will need the namerd CLI. Let's install that, too.

```
$ go get -u github.com/linkerd/namerctl
$ go install github.com/linkerd/namerctl
```

and verify that `namerctl` is working properly by getting the dtab for the internal namespace
```
# assuming that $GOPATH/bin is in your $PATH
$ export NAMERCTL_BASE_URL=http://$NAMERD_INGRESS_LB:4180

$ ./gopath/bin/namerctl dtab get internal
# version MzU4MQ==
/srv         => /#/io.l5d.k8s/default/http ;
/host        => /srv ;
/tmp         => /srv ;
/svc         => /host ;
/host/world  => /srv/world-v1 ;
```

## Manage Canary Routing Rules
Imagine you're rolling out a new version of your service. You ran all your tests and your confident that everything works, but in complex microservice architectures with decentralized governance, it's impossible to maintain a full fidelity test environments. Therefore approaches using canary deployments, sometimes also referred to as "testing in production" becoming more and more popular. 

In this example, we have V1 of our service running. Then we're deploying V2 of a downstream service. Instead of directing all traffic to the new version, only 30% of the traffic go to the new version to keep the impact of potential integration issues low.

Note: 30% is a fairly high percentage. It's this high only because it makes it easier to observe. In real canary environments, the inital percentage is much, much lower and gradually increases over time. 

Let's install V1 of the app:
```
$ kubectl create -f hello-world.yml
replicationcontroller "hello" created
service "hello" created
replicationcontroller "world-v1" created
service "world-v1" created

$ kubectl describe svc world-v1
Name:              world-v1
Namespace:         default
Labels:            <none>
Annotations:       <none>
Selector:          app=world-v1
Type:              ClusterIP
IP:                None
Port:              http  7778/TCP
TargetPort:        7778/TCP
Endpoints:         10.240.0.12:7778,10.240.0.44:7778,10.240.0.80:7778
Session Affinity:  None
Events:            <none>

```
Note that the service doesn't have it's own IP address. It only points to the pods' endpoints where the application is running. Linkerd discovers the endpoints dynamically by querying the kubernetes API.

Make sure it works through the linkerd proxy endpoint.
```
$ curl $L5D_INGRESS_LB
Hello (10.240.0.39) world (10.240.0.44)!!
```

Now we install V2 of the app:
```
$ kubectl create -f world-v2.yaml 
replicationcontroller "world-v2" created
service "world-v2" created
```

V2 doesn't take traffic yet, because the hello app invokes a service named world. Linkerd has a routing rule that points only to world-v1.

To enable canaries of the V2, we create a new route table that shifts a percentage of the traffic:
```
# write the linkerd delegation table to a file
namerctl dtab get internal > mydtab.txt
```

edit the delegation table to direct 30% of the traffic to world to go to world-v2:
```
/host/world  => 3 * /srv/world-v2 & 7 * /srv/world-v1 ;
```

and update routing rule with the namerd CLI.

```
$ namerctl dtab update internal ./mydtab.txt
Updated internal
```

Now test that 30% of the traffic hit the new version.
```
$ for i in {1..10}; do curl $L5D_INGRESS_LB; echo ""; done
Hello (10.240.0.39) world (10.240.0.44)!!
Hello (10.240.0.55) world (10.240.0.44)!!
Hello (10.240.0.55) worldv2 (10.240.0.78)!!
Hello (10.240.0.55) world (10.240.0.44)!!
Hello (10.240.0.55) worldv2 (10.240.0.30)!!
Hello (10.240.0.55) worldv2 (10.240.0.57)!!
Hello (10.240.0.26) world (10.240.0.80)!!
Hello (10.240.0.55) world (10.240.0.80)!!
Hello (10.240.0.26) worldv2 (10.240.0.78)!!
Hello (10.240.0.39) world (10.240.0.44)!!
```

Note that some requests were directed to the new version.

## Room For Improvement
- Run Linkerd in non-default namespace to keep things clean in the cluster
- TLS config ... because security matters
- side car configuration ... because everybody just loves sidecars
- sidecar with TLS ... see above
- test performance ... because running Linkerd comes at a performance cost  
- deploy AKS via terraform ... to be platform neutral

## Automation
Instead of typing or cutting and pasting all these commands, you can run the supplied scripts:
- `setup.sh`: set up an AKS cluster from scrath, configure linkerd, namerd, and the canary deployment.
- `cleanup.sh`: delete the canary deployment and all namerd and linkerd resources.

## Troubleshooting
- Check all services (linkerd, namerd, hello, world, world-v2) are running
```
kubectl get pods
kubectl get svc
kubectl get endpoints ...
```

- check proxy is working
```
curl $L5D_INGRESS:9990

Need route endpoint
```

- make sure the k8s downward API works

```
pod "node-name-test" created
$ kubectl apply -f https://raw.githubusercontent.com/linkerd/linkerd-examples/master/k8s-daemonset/k8s/node-name-test.yml


$ kubectl logs node-name-test
Server:		10.0.0.10
Address:	10.0.0.10#53

Name:	k8s-agentpool1-93050318-0.lvophhkhn3bufjo3extvnx2rcb.bx.internal.cloudapp.net
Address: 10.240.0.4
```

## Acknowledgements
This article is heavily based on content from the [buoyant blog](https://blog.buoyant.io/2016/11/04/a-service-mesh-for-kubernetes-part-iv-continuous-deployment-via-traffic-shifting/) and the [linkerd samples](https://github.com/linkerd/linkerd-examples/tree/master/k8s-daemonset) 