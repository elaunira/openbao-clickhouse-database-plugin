.PHONY: build build-linux clean test test-short lint fmt vet tidy sha256 install \
        docker-build docker-build-ubi docker-buildx docker-run

BINARY_NAME=clickhouse-database-plugin
VERSION?=dev
LDFLAGS=-ldflags "-X main.version=$(VERSION)"

# Container image settings. PLUGIN_VERSION must be valid semver with a leading
# "v": OpenBao rejects a non-semver version, and its catalog lookups normalise
# to a "v" prefix, so a version without one is registered but never found.
IMAGE?=ghcr.io/digitalis-io/openbao-plugin-database-clickhouse
IMAGE_TAG?=local
OPENBAO_VERSION?=2.4.4
PLUGIN_VERSION?=v0.0.0-dev
PLATFORMS?=linux/amd64,linux/arm64
DOCKER_BUILD_ARGS=--build-arg OPENBAO_VERSION=$(OPENBAO_VERSION) --build-arg VERSION=$(PLUGIN_VERSION)

build:
	CGO_ENABLED=0 go build $(LDFLAGS) -o $(BINARY_NAME) ./cmd/$(BINARY_NAME)

build-linux:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BINARY_NAME)-linux-amd64 ./cmd/$(BINARY_NAME)
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BINARY_NAME)-linux-arm64 ./cmd/$(BINARY_NAME)

clean:
	rm -f $(BINARY_NAME) $(BINARY_NAME)-*

test:
	go test -v -race -cover ./...

test-short:
	go test -v -short ./...

lint:
	golangci-lint run

fmt:
	go fmt ./...

vet:
	go vet ./...

tidy:
	go mod tidy

sha256:
	@sha256sum $(BINARY_NAME) | cut -d' ' -f1

# Build the alpine-based image for the local architecture.
docker-build:
	docker build --load --target default $(DOCKER_BUILD_ARGS) -t $(IMAGE):$(IMAGE_TAG) .

# Build the UBI-based image for the local architecture.
docker-build-ubi:
	docker build --load --target ubi $(DOCKER_BUILD_ARGS) -t $(IMAGE):$(IMAGE_TAG)-ubi .

# Build both flavours for all supported platforms. Multi-arch images cannot be
# loaded into the local daemon, so set PUSH=true to publish them instead.
docker-buildx:
	docker buildx build --target default --platform $(PLATFORMS) $(DOCKER_BUILD_ARGS) \
		-t $(IMAGE):$(IMAGE_TAG) $(if $(filter true,$(PUSH)),--push,) .
	docker buildx build --target ubi --platform $(PLATFORMS) $(DOCKER_BUILD_ARGS) \
		-t $(IMAGE):$(IMAGE_TAG)-ubi $(if $(filter true,$(PUSH)),--push,) .

# Run a dev-mode server with the plugin already registered.
docker-run: docker-build
	docker run --rm -p 8200:8200 $(IMAGE):$(IMAGE_TAG)

install: build
	mkdir -p $(DESTDIR)/usr/lib/openbao/plugins
	install -m 755 $(BINARY_NAME) $(DESTDIR)/usr/lib/openbao/plugins/

.DEFAULT_GOAL := build
