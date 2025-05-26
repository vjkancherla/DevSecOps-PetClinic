#!/usr/bin/groovy

pipeline {
  agent {
    kubernetes {
      yamlFile "jenkins-agent-pod-template.yml"
    }
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
  }

  stages {

    stage ("Mvn compile, test and package") {
      steps {
        container("maven") {
          // You don't need to explicitly run compile or test before package because Maven handles it.
          sh 'mvn clean package'
        }
      }
    }

     stage("Sonarqube analysis"){
        steps {
          withSonarQubeEnv(installationName: "SonarQube-on-Docker") {
            container("sonar-scanner") {
              // uses sonar-project.properties to identify the resources to scan
              sh 'sonar-scanner'
            }
          }
        }
      }

      stage("Quality gate"){
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

      stage("Secrets scanning"){
        steps {
          container("gitleaks") {
            // Ensure no secrets are stored in source code
            sh 'gitleaks dir ./ --report-path "gitleaks-report.json" --report-format json'
          }
        }
      }

      // This stage triggers fine, but takes super long due to downloading of the vulnerability DB each time.
      // Disabling it for now.
      // stage("OWASP Dependency Check") {
      //   steps {
      //     // see jenkins-owasp-dependency-check.md for setting up OWASP
      //     dependencyCheck additionalArguments: '--scan ./ --format HTML --prettyPrint', odcInstallation: 'OWASP-DP-Check'
      //     dependencyCheckPublisher pattern: '**/dependency-check-report.html'
      //   }
      // }

      
      stage("Build Image with Kaniko") {
        steps {
          container("kaniko") {
            // Use the "-no-push" option to only build the image and not push it at this stage
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
        steps {
          container("trivy") {
            // Scan up don't fail if there are CVEs
            //sh 'trivy image --input image.tar --severity HIGH,CRITICAL --exit-code 1'
            sh 'trivy image --input image.tar > trivy-image-scan-${env.BUILD_NUMBER}-results.txt'
          }
        }
      }

      stage("Publish Image with Kaniko") {
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
        steps {
          container("trivy") {
            sh '''
              trivy config \
              --helm-set image.repository=${IMAGE_REPO} \
              --helm-set image.tag=${IMAGE_TAG} \
              ./helm-chart > trivy-helm-scan-${env.BUILD_NUMBER}-results.txt
            '''
          }
        }
      }

      stage("Helm Install Dry Run") {
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

      stage ('Manual Approval of Release'){
        steps {
          script {
            timeout(time: 10, unit: 'MINUTES') {
            
            /*
            Send an Email to an Approver to approve the DeployGate
            */
            // def approvalMailContent = """
            // Project: ${env.JOB_NAME}
            // Build Number: ${env.BUILD_NUMBER}
            // Go to build URL and approve the deployment request.
            // URL de build: ${env.BUILD_URL}
            // """
            // mail(
            // to: 'postbox.vjk@gmail.com',
            // subject: "${currentBuild.result} CI: Project name -> ${env.JOB_NAME}", 
            // body: approvalMailContent,
            // mimeType: 'text/plain'
            // )

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
        steps {
          withCredentials([file(credentialsId: 'k3d-kubeconfig', variable: 'KUBECONFIG')]) {
            container("kubectl-helm") {
              // install chart and wait untill all resources are ready
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
        steps {
          withCredentials([file(credentialsId: 'k3d-kubeconfig', variable: 'KUBECONFIG')]) {
            container("kubectl-helm") {
              // Invoke the test-pod that is part of the helm-chart: helm-chart/templates/tests/post-install-check.yml
              sh 'helm test petclinic-${GIT_COMMIT_HASH_SHORT} -n ci-feature-${GIT_COMMIT_HASH_SHORT}'

              // Get the logs
              sh 'kubectl logs petclinic-test-connection -n ci-feature-${GIT_COMMIT_HASH_SHORT}'

              // Delete the test-pod
              sh 'kubectl delete pod petclinic-test-connection -n ci-feature-${GIT_COMMIT_HASH_SHORT} --ignore-not-found=true'
            }
          }
        }
      }

      stage("Teardown App") {
        steps {
          withCredentials([file(credentialsId: 'k3d-kubeconfig', variable: 'KUBECONFIG')]) {
            container("kubectl-helm") {
              // Invoke the test-pod that is part of the helm-chart: helm-chart/templates/tests/post-install-check.yml
              sh 'helm uninstall petclinic-${GIT_COMMIT_HASH_SHORT} -n ci-feature-${GIT_COMMIT_HASH_SHORT}'

              sh 'kubectl delete ns ci-feature-${GIT_COMMIT_HASH_SHORT}'
            }
          }
        }
      }

  } // End Stages

  post {
    always {
    // Archive raw scan reports for download
    archiveArtifacts artifacts: 'trivy-*.txt', allowEmptyArchive: true

    // Archive gitleaks scans report
    archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true
    
    // Optionally, Email the scan reports
    // emailext attachLog: true,
    //   subject: "'${currentBuild.result}'",
    //   body: "Project: ${env.JOB_NAME}<br/>" +
    //       "Build Number: ${env.BUILD_NUMBER}<br/>" +
    //       "URL: ${env.BUILD_URL}<br/>",
    //   to: 'postbox.vjk@gmail.com',
    //   attachmentsPattern: 'trivy-*.txt'
    // }
    }
  } // Eng Post

} // End pipeline
