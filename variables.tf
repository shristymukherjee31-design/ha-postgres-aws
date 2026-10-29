variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "ha-pg"
}

variable "my_ip" {
  type        = string
  description = "49.43.160.113/32"
}

variable "key_name" {
  type    = string
  default = "ha-pg-key"
}
