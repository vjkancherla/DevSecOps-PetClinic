# Custom Jenkins Docker Image

A customized Jenkins Docker image with additional DevOps tools pre-installed for CI/CD pipelines, configured for k3d clusters.

## Image Details

- **Base Image**: `jenkins/jenkins:lts` (Jenkins LTS version)
- **Platform**: linux/amd64
- **Maintained by**: [Your Name/Organization]
- **Latest Version**: v2 (12 May 2025)
- **Jenkins Version**: 2.504.1

## Included Tools

The image comes pre-installed with:
- Docker CLI (20.10.7)
- Trivy (latest)
- kubectl (latest stable)
- Helm (v3.7.1)
- SonarScanner (4.6.2.2472)
- Python 3, pip, coverage.py

## Usage

### For k3d Cluster Deployment

```bash
docker run -d --name jenkins-docker \
  -p 8080:8080 -p 50000:50000 \
  -v /Users/vkancherla/Downloads/Docker-Volumes/jenkins-volume:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --network=k3d-mycluster \
  --ip 172.19.0.6 \
  -e TZ=Europe/London \
  vjkancherla/my-jenkins:v2