# `nextflow-aws-batch-hello-world`

`nextflow-aws-batch-hello-world` provides a complete Terraform template to stand up a target AWS Batch environment for running Nextflow pipelines. It also includes "[your first Nextflow script](https://www.nextflow.io/docs/latest/your-first-script.html)" so you can watch a basic Nextflow piepline use the new Batch environment.

## Prerequisites

- An AWS cloud account
- [Docker](https://docs.docker.com/desktop/)
- [Nextflow](https://www.nextflow.io/docs/latest/install.html)
- [Terraform](https://developer.hashicorp.com/terraform/install)

## Usage

1. Set up the AWS infrastructure: `make init; make plan; make apply`
2. Build and deploy the Nextflow Docker image for the Batch containers: `make login; make build; make push`
3. Run the pipeline: `make run`
