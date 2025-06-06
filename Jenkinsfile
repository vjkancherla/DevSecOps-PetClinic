pipeline {
  agent {
    kubernetes {
      yamlFile "jenkins-agent-pod-template.yaml"
    }
  }

  parameters {
    booleanParam(name: 'RUN_BUILD', defaultValue: true, description: 'Run Maven build, test and package')
    booleanParam(name: 'RUN_CODE_QUALITY', defaultValue: true, description: 'Run SonarQube and quality gate')
    booleanParam(name: 'RUN_SECURITY_SCANS', defaultValue: true, description: 'Run security scans (except OWASP)')
    booleanParam(name: 'RUN_OWASP_SCAN', defaultValue: false, description: 'Run OWASP Dependency Check (resource intensive)')
    booleanParam(name: 'RUN_IMAGE_BUILD', defaultValue: true, description: 'Build and scan container image')
    booleanParam(name: 'RUN_HELM_OPERATIONS', defaultValue: true, description: 'Run Helm chart operations')
    booleanParam(name: 'RUN_CHART_PUBLISH', defaultValue: true, description: 'Package and publish Helm chart to Docker Hub')
    booleanParam(name: 'RUN_DEPLOYMENT', defaultValue: true, description: 'Run full deployment (including manual approval)')
  }

  options {
      disableConcurrentBuilds()
      buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
  }

  environment {
    PROJECT = "PetClinic"
    GIT_COMMIT_HASH = sh(script: "git log -n 1 --pretty=format:'%H'", returnStdout: true).trim()
    GIT_COMMIT_HASH_SHORT = "${GIT_COMMIT_HASH.take(8)}" 
    IMAGE_REPO = "vjkancherla/petclinic"
    IMAGE_TAG = "${GIT_COMMIT_HASH_SHORT}"
    
    // Docker Hub settings for Helm charts
    DOCKERHUB_ORG = "vjkancherla"
    CHART_NAME = "petclinic"
    DOCKER_REGISTRY = "registry-1.docker.io"
    
    // Generate semantic version from git tag or use commit-based version
    CHART_VERSION = sh(script: """
      if git describe --tags --exact-match HEAD 2>/dev/null; then
        git describe --tags --exact-match HEAD | sed 's/^v//'
      else 
        echo "0.1.${BUILD_NUMBER}+git.${GIT_COMMIT_HASH_SHORT}"
      fi
    """, returnStdout: true).trim()
  }

  stages {
    stage ("Mvn compile, test and package") {
      when { expression { params.RUN_BUILD } }
      steps {
        container("maven") {
          sh 'mvn clean package'
        }
      }
    }

    stage("Sonarqube analysis") {
      when { expression { params.RUN_CODE_QUALITY } }
      steps {
        withSonarQubeEnv(installationName: "SonarQube-on-Docker") {
          container("sonar-scanner") {
            sh 'sonar-scanner'
          }
        }
      }
    }

    stage("Quality gate") {
      when { expression { params.RUN_CODE_QUALITY } }
      steps {
        script {
          timeout(time: 5, unit: 'MINUTES') {
            def qG = waitForQualityGate()
            if (qG.status != 'OK') {
                error "Pipeline aborted due to quality gate failure: ${qG.status}"
            }
          }
        } 
      } 
    } 

    stage("Secrets scanning") {
      when { expression { params.RUN_SECURITY_SCANS } }
      steps {
        container("gitleaks") {
          sh 'gitleaks dir ./ --report-path "gitleaks-report.json" --report-format json'
        }
      }
    }

    // The OWASP dependency check take LOOONG TIME to run the first time round.
    // It downloads and caches the NVD database.
    stage("OWASP Dependency Check") {
      when { 
        allOf {
          expression { params.RUN_SECURITY_SCANS }
          expression { params.RUN_OWASP_SCAN }
        }
      }
      steps {
        container("owasp-dependency-check") {
          sh '''
            echo "Starting OWASP Dependency Check at $(date)"
            echo "Current directory: $(pwd)"
            ls -al
            echo "Available disk space:"
            df -h
            echo "Contents of data directory:"
            ls -la /usr/share/dependency-check/data/ || echo "Data directory not accessible"
            
            # Run OWASP dependency check with debug logging
            /usr/share/dependency-check/bin/dependency-check.sh \
              --scan ./src \
              --format HTML \
              --format JSON \
              --format XML \
              --out ./dependency-check-reports \
              --prettyPrint \
              --log /tmp/dependency-check.log \
              --nvdValidForHours 5004 \
              --data /usr/share/dependency-check/data
            
            echo "OWASP Dependency Check completed at $(date)"
            echo "Generated reports:"
            ls -la ./dependency-check-reports/ || echo "No reports generated"
          '''
        }
      }
    }
    
    stage("Build Image with Kaniko") {
      when { expression { params.RUN_IMAGE_BUILD } }
      steps {
        container("kaniko") {
          sh '''
            /kaniko/executor --context . \
            --dockerfile Dockerfile \
            --destination ${IMAGE_REPO}:${IMAGE_TAG} \
            --no-push \
            --tarPath ./image.tar
          '''
        }
      }
    }

    stage("Scan Image with Trivy") {
       when { 
        allOf {
          expression { params.RUN_SECURITY_SCANS }
          expression { params.RUN_IMAGE_BUILD }
        }
      }
      steps {
        container("trivy") {
          sh 'trivy image --input image.tar > trivy-image-scan-results.txt'
        }
      }
    }

    stage("Publish Image with Kaniko") {
      when { expression { params.RUN_IMAGE_BUILD } }
      steps {
        container("kaniko") {
          sh '''
            /kaniko/executor --context . \
            --dockerfile Dockerfile \
            --destination ${IMAGE_REPO}:${IMAGE_TAG} \
          '''
        }
      }
    }

    stage("Scan Helm Chart with Trivy") {
      when { 
        allOf {
          expression { params.RUN_SECURITY_SCANS }
          expression { params.RUN_HELM_OPERATIONS }
        }
      }
      steps {
        container("trivy") {
          sh '''
            trivy config \
            --helm-set image.repository=${IMAGE_REPO} \
            --helm-set image.tag=${IMAGE_TAG} \
            ./helm-chart > trivy-helm-scan-results.txt
          '''
        }
      }
    }

    stage("Package and Publish Helm Chart") {
      when { 
        allOf {
          expression { params.RUN_HELM_OPERATIONS }
          expression { params.RUN_CHART_PUBLISH }
        }
      }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_TOKEN')]) {
          container("kubectl-helm") {
            sh '''
              echo "Packaging Helm chart with version: ${CHART_VERSION}"
              echo "Using image: ${IMAGE_REPO}:${IMAGE_TAG}"
              
              # Update chart version and app version in Chart.yaml
              sed -i "s/^version:.*/version: ${CHART_VERSION}/" ./helm-chart/Chart.yaml
              sed -i "s/^appVersion:.*/appVersion: \"${IMAGE_TAG}\"/" ./helm-chart/Chart.yaml
              
              # Update default image in values.yaml to point to the newly built image
              sed -i "s|repository:.*|repository: ${IMAGE_REPO}|" ./helm-chart/values.yaml
              sed -i "s/tag:.*/tag: \"${IMAGE_TAG}\"/" ./helm-chart/values.yaml
              
              # Verify the changes
              echo "=== Updated Chart.yaml ==="
              cat ./helm-chart/Chart.yaml
              echo "=== Updated values.yaml ==="
              cat ./helm-chart/values.yaml
              
              # Package the Helm chart
              helm package ./helm-chart --version ${CHART_VERSION} --app-version ${IMAGE_TAG}
              
              # Login to Docker Hub registry for Helm
              echo "${DOCKERHUB_TOKEN}" | helm registry login ${DOCKER_REGISTRY} -u ${DOCKERHUB_USER} --password-stdin
              
              # Push chart to Docker Hub OCI registry
              helm push ${CHART_NAME}-${CHART_VERSION}.tgz oci://${DOCKER_REGISTRY}/${DOCKERHUB_ORG}
              
              echo "Successfully published Helm chart to oci://${DOCKER_REGISTRY}/${DOCKERHUB_ORG}/${CHART_NAME}:${CHART_VERSION}"
              echo "Chart contains image: ${IMAGE_REPO}:${IMAGE_TAG}"
            '''
          }
        }
      }
    }

    stage("Helm Install Dry Run") {
      when { expression { params.RUN_HELM_OPERATIONS } }
      steps {
        withCredentials([file(credentialsId: 'k3d-kubeconfig', variable: 'KUBECONFIG')]) {
          container("kubectl-helm") {
            sh '''
              helm upgrade --install petclinic-${GIT_COMMIT_HASH_SHORT} \
                -n ci-feature-${GIT_COMMIT_HASH_SHORT} \
                --create-namespace \
                --set image.repository=${IMAGE_REPO} \
                --set image.tag=${IMAGE_TAG} \
                --debug --dry-run \
                ./helm-chart
            '''
          }
        }
      }
    }

    stage ('Manual Approval of Release') {
      when { expression { params.RUN_DEPLOYMENT } }
      steps {
        script {
          timeout(time: 10, unit: 'MINUTES') {
            input(
              id: "DeployGate",
              message: "Deploy ${params.project_name}?",
              submitter: "approver",
              parameters: [choice(name: 'action', choices: ['Deploy'], description: 'Approve deployment')]
            )  
          }
        }
      }
    }

    stage("Helm Install Live Run") {
      when { expression { params.RUN_DEPLOYMENT } }
      steps {
        withCredentials([file(credentialsId: 'k3d-kubeconfig', variable: 'KUBECONFIG')]) {
          container("kubectl-helm") {
            sh '''
              helm upgrade --install petclinic-${GIT_COMMIT_HASH_SHORT} \
                -n ci-feature-${GIT_COMMIT_HASH_SHORT} \
                --create-namespace \
                --set image.repository=${IMAGE_REPO} \
                --set image.tag=${IMAGE_TAG} \
                --wait \
                --timeout 5m \
                ./helm-chart
            '''
          }
        }
      }
    }

    stage("Verify App") {
      when { expression { params.RUN_DEPLOYMENT } }
      steps {
        withCredentials([file(credentialsId: 'k3d-kubeconfig', variable: 'KUBECONFIG')]) {
          container("kubectl-helm") {
            sh 'helm test petclinic-${GIT_COMMIT_HASH_SHORT} -n ci-feature-${GIT_COMMIT_HASH_SHORT}'
            sh 'kubectl logs petclinic-test-connection -n ci-feature-${GIT_COMMIT_HASH_SHORT}'
            sh 'kubectl delete pod petclinic-test-connection -n ci-feature-${GIT_COMMIT_HASH_SHORT} --ignore-not-found=true'
          }
        }
      }
    }

    stage("Teardown App") {
      when { expression { params.RUN_DEPLOYMENT } }
      steps {
        withCredentials([file(credentialsId: 'k3d-kubeconfig', variable: 'KUBECONFIG')]) {
          container("kubectl-helm") {
            sh 'helm uninstall petclinic-${GIT_COMMIT_HASH_SHORT} -n ci-feature-${GIT_COMMIT_HASH_SHORT}'
            sh 'kubectl delete ns ci-feature-${GIT_COMMIT_HASH_SHORT}'
          }
        }
      }
    }
  }

  post {
    always {
      script {
        // Archive Trivy reports only if security scans or image builds are enabled
        if (params.RUN_SECURITY_SCANS || params.RUN_IMAGE_BUILD) {
          archiveArtifacts artifacts: 'trivy-*.txt', allowEmptyArchive: true
        }
        
        // Archive Gitleaks report only if security scans are enabled
        if (params.RUN_SECURITY_SCANS) {
          archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
        }
        
        // Archive OWASP Dependency Check report only if OWASP scan is enabled
        if (params.RUN_OWASP_SCAN) {
          archiveArtifacts artifacts: 'dependency-check-report*', allowEmptyArchive: true
        }
        
        // Archive packaged Helm charts if chart publishing is enabled
        if (params.RUN_CHART_PUBLISH) {
          archiveArtifacts artifacts: '*.tgz', allowEmptyArchive: true
        }
      }
    }
  }
}