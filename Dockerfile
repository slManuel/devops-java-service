FROM eclipse-temurin:21-jdk@sha256:3e3c176ffed168beb42c607be9bc1639b466cf00261a0fb04425562c9d0c5c2b AS compile
WORKDIR /src
COPY src/main/java src/main/java
RUN mkdir -p classes && javac --release 21 -d classes src/main/java/demo/Main.java
FROM eclipse-temurin:21-jre@sha256:cff19e6215689161eb6162c11b86b0c60ddf802164f2eaf48d570f8fb79a36c5
WORKDIR /app
COPY --from=compile /src/classes /app/classes
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70", "-cp", "/app/classes", "demo.Main"]
