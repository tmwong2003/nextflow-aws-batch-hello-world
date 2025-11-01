export AWS_ACCOUNT_ID=$(shell aws sts get-caller-identity --query Account --output text)
export AWS_REGION=$(shell aws configure get region)

export TF_VAR_docker_repository=nextflow-hello-world
export TF_VAR_aws_region=${AWS_REGION}
export TF_VAR_service_name=nextflow
export TF_VAR_service_owner=${USER}

export DOCKER_REGISTRY=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
export DOCKER_IMAGE_NAME=${TF_VAR_service_owner}/${TF_VAR_docker_repository}:latest

echo:
	@echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
	@echo "AWS Region: ${AWS_REGION}"
	@echo "Service name: ${TF_VAR_service_name}"
	@echo "Service owner: ${TF_VAR_service_owner}"
	@echo "Docker registry: ${DOCKER_REGISTRY}"
	@echo "Docker image name: ${DOCKER_IMAGE_NAME}"

#
# Development environment management
#

.PHONY: clean

clean:
	rm -f .nextflow.log.*
	rm -f .tf.out

#
# Docker image
#

export DOCKER_IMAGE_NAME=${TF_VAR_service_owner}/${TF_VAR_docker_repository}:latest

.PHONY: login build push

login:
	aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${DOCKER_REGISTRY}

build:
	docker buildx build --platform linux/amd64,linux/arm64 -t ${DOCKER_IMAGE_NAME} .
	docker tag ${DOCKER_IMAGE_NAME} ${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}

push: build
	docker push ${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}

#
# Nextflow pipeline
#

run:
	nextflow run main.nf \
		-ansi-log false \
		-bucket-dir s3://${TF_VAR_service_owner}-${TF_VAR_service_name}-scratch/ \
		-with-docker ${DOCKER_REGISTRY}/${DOCKER_IMAGE_NAME}

#
# Terraform infrastructure
#

.PHONY: init plan apply

init:
	terraform init

plan:
	terraform plan -out=.tf.out

apply:
	terraform apply .tf.out
	rm -f .tf.out