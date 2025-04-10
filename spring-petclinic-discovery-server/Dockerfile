FROM eclipse-temurin:17-jdk-alpine
VOLUME /tmp
# install curl
RUN apk update && apk add curl
COPY target/*.jar app.jar
EXPOSE 8761
ENTRYPOINT ["java","-jar","/app.jar"]
