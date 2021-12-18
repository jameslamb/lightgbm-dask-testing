AWS_REGION=us-east-1
BASE_IMAGE=lightgbm-dask-testing-base:${DASK_VERSION}
USER_SLUG=$$(echo $${USER} | tr '[:upper:]' '[:lower:]' | tr -cd '[a-zA-Z0-9]-')
CLUSTER_IMAGE_NAME=lightgbm-dask-testing-cluster-${USER_SLUG}
DASK_VERSION=2021.9.1
NOTEBOOK_IMAGE=lightgbm-dask-testing-notebook:${DASK_VERSION}
NOTEBOOK_CONTAINER_NAME=dask-lgb-notebook

cluster-name:
	@echo ${USER_SLUG}
	@echo ${CLUSTER_IMAGE_NAME}

.PHONY: base-image
base-image:
	docker build \
		--build-arg DASK_VERSION=${DASK_VERSION} \
		-t ${BASE_IMAGE} \
		- < Dockerfile-base

.PHONY: clean
clean:
	git clean -d -f -X
	rm -rf ./LightGBM/

.PHONY: cluster-image
cluster-image: LightGBM/lib_lightgbm.so
	docker build \
		--build-arg DASK_VERSION=${DASK_VERSION} \
		-t ${CLUSTER_IMAGE_NAME}:${DASK_VERSION} \
		-f Dockerfile-cluster \
		.

.PHONY: create-repo
create-repo: ecr-details.json

.PHONY: delete-repo
delete-repo:
	aws --region us-east-1 \
		ecr-public batch-delete-image \
			--repository-name ${CLUSTER_IMAGE_NAME} \
			--image-ids imageTag=${DASK_VERSION}
	aws --region us-east-1 \
		ecr-public delete-repository \
			--repository-name ${CLUSTER_IMAGE_NAME}
	rm -f ./ecr-details.json

ecr-details.json:
	aws --region us-east-1 \
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
		-it ${BASE_IMAGE} \
		/bin/bash -cex \
			"mkdir build && cd build && cmake .. && make -j2"

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

.PHONY: notebook-image
notebook-image: LightGBM/README.md
	docker build \
		-t ${NOTEBOOK_IMAGE} \
		-f Dockerfile-notebook \
		--build-arg BASE_IMAGE=${BASE_IMAGE} \
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
		--env AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION} \
		--env AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY:-notset} \
		-p 8888:8888 \
		-p 8787:8787 \
		--name ${NOTEBOOK_CONTAINER_NAME} \
		${NOTEBOOK_IMAGE}

.PHONY: stop-notebook
stop-notebook:
	@docker kill ${NOTEBOOK_CONTAINER_NAME}
	@docker rm ${NOTEBOOK_CONTAINER_NAME}
