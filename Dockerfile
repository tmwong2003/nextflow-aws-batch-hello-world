FROM public.ecr.aws/amazonlinux/amazonlinux:latest

RUN yum update -y && \
    yum install awscli -y

WORKDIR /app

CMD ["aws", "--version"]

