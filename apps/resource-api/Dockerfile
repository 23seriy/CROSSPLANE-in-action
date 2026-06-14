# hadolint ignore=DL3007
FROM golang:1.24-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o resource-api .

FROM alpine:3.20

LABEL org.opencontainers.image.title="resource-api" \
      org.opencontainers.image.description="Go microservice for Crossplane S3 demo" \
      org.opencontainers.image.source="https://github.com/23seriy/crossplane-in-action"

RUN apk --no-cache add ca-certificates \
    && addgroup -g 10001 -S appgroup \
    && adduser -u 10001 -S appuser -G appgroup

COPY --from=builder /app/resource-api /usr/local/bin/resource-api

USER 10001
EXPOSE 8080

CMD ["resource-api"]
