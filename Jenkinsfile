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
    REGISTRY_USER = "vjkancherla"
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

     stage("Sonarqube Analysis "){
        steps {
          withSonarQubeEnv(installationName: "SonarQube-on-Docker") {
            container("sonar-scanner") {
              // uses sonar-project.properties to identify the resources to scan
              sh 'sonar-scanner'
            }
          }
        }
      }

      stage("quality gate"){
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

  } // End Stages

} // End pipeline
