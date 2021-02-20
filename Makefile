include image.env

.PHONY: base-image
base-image:
	docker build --no-cache -t ${BASE_IMAGE} - < Dockerfile-base

clean:
	git clean -d -f -X

LightGBM/README.md:
	git clone --recursive https://github.com/microsoft/LightGBM.git

notebook-image: LightGBM/README.md
	docker build \
		--no-cache \
		-t ${IMAGE_NAME}:${IMAGE_TAG} \
		-f Dockerfile-notebook \
		--build-arg BASE_IMAGE=${BASE_IMAGE} \
		.

cluster-image: LightGBM/README.md
	docker build --no-cache -t ${CLUSTER_IMAGE_NAME}:${IMAGE_TAG} -f Dockerfile-cluster .

.PHONY: delete-repo
delete-repo:
	aws --region us-east-1 \
		ecr-public batch-delete-image \
			--repository-name ${CLUSTER_IMAGE_NAME} \
			--image-ids imageTag=${IMAGE_TAG}
	aws --region us-east-1 \
		ecr-public delete-repository \
			--repository-name ${CLUSTER_IMAGE_NAME}
	rm ecr-details.json

ecr-details.json:
	aws --region us-east-1 \
		ecr-public create-repository \
			--repository-name ${CLUSTER_IMAGE_NAME} \
	> ecr-details.json

create-repo: ecr-details.json

# https://docs.amazonaws.cn/en_us/AmazonECR/latest/public/docker-push-ecr-image.html
push-image: create-repo
	aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
	docker tag ${CLUSTER_IMAGE_NAME}:${IMAGE_TAG} $$(cat ecr-details.json | jq .'repository'.'repositoryUri' | tr -d '"'):1
	docker push $$(cat ecr-details.json | jq .'repository'.'repositoryUri' | tr -d '"'):1

.PHONY: start-notebook
start-notebook:
	docker run \
		-v $$(pwd):/home/jovyan/testing \
		--env AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY:-notset} \
		--env AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-notset} \
		-p 8888:8888 \
		-p 8787:8787 \
		--name ${CONTAINER_NAME} \
		${IMAGE_NAME}:${IMAGE_TAG}

.PHONY: stop-notebook
stop-notebook:
	@docker kill ${CONTAINER_NAME}
	@docker rm ${CONTAINER_NAME}

.PHONY: format
format:
	black .
	isort .
	nbqa isort . --nbqa-mutate
	nbqa black . --nbqa-mutate

.PHONY: lint
lint:
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
