/**
 * Persistent resources shared by infrastructure versions
 */
module "storage" {
  source = "./storage"
}

module "cdn" {
  source      = "./cdn"
  name_prefix = "star23"
}
