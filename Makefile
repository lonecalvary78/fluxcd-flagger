TAG?=latest
VERSION?=$(shell grep 'VERSION' pkg/version/version.go | awk '{ print $$4 }' | tr -d '"')
VERSION_MINOR:=$(shell grep 'VERSION' pkg/version/version.go | awk '{ print $$4 }' | tr -d '"' | rev | cut -d'.' -f2- | rev)
PATCH:=$(shell grep 'VERSION' pkg/version/version.go | awk '{ print $$4 }' | tr -d '"' | awk -F. '{print $$NF}')
SOURCE_DIRS = cmd pkg/apis pkg/controller pkg/server pkg/logging pkg/version
run:
	go run cmd/steerer/* -kubeconfig=$$HOME/.kube/config -log-level=info -metrics-server=https://prometheus.istio.weavedx.com

build:
	docker build -t stefanprodan/steerer:$(TAG) . -f Dockerfile

push:
	docker push stefanprodan/steerer:$(TAG)

fmt:
	gofmt -l -s -w $(SOURCE_DIRS)

test-fmt:
	gofmt -l -s $(SOURCE_DIRS) | grep ".*\.go"; if [ "$$?" = "0" ]; then exit 1; fi

test-codegen:
	./hack/verify-codegen.sh

test: test-fmt test-codegen
	go test ./...

helm-package:
	cd charts/ && helm package steerer/ && helm package podinfo-steerer/ && helm package grafana/
	mv charts/*.tgz docs/
	helm repo index docs --url https://stefanprodan.github.io/steerer --merge ./docs/index.yaml

helm-up:
	helm upgrade --install steerer ./chart/steerer --namespace=istio-system

version-set:
	@next="$(TAG)" && \
	current="$(VERSION)" && \
	sed -i '' "s/$$current/$$next/g" pkg/version/version.go && \
	sed -i '' "s/steerer:$$current/steerer:$$next/g" artifacts/steerer/deployment.yaml && \
	sed -i '' "s/tag: $$current/tag: $$next/g" charts/steerer/values.yaml && \
	sed -i '' "s/appVersion: $$current/appVersion: $$next/g" charts/steerer/Chart.yaml && \
	echo "Version $$next set in code, deployment and charts"

version-up:
	@next="$(VERSION_MINOR).$$(($(PATCH) + 1))" && \
	current="$(VERSION)" && \
	sed -i '' "s/$$current/$$next/g" pkg/version/version.go && \
	sed -i '' "s/steerer:$$current/steerer:$$next/g" artifacts/steerer/deployment.yaml && \
	sed -i '' "s/tag: $$current/tag: $$next/g" charts/steerer/values.yaml && \
	sed -i '' "s/appVersion: $$current/appVersion: $$next/g" charts/steerer/Chart.yaml && \
	echo "Version $$next set in code, deployment and chart"

dev-up: version-up
	@echo "Starting build/push/deploy pipeline for $(VERSION)"
	docker build -t stefanprodan/steerer:$(VERSION) . -f Dockerfile
	docker push stefanprodan/steerer:$(VERSION)
	kubectl apply -f ./artifacts/steerer/crd.yaml
	helm upgrade --install steerer ./charts/steerer --namespace=istio-system --set crd.create=false

release:
	git tag $(VERSION)
	git push origin $(VERSION)

release-set: fmt version-set helm-package
	git add .
	git commit -m "Release $(VERSION)"
	git push origin master
	git tag $(VERSION)
	git push origin $(VERSION)
