terraform {
  backend "s3" {
    bucket = "sigmoid-example-tfstate"
    key    = "aws-base-infra-tf-yaml/env/dev/terraform.tfstate"
    region = "ap-northeast-2"
  }
}