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

.PHONY: ecr-login build-image push-image

ecr-login:
	aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 221723323706.dkr.ecr.us-west-2.amazonaws.com

build-image:
	docker buildx build --platform linux/amd64,linux/arm64 -t fantail/nf-hello-world:latest .
	docker tag fantail/nf-hello-world:latest 221723323706.dkr.ecr.us-west-2.amazonaws.com/fantail/nf-hello-world:latest

push-image: build-image
	docker push 221723323706.dkr.ecr.us-west-2.amazonaws.com/fantail/nf-hello-world:latest

#
# Terraform infrastructure
#

.PHONY: tf-init tf-plan tf-apply

tf-init:
	terraform init

tf-plan:
	terraform plan -out=.tf.out

tf-apply:
	terraform apply .tf.out
