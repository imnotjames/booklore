# Stage 1: Build the Angular app
FROM node:24-alpine AS angular-build

WORKDIR /angular-app

COPY ./booklore-ui/package.json ./booklore-ui/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm config set registry https://registry.npmjs.org/ \
    && npm ci --force

COPY ./booklore-ui /angular-app/

RUN npm run build --configuration=production

# Stage 2: Build the Spring Boot app with Gradle
FROM gradle:9.3.1-jdk25-alpine AS springboot-build

WORKDIR /springboot-app

# Copy only build files first to cache dependencies
COPY ./booklore-api/build.gradle ./booklore-api/settings.gradle /springboot-app/

# Download dependencies (cached layer)
RUN --mount=type=cache,target=/home/gradle/.gradle \
    gradle dependencies --no-daemon

COPY ./booklore-api/src /springboot-app/src

# Copy Angular dist into Spring Boot static resources so it's embedded in the JAR
COPY --from=angular-build /angular-app/dist/booklore/browser /springboot-app/src/main/resources/static

# Inject version into application.yaml using yq
ARG APP_VERSION
RUN apk add --no-cache yq && \
    yq eval '.app.version = strenv(APP_VERSION)' -i /springboot-app/src/main/resources/application.yaml

RUN --mount=type=cache,target=/home/gradle/.gradle \
    gradle clean build -x test --no-daemon --parallel

FROM scratch AS dependency-kepubify

ARG KEPUBIFY_VERSION="4.0.4"
ARG KEPUBIFY_AMD64_CHECKSUM="sha256:37d7628d26c5c906f607f24b36f781f306075e7073a6fe7820a751bb60431fc5"
ARG KEPUBIFY_ARM64_CHECKSUM="sha256:5a15b8f6f6a96216c69330601bca29638cfee50f7bf48712795cff88ae2d03a3"

ADD \
      --checksum="${KEPUBIFY_AMD64_CHECKSUM}" \
      --chmod=755 \
      https://github.com/pgaskin/kepubify/releases/download/v${KEPUBIFY_VERSION}/kepubify-linux-64bit /kepubify-amd64
ADD \
      --checksum="${KEPUBIFY_ARM64_CHECKSUM}" \
      --chmod=755 \
      https://github.com/pgaskin/kepubify/releases/download/v${KEPUBIFY_VERSION}/kepubify-linux-arm64 /kepubify-arm64

# Stage 3: Final image
FROM eclipse-temurin:25-jre-alpine

ARG APP_VERSION
ARG APP_REVISION

# Set OCI labels
LABEL org.opencontainers.image.title="BookLore" \
      org.opencontainers.image.description="BookLore: A self-hosted, multi-user digital library with smart shelves, auto metadata, Kobo & KOReader sync, BookDrop imports, OPDS support, and a built-in reader for EPUB, PDF, and comics." \
      org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.revision=$APP_REVISION \
      org.opencontainers.image.licenses="GPL-3.0" \
      org.opencontainers.image.base.name="docker.io/library/eclipse-temurin:25-jre-alpine"

ENV JAVA_TOOL_OPTIONS="-XX:+UseG1GC -XX:+UseCompactObjectHeaders -XX:+UseStringDeduplication -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

ARG TARGETARCH
RUN apk update && apk add --no-cache su-exec libstdc++ libgcc && \
    mkdir -p /bookdrop

COPY docker/unrar/unrar-${TARGETARCH} /usr/local/bin/unrar
RUN chmod 755 /usr/local/bin/unrar

COPY --from=mwader/static-ffmpeg:8.1 /ffprobe /usr/local/bin/ffprobe
COPY --from=dependency-kepubify /kepubify-${TARGETARCH} /usr/local/bin/kepubify

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
COPY --from=springboot-build /springboot-app/build/libs/booklore-api-0.0.1-SNAPSHOT.jar /app/app.jar

ARG BOOKLORE_PORT=6060
EXPOSE ${BOOKLORE_PORT}

ENTRYPOINT ["entrypoint.sh"]
CMD ["java", "-jar", "/app/app.jar"]
