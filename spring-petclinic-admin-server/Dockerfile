FROM eclipse-temurin:17-jdk-alpine

WORKDIR /app

COPY target/*.jar app.jar

EXPOSE 9091

# Variable d'environnement pour le serveur Eureka
ENV EUREKA_SERVER_URL=http://discovery-server:8761/eureka/
ENV CONFIG_SERVER_URL=http://config-server:8888/
ENV SPRING_PROFILES_ACTIVE=default

ENTRYPOINT ["java", "-jar", "app.jar"]
