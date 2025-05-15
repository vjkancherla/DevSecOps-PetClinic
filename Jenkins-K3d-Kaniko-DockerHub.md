# Jenkins-K3d-Kaniko-DockerHub Integration

This setup demonstrates how Jenkins uses Kubernetes agents on K3d, and utilizes Kaniko to build and push images to DockerHub.

## Reference Video
[![YouTube Tutorial](https://img.youtube.com/vi/vMlUVDcriww/0.jpg)](https://www.youtube.com/watch?v=vMlUVDcriww)

## Prerequisites
- Followed previous setup from `/Users/vkancherla/Downloads/Devops-Projects/DevSecOps-PetClinic/JenkinsOnDocker-K8sOnK3D.md`

## DockerHub Configuration
1. Create a personal access token in DockerHub

## Kubernetes Secret Setup
Create a secret in the Jenkins namespace for DockerHub credentials:

```
kubectl create secret -n jenkins docker-registry docker-credentials \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=vjkancherla \
  --docker-password=<DOCKERHUB-TOKEN> \
  --docker-email=my_email@yahoo.com
```

This secret will be mounted to the Kaniko container for authentication.

## Jenkins Agent Pod Example
```
apiVersion: v1
kind: Pod
metadata:
  name: jenkins-agent
  namespace: jenkins
spec:
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:latest
    args: ['$(JENKINS_SECRET)', '$(JENKINS_NAME)']
    volumeMounts:
      - name: workspace-volume
        mountPath: /home/jenkins/agent

  - name: maven
    image: maven:3.8.6-openjdk-17
    command:
    - cat
    tty: true
    volumeMounts:
      - name: maven-cache
        mountPath: /root/.m2
      - name: workspace-volume
        mountPath: /home/jenkins/agent

  - name: kaniko
    image: gcr.io/kaniko-project/executor:v1.12.0
    command:
    - /busybox/cat
    tty: true
    volumeMounts:
      - name: kaniko-secret
        mountPath: /kaniko/.docker
      - name: workspace-volume
        mountPath: /home/jenkins/agent

  - name: kubectl-helm
    image: alpine/k8s:1.26.6
    command:
    - cat
    tty: true
    env:
    - name: KUBECONFIG
      value: /home/jenkins/agent/kubeconfig
    volumeMounts:
      - name: workspace-volume
        mountPath: /home/jenkins/agent

  - name: sonar-scanner
    image: sonarsource/sonar-scanner-cli:latest
    command:
    - cat
    tty: true
    volumeMounts:
      - name: workspace-volume
        mountPath: /home/jenkins/agent

  - name: trivy
    image: aquasec/trivy:0.45.1
    command:
    - cat
    tty: true
    volumeMounts:
      - name: workspace-volume
        mountPath: /home/jenkins/agent

  volumes:
  - name: workspace-volume
    emptyDir: {}
  - name: maven-cache
    emptyDir: {}
  - name: kaniko-secret
    secret:
      secretName: docker-credentials
      items:
      - key: .dockerconfigjson
        path: config.json
```