# NOTE: using us-east-1 because it is the only region that supports
#       ECR BatchDeleteImage()
AWS_REGION=us-east-1
DASK_VERSION=2024.6.2
PYTHON_VERSION=3.12
IMAGE_TAG=py${PYTHON_VERSION}-dask${DASK_VERSION}
USER_SLUG=$$(echo $${USER} | tr '[:upper:]' '[:lower:]' | tr -cd '[a-zA-Z0-9]-')
CLUSTER_BASE_IMAGE=lightgbm-dask-testing-cluster-base:${IMAGE_TAG}
CLUSTER_IMAGE_NAME=lightgbm-dask-testing-cluster-${USER_SLUG}
CLUSTER_IMAGE=${CLUSTER_IMAGE_NAME}:${IMAGE_TAG}
FORCE_REBUILD=0
FORCE_REBUILD_PROFILING_IMAGE=0
NOTEBOOK_BASE_IMAGE=lightgbm-dask-testing-notebook-base:${IMAGE_TAG}
NOTEBOOK_IMAGE=lightgbm-dask-testing-notebook:${IMAGE_TAG}
NOTEBOOK_CONTAINER_NAME=dask-lgb-notebook
PROFILING_IMAGE=lightgbm-dask-testing-profiling:${IMAGE_TAG}

LIB_LIGHTGBM=${PWD}/LightGBM/lib_lightgbm.so
LIGHTGBM_REPO=${PWD}/LightGBM/README.md

.PHONY: clean
clean:
	docker rmi $$(docker images -q ${CLUSTER_IMAGE}) || true
	docker rmi $$(docker images -q ${CLUSTER_BASE_IMAGE}) || true
	docker rmi $$(docker images -q ${NOTEBOOK_IMAGE}) || true
	docker rmi $$(docker images -q ${NOTEBOOK_BASE_IMAGE}) || true
	docker rmi $$(docker images -q ${PROFILING_IMAGE}) || true
	rm -rf ./LightGBM/build
	rm -f ./LightGBM/lib_lightgbm.so

.PHONY: cluster-base-image
cluster-base-image:
	@if $$(docker image inspect ${CLUSTER_BASE_IMAGE} > /dev/null); then \
		if test ${FORCE_REBUILD} -le 0; then \
			echo "image '${CLUSTER_BASE_IMAGE}' already exists. To force rebuilding, run 'make cluster-base-image -e FORCE_REBUILD=1'."; \
			exit 0; \
		fi; \
	fi; \
	docker buildx build \
		--build-arg DASK_VERSION=${DASK_VERSION} \
		--build-arg PYTHON_VERSION=${PYTHON_VERSION} \
		--load \
		--output type=docker \
		-t ${CLUSTER_BASE_IMAGE} \
		-f ./Dockerfile-cluster-base \
		.
	echo "--- docker images ---"
	docker images

.PHONY: cluster-image
cluster-image: cluster-base-image $(LIB_LIGHTGBM)
	docker buildx build \
		--build-arg BASE_IMAGE=${CLUSTER_BASE_IMAGE} \
		--load \
		--output type=docker \
		-t ${CLUSTER_IMAGE} \
		-f ./Dockerfile-cluster \
		.

.PHONY: create-repo
create-repo: ecr-details.json

.PHONY: delete-repo
delete-repo:
	aws --region ${AWS_REGION} \
		ecr-public batch-delete-image \
			--repository-name ${CLUSTER_IMAGE_NAME} \
			--image-ids imageTag=${IMAGE_TAG}
	aws --region ${AWS_REGION} \
		ecr-public delete-repository \
			--repository-name ${CLUSTER_IMAGE_NAME}
	rm -f ./ecr-details.json

ecr-details.json:
	aws --region ${AWS_REGION} \
		ecr-public create-repository \
			--repository-name ${CLUSTER_IMAGE_NAME} \
	> ./ecr-details.json

$(LIGHTGBM_REPO):
	git clone --recursive https://github.com/microsoft/LightGBM.git

$(LIB_LIGHTGBM): $(LIGHTGBM_REPO)
	make notebook-base-image
	docker run \
		--rm \
		-v $$(pwd)/LightGBM:/opt/LightGBM \
		--workdir=/opt/LightGBM \
		--entrypoint="" \
		-i ${NOTEBOOK_BASE_IMAGE} \
		/bin/bash -cex \
			"rm -rf ./build && cmake -B build -S . && cmake --build build --target _lightgbm -j2"

.PHONY: lightgbm-unit-tests
lightgbm-unit-tests:
	docker run \
		--rm \
		-v $$(pwd)/LightGBM:/opt/LightGBM \
		--workdir=/opt/LightGBM \
		--entrypoint="" \
		-i ${CLUSTER_IMAGE} \
		/bin/bash -cex \
			"sh ./build-python.sh install --precompile && pip install pytest && pytest -vv -rA tests/python_package_test/test_dask.py"

