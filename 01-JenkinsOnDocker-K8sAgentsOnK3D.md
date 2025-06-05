# Jenkins Master on Docker with Kubernetes Agents on K3D

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Cluster Setup](#cluster-setup)
4. [Network Configuration](#network-configuration)
5. [Kubernetes Resources](#kubernetes-resources)
6. [Jenkins Deployment](#jenkins-deployment)
7. [Jenkins Configuration](#jenkins-configuration)
8. [Verification](#verification)
9. [Troubleshooting](#troubleshooting)

## Overview <a name="overview"></a>
This guide demonstrates how to:
- Run Jenkins master in a Docker container
- Deploy dynamic agents in a local K3D Kubernetes cluster
- Establish communication between components

## Prerequisites <a name="prerequisites"></a>
- Docker installed
- `kubectl` installed
- `k3d` installed (v5.0.0+ recommended)

## Cluster Setup <a name="cluster-setup"></a>

### 1. Create K3D Cluster
```
k3d cluster create mycluster \
  -a 1 \  # 1 agent node
  --subnet 172.19.0.0/16 \  # Fixed subnet for static IP assignment
  --api-port 6443  # Expose Kubernetes API port
```

## Network Configuration <a name="network-configuration"></a>

### 2. Identify K3D Network
```
docker network ls | grep k3d

85aa90134e5   k3d-mycluster   bridge    local
```
The network we are interested in "k3d-mycluster".

### 3. Get K3D Server IP
```
K3D_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k3d-mycluster-server-0)
echo $K3D_IP
```

### 4. Prepare Kubeconfig that Jenkins can use
```
cp ~/.kube/config k3d-kubeconfig
sed -i '' "s|server: .*|server: https://${K3D_IP}:6443|g" k3d-kubeconfig
```

## Kubernetes Resources <a name="kubernetes-resources"></a>

### 5. Create Jenkins Namespace and Service Account
```
kubectl create ns jenkins
kubectl create serviceaccount -n jenkins jenkins-sa
```

### 6. Create Long-lived Service Account Token and Store it in a Secret
```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-sa-secret
  namespace: jenkins
  annotations:
    kubernetes.io/service-account.name: jenkins-sa
type: kubernetes.io/service-account-token
EOF
```

### 7. Retrieve Authentication Token from the secret
```
JENKINS_TOKEN=$(kubectl get secret -n jenkins jenkins-sa-secret -o jsonpath='{.data.token}' | base64 -d)
echo $JENKINS_TOKEN

```

### 8. Create Role Binding
```
kubectl create rolebinding jenkins-admin-binding \
  --clusterrole=admin \
  --serviceaccount=jenkins:jenkins-sa \
  --namespace=jenkins
```

## Jenkins Deployment <a name="jenkins-deployment"></a>

### 9. Run Jenkins Container
```
docker run -d --name jenkins-docker \
  -p 8080:8080 -p 50000:50000 \
  -v /Users/vkancherla/Downloads/Docker-Volumes/jenkins-volume:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --network=k3d-mycluster \
  --ip 172.19.0.6 \
  -e TZ=Europe/London \
  bitnami/jenkins:2.504.1
```

Login to Jenkins:
URL: localhost:8080
username: user
password: bitnami

## Jenkins Configuration <a name="jenkins-configuration"></a>

### 10.0 Install Plugins
The bitnami/jenkins:2.504.1 image is lightweight. We need to install the following plugins:
```
build-timeout:1.38
build-timestamp
git-client:6.1.3
git:5.7.0
github:1.43.0
kubernetes-client-api:6.10.0-251.v556f5f100500
kubernetes-credentials:192.v4d5b_1c429d17
kubernetes:4340.v345364d31a_2a_
pipeine:608.v67378e9d3db_1
Pipeline: SCM Step:437.v05a_f66b_e5ef8
Pipeline: Job:1520.v56d65e3b_4566
Pipeline: Basic Steps:1079.vce64b_a_929c5a_
Pipeline: Stage Step:322.vecffa_99f371c
Pipeline: Multibranch:806.vb_b_688f609ee9
pipeline-build-step:567.vea_ce550ece97
pipeline-input-step:517.vf8e782ee645c
Pipeline: Declarative:2.2255.v56a_15e805f12
OWASP Dependency-Check:5.6.1
sonar-quality-gates:352.vdcdb_d7994fb_6
ws-cleanup:0.48
```

### 10.1 Add Credentials (Web UI)
#### A. Accessing Credentials Section
1. Open Jenkins in your browser: `http://localhost:8080` (or your configured host/IP)
2. Log in with your admin credentials
3. Navigate to: Dashboard → Manage Jenkins → Security → Manage Credentials
4. Under "Stores scoped to Jenkins", click on: System → Global credentials (unrestricted)
5. Click "Add Credentials" on the left sidebar

---

#### B. Adding Kubeconfig File Credential (For Option 2 Configuration)
1. **Kind**: Select "Secret file" from dropdown
2. **File**: Click "Browse" and upload your `k3d-kubeconfig` file
- *Location tip*: This is the file you created in [Step 4](#network-configuration).
3. **ID**: Enter `k3d-kubeconfig` (must match reference in cloud config)
4. **Description**: "Kubeconfig for k3d-mycluster access"
5. **Scope**: Keep default "Global" selection
6. Click "OK" to save

---

#### C. Adding Service Account Token (For Option 1 - Recommended)
1. **Kind**: Select "Secret text" from dropdown
2. **Secret**: Paste the token you obtained in [Step 7](#kubernetes-resources):
```
echo $JENKINS_TOKEN  # Use this value if you saved it earlier
```
- Format note: This is the base64-decoded service account token
3. **ID**: Enter k8s-jenkins-sa-token
4. **Description**: "Service account token for jenkins-sa in k3d"
5. **Scope**: Global
6. Click "OK"

### 11. Configure Kubernetes Cloud (Option 1 - Recommended)
#### A. Accessing Cloud Configuration
1. Navigate to: Dashboard → Manage Jenkins → Manage Nodes and Clouds → Configure Clouds
2. Click **Add a new cloud** and select **Kubernetes**

---

#### B. Core Configuration Parameters
Fill in these fields carefully:

1. **Name**: k3d-mycluster
2. **Kubernetes URL**: `https://${K3D_IP}:6443` (The K3D_IP from step-3)
3. **Disable HTTPS certificate check**: ✔ Enabled
4. **Credentials**: Select your stored `k8s-jenkins-sa-token` credential
5. Click "Test Connectivity" to verify connectivity
6. **Jenkins URL**: `http://<THE-MACBOOK-IPAddress>:8080` (http://192.168.1.152:8080)
7. **Jenkins tunnel**: `<THE-MACBOOK-IPAddress>:50000`  (192.168.1.152:50000)

### 12. Configure Kubernetes Cloud (Option 2)
#### A. Accessing Cloud Configuration
1. Navigate to: Dashboard → Manage Jenkins → Manage Nodes and Clouds → Configure Clouds
2. Click **Add a new cloud** and select **Kubernetes**

---

#### B. Core Configuration Parameters
Fill in these fields carefully:

1. **Name**: k3d-mycluster
2. **Kubernetes URL**: Leave empty
3. **Disable HTTPS certificate check**: ✔ Enabled
4. **Credentials**: Select your stored `k3d-kubeconfig` credential
5. Click "Test Connectivity" to verify connectivity
6. **Jenkins URL**: `http://<THE-MACBOOK-IPAddress>:8080` (http://192.168.1.152:8080)
7. **Jenkins tunnel**: `<THE-MACBOOK-IPAddress>:50000`  (192.168.1.152:50000)

## 13. Configure Agent Settings
Go to Manage Jenkins > Security > Agents:
- TCP port for inbound agents: Fixed (50000)


## Verification <a name="verification"></a>

## 14. Test Pipeline
```
pipeline {
  agent {
    kubernetes {
      yaml '''
        apiVersion: v1
        kind: Pod
        metadata:
          name: jenkins-agent
          namespace: jenkins
        spec:
          containers:
          - name: jnlp
            image: jenkins/inbound-agent:latest
            args: ["\$(JENKINS_SECRET)", "\$(JENKINS_NAME)"]
          - name: maven
            image: maven:3.8.6-jdk-11
            command: ["sleep", "infinity"]
        '''
    }
  }
  stages {
    stage('Test') {
      steps {
        container('maven') {
          sh 'mvn -version'
        }
      }
    }
  }
}
```