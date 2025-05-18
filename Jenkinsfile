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
    GIT_COMMIT_HASH = sh (script: "git log -n 1 --pretty=format:'%H'", returnStdout: true)
    IMAGE_REPO = "vjkancherla/petclinic"
    IMAGE_TAG = "${GIT_COMMIT_HASH}"
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
            sh 'trivy image --input image.tar --severity HIGH,CRITICAL --exit-code 1'
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
  } // End Stages

} // End pipeline
