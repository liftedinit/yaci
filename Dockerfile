# Start from the official Golang image to build our application.
FROM golang:1.23 AS builder

# Set the current working directory inside the container.
WORKDIR /app

# Copy go.mod and go.sum to download the dependencies.
# This is done before copying the source code to cache the dependencies layer.
COPY go.mod ./
COPY go.sum ./

# Download all dependencies. Dependencies will be cached if the go.mod and go.sum files are not changed.
RUN go mod download

# Copy the source code into the container.
COPY . .

# Build the Go app as a static binary.
# -o specifies the output file, in this case, the executable name.
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o yaci .

# Start from a Debian Slim image to keep the final image size down.
FROM debian:buster-slim

# Copy the pre-built binary file and script from the previous stage.
COPY --from=builder /app/yaci /usr/local/bin/yaci

ENTRYPOINT ["/usr/local/bin/yaci"]
