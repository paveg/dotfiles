.PHONY: echo linux.build linux.run

REPO_NAME = dotfiles
DOCKER_TAG ?= latest

echo:
	@echo "image -> ${REPO_NAME}:${DOCKER_TAG}"

linux.build:
	docker build -f docker/linux/Dockerfile --no-cache -t ${REPO_NAME}:${DOCKER_TAG} .

linux.run: linux.build
	docker run -it ${REPO_NAME}:${DOCKER_TAG}
