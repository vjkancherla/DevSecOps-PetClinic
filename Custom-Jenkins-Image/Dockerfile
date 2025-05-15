# Custom Jenkins Image with Kubectl, Helm, Docker-client, Coverage, SonarScanner and Trivy tools

## Built Image: vjkancherla/my-jenkins:v2 on 12May2025. The Jenkins version is 2.504.1
FROM --platform=linux/amd64 jenkins/jenkins:lts

USER root

# Install all system packages in a single RUN layer to reduce image size
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg2 \
        software-properties-common \
        sudo \
        python3 \
        python3-pip \
        python3-requests \
        python3-coverage \
        wget && \
    # Clean up in the same layer
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Verify that Java is installed
RUN java -version

# Install Docker CLI binary
RUN curl -fsSL -o docker.tgz https://download.docker.com/linux/static/stable/x86_64/docker-20.10.7.tgz && \
    tar xzvf docker.tgz --strip 1 -C /usr/bin docker/docker && \
    rm docker.tgz && \
    chmod +x /usr/bin/docker

# Configure Jenkins user permissions
RUN echo "jenkins ALL=NOPASSWD: ALL" >> /etc/sudoers && \
    groupadd -g 9999 docker && \
    usermod -aG docker jenkins

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# Install Helm
RUN curl -fsSL -o helm.tar.gz https://get.helm.sh/helm-v3.7.1-linux-amd64.tar.gz && \
    tar -zxvf helm.tar.gz && \
    install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm && \
    rm -rf linux-amd64 helm.tar.gz

# Install SonarScanner
RUN curl -fsSL -o sonar-scanner-cli.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-4.6.2.2472-linux.zip && \
    unzip sonar-scanner-cli.zip -d /opt/ && \
    mv /opt/sonar-scanner-4.6.2.2472-linux /opt/sonar-scanner && \
    rm sonar-scanner-cli.zip && \
    chmod -R 755 /opt/sonar-scanner

# Install Trivy
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Set environment variables
ENV PATH="/opt/sonar-scanner/bin:${PATH}"

USER jenkins