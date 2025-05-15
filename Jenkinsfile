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
  }

}