.PHONY: lint-dockerfiles
lint-dockerfiles:
	for dockerfile in $$(ls | grep -E '^Dockerfile'); do \
		echo "linting $${dockerfile}" && \
		docker run \
			--rm \
			-v $$(pwd)/.hadolint.yaml:/.config/hadolint.yaml \
			-i \
			hadolint/hadolint \
		< $${dockerfile} || exit 1; \
	done

.PHONY: notebook-base-image
notebook-base-image:
	@if $$(docker image inspect ${NOTEBOOK_BASE_IMAGE} > /dev/null); then \
		if test ${FORCE_REBUILD} -le 0; then \
			echo "image '${NOTEBOOK_BASE_IMAGE}' already exists. To force rebuilding, run 'make notebook-base-image -e FORCE_REBUILD=1'."; \
			exit 0; \
		fi; \
	fi; \
	docker buildx build \
		--build-arg DASK_VERSION=${DASK_VERSION} \
		--build-arg PYTHON_VERSION=${PYTHON_VERSION} \
		--load \
		--output type=docker \
		-t ${NOTEBOOK_BASE_IMAGE} \
		-f ./Dockerfile-notebook-base \
		.

.PHONY: notebook-image
notebook-image: notebook-base-image $(LIB_LIGHTGBM)
	docker buildx build \
		--build-arg BASE_IMAGE=${NOTEBOOK_BASE_IMAGE} \
		--load \
		--output type=docker \
		-t ${NOTEBOOK_IMAGE} \
		-f ./Dockerfile-notebook \
		.

.PHONY: profile
profile: profiling-image
	docker run \
		--rm \
		-p 8080:8080 \
		--env LIGHTGBM_HOME=/opt/LightGBM \
		--env PROFILING_OUTPUT_DIR=/profiling-output \
		-v $$(pwd)/profiling-output:/profiling-output \
		-v $$(pwd)/LightGBM:/opt/LightGBM \
		--workdir=/opt/LightGBM \
		--entrypoint="" \
		-i ${PROFILING_IMAGE} \
		/bin/bash -cex \
			'/bin/bash /usr/local/bin/profile-examples.sh && python -m snakeviz /profiling-output/ --hostname 0.0.0.0 --server'

.PHONY: profiling-image
profiling-image: cluster-image
	@if $$(docker image inspect ${PROFILING_IMAGE} > /dev/null); then \
		if test ${FORCE_REBUILD_PROFILING_IMAGE} -le 0; then \
			echo "image '${PROFILING_IMAGE}' already exists. To force rebuilding, run 'make profiling-image -e FORCE_REBUILD_PROFILING_IMAGE=1'."; \
			exit 0; \
		fi; \
	fi && \
	docker buildx build \
		--build-arg BASE_IMAGE=${CLUSTER_IMAGE} \
		--load \
		--output type=docker \
		-t ${PROFILING_IMAGE} \
		-f ./Dockerfile-profiling \
		.

.PHONY: profile-memory-usage
profile-memory-usage: profiling-image
	docker run \
		--rm \
		--env LIGHTGBM_HOME=/opt/LightGBM \
		--env PROFILING_OUTPUT_DIR=/profiling-output/memory-usage \
		-v $$(pwd)/profiling-output:/profiling-output \
		-v $$(pwd)/LightGBM:/opt/LightGBM \
		--workdir=/opt/LightGBM \
		--entrypoint="" \
		-i ${PROFILING_IMAGE} \
		/bin/bash -cex \
			'/bin/bash /usr/local/bin/profile-example-memory-usage.sh'

# https://docs.amazonaws.cn/en_us/AmazonECR/latest/public/docker-push-ecr-image.html
.PHONY: push-image
push-image: create-repo
	aws ecr-public get-login-password \
		--region ${AWS_REGION} \
	| docker login \
		--username AWS \
		--password-stdin public.ecr.aws
	docker tag \
		${CLUSTER_IMAGE_NAME}:${IMAGE_TAG} \
		$$(cat ./ecr-details.json | jq .'repository'.'repositoryUri' | tr -d '"'):${IMAGE_TAG}
	docker push \
		$$(cat ./ecr-details.json | jq .'repository'.'repositoryUri' | tr -d '"'):${IMAGE_TAG}

# NOTE: IMAGE_TAG is in the environment here so the AWS notebooks
#       know what image to use for the Dask cluster
.PHONY: start-notebook
start-notebook:
	docker run \
		--rm \
		-v $$(pwd):/root/testing \
		--env AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-notset} \
		--env AWS_DEFAULT_REGION=${AWS_REGION} \
		--env AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY:-notset} \
		--env IMAGE_TAG=${IMAGE_TAG} \
		-p 8888:8888 \
		-p 8787:8787 \
		--name ${NOTEBOOK_CONTAINER_NAME} \
		${NOTEBOOK_IMAGE}

.PHONY: stop-notebook
stop-notebook:
	@docker kill ${NOTEBOOK_CONTAINER_NAME}
	@docker rm ${NOTEBOOK_CONTAINER_NAME}
