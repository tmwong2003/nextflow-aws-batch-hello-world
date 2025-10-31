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

.PHONY: login build push

login:
	aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 221723323706.dkr.ecr.us-west-2.amazonaws.com

build:
	docker buildx build --platform linux/amd64,linux/arm64 -t fantail/nf-hello-world:latest .
	docker tag fantail/nf-hello-world:latest 221723323706.dkr.ecr.us-west-2.amazonaws.com/fantail/nf-hello-world:latest

push: build
	docker push 221723323706.dkr.ecr.us-west-2.amazonaws.com/fantail/nf-hello-world:latest

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
