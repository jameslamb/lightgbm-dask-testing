AWS_REGION=us-west-2
DASK_VERSION=2021.9.1
USER_SLUG=$$(echo $${USER} | tr '[:upper:]' '[:lower:]' | tr -cd '[a-zA-Z0-9]-')
CLUSTER_BASE_IMAGE=lightgbm-dask-testing-cluster-base:${DASK_VERSION}
CLUSTER_IMAGE_NAME=lightgbm-dask-testing-cluster-${USER_SLUG}
CLUSTER_IMAGE=${CLUSTER_IMAGE_NAME}:${DASK_VERSION}
FORCE_REBUILD=0
NOTEBOOK_BASE_IMAGE=lightgbm-dask-testing-notebook-base:${DASK_VERSION}
NOTEBOOK_IMAGE=lightgbm-dask-testing-notebook:${DASK_VERSION}
NOTEBOOK_CONTAINER_NAME=dask-lgb-notebook

.PHONY: clean
clean:
	docker rmi $$(docker images -q ${CLUSTER_IMAGE}) || true
	docker rmi $$(docker images -q ${CLUSTER_BASE_IMAGE}) || true
	docker rmi $$(docker images -q ${NOTEBOOK_IMAGE}) || true
	docker rmi $$(docker images -q ${NOTEBOOK_BASE_IMAGE}) || true

.PHONY: cluster-base-image
cluster-base-image:
	@if $$(docker image inspect ${CLUSTER_BASE_IMAGE} > /dev/null); then \
		if test ${FORCE_REBUILD} -le 0; then \
			echo "image '${CLUSTER_BASE_IMAGE}' already exists. To force rebuilding, run 'make cluster-base-image -e FORCE_REBUILD=1'."; \
			exit 0; \
		fi; \
	fi; \
	docker build \
		--build-arg DASK_VERSION=${DASK_VERSION} \
		-t ${CLUSTER_BASE_IMAGE} \
		- < Dockerfile-cluster-base

.PHONY: cluster-image
cluster-image: cluster-base-image LightGBM/lib_lightgbm.so
	docker build \
		--build-arg DASK_VERSION=${DASK_VERSION} \
		-t ${CLUSTER_IMAGE} \
		--build-arg BASE_IMAGE=${CLUSTER_BASE_IMAGE} \
		-f Dockerfile-cluster \
		.

.PHONY: create-repo
create-repo: ecr-details.json

.PHONY: delete-repo
delete-repo:
	aws --region ${AWS_REGION} \
		ecr-public batch-delete-image \
			--repository-name ${CLUSTER_IMAGE_NAME} \
			--image-ids imageTag=${DASK_VERSION}
	aws --region ${AWS_REGION} \
		ecr-public delete-repository \
			--repository-name ${CLUSTER_IMAGE_NAME}
	rm -f ./ecr-details.json

ecr-details.json:
	aws --region ${AWS_REGION} \
		ecr-public create-repository \
			--repository-name ${CLUSTER_IMAGE_NAME} \
	> ./ecr-details.json

.PHONY: format
format:
	black .
	isort .
	nbqa isort . --nbqa-mutate
	nbqa black . --nbqa-mutate

LightGBM/README.md:
	git clone --recursive https://github.com/microsoft/LightGBM.git

LightGBM/lib_lightgbm.so: LightGBM/README.md
	docker run \
		--rm \
		-v $$(pwd)/LightGBM:/opt/LightGBM \
		--workdir=/opt/LightGBM \
		--entrypoint="" \
		-it ${NOTEBOOK_BASE_IMAGE} \
		/bin/bash -cex \
			"mkdir build && cd build && cmake .. && make -j2"

.PHONY: lightgbm-unit-tests
lightgbm-unit-tests: cluster-image
	docker run \
		--rm \
		-v $$(pwd)/LightGBM:/opt/LightGBM \
		--workdir=/opt/LightGBM \
		--entrypoint="" \
		-it ${CLUSTER_IMAGE} \
		/bin/bash -cex \
			"pip install pytest && pytest tests/python_package_test/test_dask.py"

.PHONY: lint
lint: lint-dockerfiles
	isort --check .
	black --check --diff .
	diff_lines=$$(nbqa black --nbqa-diff . | wc -l); \
	if [ $${diff_lines} -gt 0 ]; then \
		echo "Some notebooks would be reformatted by black. Run 'make format' and try again."; \
		exit 1; \
	fi
	flake8 --count .
	nbqa flake8 .
	nbqa isort --check .

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
	docker build \
		--build-arg DASK_VERSION=${DASK_VERSION} \
		-t ${NOTEBOOK_BASE_IMAGE} \
		- < Dockerfile-notebook-base

.PHONY: notebook-image
notebook-image: notebook-base-image LightGBM/lib_lightgbm.so
	docker build \
		-t ${NOTEBOOK_IMAGE} \
		-f Dockerfile-notebook \
		--build-arg BASE_IMAGE=${NOTEBOOK_BASE_IMAGE} \
		.

# https://docs.amazonaws.cn/en_us/AmazonECR/latest/public/docker-push-ecr-image.html
.PHONY: push-image
push-image: create-repo
	aws ecr-public get-login-password \
		--region ${AWS_REGION} \
	| docker login \
		--username AWS \
		--password-stdin public.ecr.aws
	docker tag \
		${CLUSTER_IMAGE_NAME}:${DASK_VERSION} \
		$$(cat ./ecr-details.json | jq .'repository'.'repositoryUri' | tr -d '"'):${DASK_VERSION}
	docker push \
		$$(cat ./ecr-details.json | jq .'repository'.'repositoryUri' | tr -d '"'):${DASK_VERSION}

.PHONY: start-notebook
start-notebook:
	docker run \
		--rm \
		-v $$(pwd):/home/jovyan/testing \
		--env AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-notset} \
		--env AWS_DEFAULT_REGION=${AWS_REGION} \
		--env AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY:-notset} \
		-p 8888:8888 \
		-p 8787:8787 \
		--name ${NOTEBOOK_CONTAINER_NAME} \
		${NOTEBOOK_IMAGE}

.PHONY: stop-notebook
stop-notebook:
	@docker kill ${NOTEBOOK_CONTAINER_NAME}
	@docker rm ${NOTEBOOK_CONTAINER_NAME}
