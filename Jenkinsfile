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
    stage ("Compile") {
      steps {
        container("maven") {
          sh 'mvn clean compile'
        }
      }
    }

    stage ("Test") {
      steps {
        container("maven") {
          sh 'mvn test'
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
          timeout(time: 2, unit: 'MINUTES') {
            def qG = waitForQualityGate()
            if (qG.status != 'OK') {
                error "Pipeline aborted due to quality gate failure: ${qG.status}"
            }
          }
        }
        
      } 
    } 

  } // End Stages

} // End pipeline
