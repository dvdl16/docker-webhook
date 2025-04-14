# Dockerfile for https://github.com/adnanh/webhook
FROM        golang:alpine AS build
MAINTAINER  Dirk van der Laarse
WORKDIR     /go/src/github.com/adnanh/webhook
ENV         WEBHOOK_VERSION 2.8.2
RUN         apk add --update -t build-deps curl libc-dev gcc libgcc
RUN         curl -L --silent -o webhook.tar.gz https://github.com/adnanh/webhook/archive/${WEBHOOK_VERSION}.tar.gz && \
            tar -xzf webhook.tar.gz --strip 1
RUN         go get -d -v
RUN         CGO_ENABLED=0 go build -ldflags="-s -w" -o /usr/local/bin/webhook

FROM        alpine:latest
COPY        --from=build /usr/local/bin/webhook /usr/local/bin/webhook
WORKDIR     /etc/webhook
VOLUME      ["/etc/webhook"]
EXPOSE      9000
ENTRYPOINT  ["/usr/local/bin/webhook"]
