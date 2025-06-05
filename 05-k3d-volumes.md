The Jenkins K8s Agent Pods need persistent storage to cache Maven, Kaniko and OWASP artefacts.

Our Jenkins K8s Agent Pods are running on K3D, which in-turn, is running on Docker.

So in-order for a K8s PV of "hostPath" to work, we need to :

1. create docker volume
2. mount the docker volume, to the agent node, whilst starting K3D
3. create a K8s PV with hostPath
4. Data will be persisted for the pods, via the docker volume, to the local machine (Macbook)



## USE DOCKER VOLUMES INSTEAD OF BIND MOUNTS FOR FASTER READ/WRITES
>> docker volume create k3d-data


## NO WORKER NODES, WITH BIND MOUNTS [NOT RECOMMENDED]
>> k3d cluster create mycluster --subnet 172.19.0.0/16 --volume /Users/vkancherla/Downloads/K3d-Volumes:/mnt/data@server:0

## NO WORKER NODES, WITH VOLUMES [RECOMMENDED]
>> k3d cluster create mycluster --subnet 172.19.0.0/16 --volume k3d-data:/mnt/data@server:0

## SERVER AND WORKER NODE, WITH BIND MOUNTS [NOT RECOMMENDED]
>> k3d cluster create mycluster \
  --servers 1 \
  --agents 1 \
  --subnet 172.19.0.0/16 \
  --volume /Users/vkancherla/Downloads/K3d-Volumes:/mnt/data@agent:0

SERVER AND WORKER NODE, WITH BIND VOLUMES [RECOMMENDED]
>> k3d cluster create mycluster \
  --servers 1 \
  --agents 1 \
  --subnet 172.19.0.0/16 \
  --volume k3d-data:/mnt/data@agent:0