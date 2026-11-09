mock_provider "aws" {}
run "existing_dev_infrastructure" {
  command = plan
}
