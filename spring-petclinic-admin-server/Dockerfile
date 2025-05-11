FROM eclipse-temurin:17-jdk-alpine
VOLUME /tmp
WORKDIR /app
COPY target/spring-petclinic-admin-server-3.0.2.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
