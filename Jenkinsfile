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

    stage("Secrets scanning"){
        steps {
          container("gitleaks") {
            
            sh 'gitleaks dir ./ --report-path "gitleaks-report.json" --report-format json'
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
