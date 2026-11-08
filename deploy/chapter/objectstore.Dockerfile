# Official upstream's source-install route. Avoid disappeared/unauthenticated
# minio/minio images; this release fixes GHSA-jjjj-jwhf-8rgr.
FROM golang:1.25 AS build
RUN CGO_ENABLED=0 go install github.com/minio/minio@RELEASE.2025-10-15T17-29-55Z
FROM alpine:3.22
RUN apk add --no-cache ca-certificates curl
COPY --from=build /go/bin/minio /minio
EXPOSE 9000
ENTRYPOINT ["/minio"]
