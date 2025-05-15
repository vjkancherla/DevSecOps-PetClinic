FROM tomcat:9.0.105-jre11-temurin-noble

COPY target/petclinic.war /usr/local/tomcat/webapps/

EXPOSE 8080