FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o resource-api .

FROM alpine:3.20
RUN apk --no-cache add ca-certificates
COPY --from=builder /app/resource-api /usr/local/bin/resource-api
EXPOSE 8080
CMD ["resource-api"]
