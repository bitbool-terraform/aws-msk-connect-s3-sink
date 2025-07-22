variable "name" {}
variable "create_sink" { default = true }
variable "create_restore_connector" { default = false }
variable "sink_version" {}
variable "kafka_version" {}
variable "region" { default = null }
#variable "topics" {}
variable "topics_dir" { default = "topics"}

variable "kafka_brokers" {}
variable "vpc_id" {}
variable "vpc_subnets" {}

variable "tags" { default = {} }

variable "restore_bucket_name" { default = null }