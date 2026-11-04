# Shared legacy SGs and prod-owned cross-VPC grants remain external references.
# Do not adopt their rule collections or duplicate prod-owned ingress.
locals {
  existing_security_group_ids = {
    ssh  = "sg-0208d71a531ef25b9"
    app  = "sg-099a8e5296eb61681"
    data = "sg-0477fb590a93b0686"
  }
}
