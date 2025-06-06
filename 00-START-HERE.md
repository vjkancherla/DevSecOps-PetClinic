# DevSecOps Demo Project - Complete Setup Guide

This guide provides step-by-step instructions to set up a complete DevSecOps pipeline using Jenkins, SonarQube, and Kubernetes (K3d) running locally on your machine using Docker.

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Infrastructure Setup](#infrastructure-setup)
4. [Service Deployment](#service-deployment)
5. [Jenkins Configuration](#jenkins-configuration)
6. [SonarQube Configuration](#sonarqube-configuration)
7. [Pipeline Creation](#pipeline-creation)
8. [Verification](#verification)
9. [Troubleshooting](#troubleshooting)

## Overview

This demo project demonstrates a complete DevSecOps pipeline with:
- **Jenkins Master** running on Docker
- **Dynamic Kubernetes Agents** on K3d cluster
- **SonarQube** for code quality analysis
- **Security scanning** with Trivy, GitLeaks, and OWASP Dependency Check
- **Container building** with Kaniko
- **Multi-branch pipeline** support

## Prerequisites

Ensure you have the following installed:
- Docker Desktop
- `kubectl` CLI tool
- `k3d` CLI tool (v5.0.0+ recommended)
- Git
- A DockerHub account and personal access token

## AUTOMATION
The document details all the manual steps required to setup and run the project. This is good for learning.
However, to speed things up, automation scripts have been created :
- [k3d-setup.sh](k3d-setup.sh)
- [k3d-teardown.sh](k3d-teardown.sh)
- [makefile](makefile)

Please refer to the following documents on how to run the automation:
- [0001-Automation-1-Initial-setup.md](0001-Automation-1-Initial-setup.md)
- [0001-Automation-2-Daily-usage.md](0001-Automation-2-Daily-usage.md)

The automated steps are:
- create docker volume - k3d-data
- start k3d, with volume mapped
- create jenkins namespace
- create K8s PV and PVCs for caching artifacts
- create a K8s secret to be consumed by Kaniko
- prep k3d-kube-config file (for jenkins-to-K3d connectivity)
- start docker services using docker compose

## Infrastructure Setup

### Step 0: Create K3d Cluster and Network

⚠️ IMPORTANT: Understanding K3d Volumes Architecture
The Jenkins K8s Agent Pods need persistent storage to cache Maven, Kaniko, and OWASP artifacts for performance. Since our Jenkins K8s Agent Pods run on K3D (which runs on Docker), we need a specific storage setup:
Storage Flow: Jenkins Agent Pod → K8s PV (hostPath) → K3d Agent Node → Docker Volume → Local Machine
Why Docker Volumes vs Bind Mounts?

✅ Docker Volumes: Faster I/O performance, better for caching
❌ Bind Mounts: Slower performance, especially on macOS/Windows

This is why we create Docker volumes first, then mount them to K3d agent nodes.


#### 0.1 Create Docker Volume for K3d Data
For better performance, use Docker volumes instead of bind mounts:
```bash
docker volume create k3d-data
```

#### 0.2 Create K3d Cluster
```bash
k3d cluster create mycluster \
  --servers 1 \
  --agents 1 \
  --subnet 172.19.0.0/16 \
  --volume k3d-data:/mnt/data@agent:0 \
  --api-port 6443
```

#### 0.3 Get K3d Server IP and Prepare Kubeconfig
```bash
# Get K3d server IP
K3D_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' k3d-mycluster-server-0)
echo "K3d Server IP: $K3D_IP"

# Prepare kubeconfig for Jenkins
cp ~/.kube/config k3d-kubeconfig
sed -i '' "s|server: .*|server: https://${K3D_IP}:6443|g" k3d-kubeconfig
```

### Step 0.1: Create Jenkins Namespace and Resources

#### Create Jenkins Namespace
```bash
kubectl create ns jenkins
```

#### [OPTIONAL] Create Service Account and Authentication
```bash
# Create service account
kubectl create serviceaccount -n jenkins jenkins-sa

# Create long-lived service account token
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

# Create role binding
kubectl create rolebinding jenkins-admin-binding \
  --clusterrole=admin \
  --serviceaccount=jenkins:jenkins-sa \
  --namespace=jenkins

# Retrieve authentication token
JENKINS_TOKEN=$(kubectl get secret -n jenkins jenkins-sa-secret -o jsonpath='{.data.token}' | base64 -d)
echo "Jenkins Token: $JENKINS_TOKEN"
```

### Step 0.2: Create Persistent Volumes and Claims

Create the required PVs and PVCs for Jenkins agent pods:

```bash
# Create Persistent Volumes
 kubectl apply -f k3d-persistence-store.yaml
```

### Step 0.3: Create Kubernetes Secret for DockerHub

Create a secret for Kaniko to push images to DockerHub:
```bash
kubectl create secret -n jenkins docker-registry docker-credentials \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=YOUR_DOCKERHUB_USERNAME \
  --docker-password=YOUR_DOCKERHUB_TOKEN \
  --docker-email=YOUR_EMAIL@domain.com
```

## Service Deployment

### Step 1: Create Docker Volumes for Jenkins and SonarQube

```bash
# Create Docker volumes for data persistence
docker volume create jenkins-data
docker volume create sonarqube-data
```

### Step 2: Deploy Jenkins and SonarQube

See [docker-compose.yaml](docker-compose.yaml)

Start the services:
```bash
docker-compose up -d
```

## Jenkins Configuration

### Step 3: Install Required Jenkins Plugins

Access Jenkins at `http://localhost:8080` and login with:
- Username: `user`
- Password: `bitnami`

Install the following plugins via **Manage Jenkins → Manage Plugins**:

**Essential Plugins:**
- build-timeout:1.38
- build-timestamp
- git-client:6.1.3
- git:5.7.0
- github:1.43.0
- kubernetes-client-api:6.10.0-251.v556f5f100500
- kubernetes-credentials:192.v4d5b_1c429d17
- kubernetes:4340.v345364d31a_2a_
- pipeline:608.v67378e9d3db_1
- Pipeline: SCM Step:437.v05a_f66b_e5ef8
- Pipeline: Job:1520.v56d65e3b_4566
- Pipeline: Basic Steps:1079.vce64b_a_929c5a_
- Pipeline: Stage Step:322.vecffa_99f371c
- Pipeline: Multibranch:806.vb_b_688f609ee9
- pipeline-build-step:567.vea_ce550ece97
- pipeline-input-step:517.vf8e782ee645c
- Pipeline: Declarative:2.2255.v56a_15e805f12

**Security Plugins:**
- sonar scanner
- sonar-quality-gates:352.vdcdb_d7994fb_6

**Utility Plugins:**
- ws-cleanup:0.48

### Step 4: Create Jenkins Credentials

Navigate to **Dashboard → Manage Jenkins → Security → Manage Credentials → System → Global credentials**

#### 4.1 Create Service Account Token Credential
- **Kind**: Secret text
- **Secret**: Paste the `$JENKINS_TOKEN` from Step 0.1
- **ID**: `k8s-jenkins-sa-token`
- **Description**: Service account token for jenkins-sa in k3d

#### 4.2 Create GitHub Credentials
- **Kind**: Username with password
- **Username**: Your GitHub username
- **Password**: Your GitHub personal access token
- **ID**: `github-credentials`
- **Description**: GitHub access credentials

#### 4.3 Create SonarQube Token (will be created in Step 5)
- **Kind**: Secret text
- **ID**: `sonarqube-token`
- **Description**: SonarQube authentication token

### Step 5: Configure Agent Security Settings

Navigate to **Manage Jenkins → Security → Agents**:
- Set **TCP port for inbound agents** to: **Fixed (50000)**

### Step 6: Configure Kubernetes Cloud

Navigate to **Dashboard → Manage Jenkins → Manage Nodes and Clouds → Configure Clouds**

1. Click **Add a new cloud** → **Kubernetes**
2. Configure the following:
   - **Name**: `k3d-mycluster`
   - **Kubernetes URL**: Leave empty
   - **Disable HTTPS certificate check**: ✅ Enabled
   - **Credentials**: Select your stored `k3d-kubeconfig` credential
   - **Jenkins URL**: `http://THE-MACBOOK-IPAddress:8080` (find with `ifconfig` or `ipconfig`)
   - **Jenkins tunnel**: `THE-MACBOOK-IPAddress:50000`

3. Click **Test Connection** to verify
4. Save the configuration

## SonarQube Configuration

### Step 5: Configure SonarQube

#### 5.1 Initial Setup
1. Access SonarQube at `http://localhost:9000`
2. Login with default credentials: `admin/admin`
3. Change password to `user` (new login: `admin/user`)

#### 5.2 Create Project
1. Click **Create Project** → **Manually**
2. Configure:
   - **Display name**: `DevSecOps-PetClinic`
   - **Project Key**: `DevSecOps-PetClinic`
   - **Main branch name**: `main`
3. Click **Set Up**
4. Select **Locally**
5. Generate and save the authentication token (e.g., `sqp_11815a7c07216bae7ee310fa4d0c27c498fb7311`)

#### 5.3 Create Webhook
1. In the project, go to **Project Settings → Webhooks**
2. Click **Create**
3. Configure:
   - **Name**: `Jenkins-On-Docker`
   - **URL**: `http://172.19.0.6:8080/sonarqube-webhook/`
4. Save the webhook

### Step 6: Connect Jenkins to SonarQube

#### 6.1 Add SonarQube Token to Jenkins
Create the SonarQube credential in Jenkins (if not done in Step 4.3):
- **Kind**: Secret text
- **Secret**: Paste the SonarQube token from Step 5.2
- **ID**: `sonarqube-token`

#### 6.2 Configure SonarQube Server in Jenkins
1. Navigate to **Manage Jenkins → Configure System**
2. Find **SonarQube Servers** section
3. Click **Add SonarQube**
4. Configure:
   - **Name**: `SonarQube-on-Docker`
   - **Server URL**: `http://172.19.0.7:9000`
   - **Server authentication token**: Select `sonarqube-token`
5. Save configuration

## Pipeline Creation

### Step 7: Create Jenkins Agent Pod Template

See [jenkins-agent-pod-template.yaml](jenkins-agent-pod-template.yaml)

### Step 8: Create Multibranch Pipeline

#### 8.1 Create Project Configuration File
In your project repository root, create `sonar-project.properties`:

```properties
sonar.projectName=DevSecOps-PetClinic
sonar.projectKey=DevSecOps-PetClinic
sonar.sources=src/main/java
sonar.tests=src/test/java
sonar.java.binaries=target/classes
sonar.java.test.binaries=target/test-classes
```

#### 8.2 Create Jenkins Pipeline
1. On Jenkins dashboard, click **New Item**
2. Enter name: `PetClinic`
3. Select **Multibranch Pipeline**
4. Configure:
   - **Display Name**: Leave empty
   - **Branch Sources**: 
     - Add **GitHub**
     - **Credentials**: Select `github-credentials`
     - **Repository HTTPS URL**: `https://github.com/vjkancherla/DevSecOps-ArgoCD`
     - **Behaviors**:
       - **Discover branches**: All Branches
       - **Filter by name (with wildcards)**: Include `feature/*`
   - **Build Configuration**: by Jenkinsfile
5. Save the configuration

## Verification

### Step 9: Test the Setup

#### 9.1 Test Kubernetes Connectivity
Create a simple test pipeline in Jenkins:

```groovy
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
            args: ["$(JENKINS_SECRET)", "$(JENKINS_NAME)"]
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

#### 9.2 Verify Services
Check that all services are running:
```bash
# Check K3d cluster
kubectl get nodes

# Check Jenkins and SonarQube containers
docker ps | grep -E "(jenkins|sonarqube)"

# Check persistent volumes
kubectl get pv,pvc -n jenkins
```

## Troubleshooting

### Common Issues

#### Jenkins Agent Connection Issues
- Verify the Jenkins URL and tunnel configuration use your machine's IP, not localhost
- Check that port 50000 is accessible
- Ensure the K3d network allows communication

#### SonarQube Webhook Issues
- Verify the webhook URL uses the correct Jenkins container IP (172.19.0.6)
- Check that both services are on the same Docker network

#### Persistent Volume Issues
- Ensure K3d agent node has the required mount paths
- Verify PV and PVC are bound correctly
- Check that the node selector matches the agent node name

#### Network Connectivity
```bash
# Test network connectivity
docker network inspect k3d-mycluster

# Check container IPs
docker inspect jenkins-docker | grep IPAddress
docker inspect sonarqube | grep IPAddress
```

### Useful Commands

```bash
# Restart services
docker-compose down && docker-compose up -d

# View logs
docker logs jenkins-docker
docker logs sonarqube

# Reset K3d cluster
k3d cluster delete mycluster
# Then follow setup steps again

# Check Jenkins agent pods
kubectl get pods -n jenkins
kubectl logs -f <pod-name> -n jenkins
```

## Next Steps

Once the setup is complete, you can:
1. Create comprehensive Jenkinsfiles with DevSecOps stages
2. Add more security scanning tools
3. Integrate with ArgoCD for GitOps deployments
4. Set up monitoring and alerting
5. Implement advanced security policies

Your DevSecOps pipeline is now ready to build, test, scan, and deploy applications with security integrated throughout the development lifecycle!