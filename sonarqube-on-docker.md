We will install and run Sonarqube on docker
==========

[1] Install and run Sonarqube

Note that we need to have Jenkins and Sonarqube running on the SAME docker network so that they can communicate.
This means that Jenkins, Sonarqube and K3D will be on tha name network.

>> docker run -d --name sonarqube \
-p 9000:9000 -p 9092:9092 \
-v /Users/vkancherla/Downloads/Docker-Volumes/sonarqube-volume:/opt/sonarqube/data \
--network=k3d-mycluster \
--ip 172.19.0.7 \
-e TZ=Europe/London \
sonarqube:9.9.8-community


[2] Access console at http://localhost:9000 and login using admin/admin


[3] Change password to "user". Login now is - admin/user


[4] To analyse Golang code, we need a tool called SonarScanner. This tool is installed on the Jenkins server.
SonarScanner is a command-line tool used to analyze projects and send the results to the SonarQube server


[4.1] The way the code scanning works is:
a. During a build, Jenkins will checkout source code
b. scan the code using SonarScanner
c. send the results to SonarQube server


Connecting Jenkins to SonarQube
==============================

[1] In SonarQube do the following:
a. Create "Project" >>  Select "Manually"
b. Display name: Monorepo-X
   Project Key: project-key-12345
   main branch name: main
c. Once project is created, click on it and select "Locally"
d. generate token and save the token
 sqp_11815a7c07216bae7ee310fa4d0c27c498fb7311

 [1.1] In SonarQube, create a webhook to let SonarQube post scan results back to Jenkins:
 a. Find Jenkins container's IP:
 >> docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' jenkins-docker
 172.18.0.6
 b. For the Monorepo-X project, go to Project Settings>Webhooks
 c. Create new Webhook:
 Name: Jenkins-On-Docker
 URL: http://172.18.0.6/sonarqube-webhook/

[2] In Jenkins, install SonarQube Scanner Plugin and the Sonar Quality Gate plugin

[3] Create a Jenkins Credential of type "secret text" and name - "sonarqube-token" save the token from step-1.d

[4] Get the SonarQube URL
>> docker ps | grep sonarqube
>> docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' sonarqube
172.20.0.7

[4.1] Go to "Manage Jenkins" > "Configure System".
Now, you should see the "SonarQube Servers" section.
Click on "Add SonarQube" to add a SonarQube server configuration.
Provide a name for the server - "SonarQube-on-Docker"
Enter the URL of your SonarQube server (e.g., http://localhost:9000). Set it to - http://172.20.0.7:9000
Server authentication token: Select the credential created in step-2

[5] At the root of your source code directory, define a file called sonar-project.properties with the following values:
sonar.projectName=DevSecOps-PetClinic
sonar.projectKey=DevSecOps-PetClinic
sonar.sources=src/main/java
sonar.tests=src/test/java
sonar.java.binaries=target/classes
sonar.java.test.binaries=target/test-classes