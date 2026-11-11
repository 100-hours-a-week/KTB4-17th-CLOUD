terraform {
  backend "s3" {
    bucket       = "star23-tfstate-975779326240"
    key          = "dev/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
