data "aws_vpc" "existing" { id = "vpc-0c203bd23ce77e200" }
output "id" { value = data.aws_vpc.existing.id }
