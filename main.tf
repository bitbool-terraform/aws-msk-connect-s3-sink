data "aws_region" "current" {}


locals {
  create_connector = var.create_sink || var.create_restore_connector
}

module "s3_sink_bucket" {
  count = var.create_sink ? 1 : 0

  source = "terraform-aws-modules/s3-bucket/aws"
  version = "4.11.0"

  bucket = format("%s-kafka-sink-data",var.name)

  force_destroy       = true

  tags = merge( {Name = format("%s-kafka-sink-data",var.name), TFModule = "aws-msk-connect-s3-sink", AwsService = "s3"}, var.tags )


  attach_policy           = false

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  acl = "private" # "acl" conflicts with "grant" and "owner"

  versioning = {
    status     = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "AES256"
      }
    }
  }

}


module "plugin_s3_bucket" {
  count = local.create_connector ? 1 : 0

  source = "terraform-aws-modules/s3-bucket/aws"
  version = "4.11.0"

  bucket = format("msk-connect-plugins-%s",var.name)

  force_destroy       = true

  tags = merge( {Name = format("msk-connect-plugins-%s",var.name), TFModule = "aws-msk-connect-s3-sink", AwsService = "s3"}, var.tags )


  attach_policy           = false

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  acl = "private" # "acl" conflicts with "grant" and "owner"

  versioning = {
    status     = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "AES256"
      }
    }
  }

}


resource "aws_s3_object" "connector_s3_zip" {
  count = local.create_connector ? 1 : 0

  bucket = module.plugin_s3_bucket[0].s3_bucket_id
  key    = format("lensesio/%s/kafka-connect-aws-s3-%s.zip",var.sink_version,var.sink_version)
  source = format("%s/connector/kafka-connect-aws-s3-%s.zip",path.module,var.sink_version)
  #etag   = filemd5(format("%s/connector/lensesio-kafka-connect-aws-s3-%s.zip",path.module,var.sink_version))
  content_type = "application/zip"
}

resource "aws_mskconnect_custom_plugin" "plugin_s3_zip" {
  count = local.create_connector ? 1 : 0

  name         = format("lenses-s3-sink-%s-%s",var.name,replace(var.sink_version,".","-"))
  content_type = "ZIP"
  location {
    s3 {
      bucket_arn = module.plugin_s3_bucket[0].s3_bucket_arn
      file_key   = aws_s3_object.connector_s3_zip[0].key
    }
  }
  description = format("Lenses S3 Sink Source Connector %s %s",var.name,var.sink_version)
}


resource "aws_mskconnect_connector" "s3_sink" {
  count = var.create_sink ? 1 : 0

  name = format("%s-s3-sink",var.name)

  kafkaconnect_version = var.kafka_version #"3.7.1"

  capacity {
    autoscaling {
      mcu_count        = 2
      min_worker_count = 1
      max_worker_count = 4

      scale_in_policy {
        cpu_utilization_percentage = 20
      }

      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class" = "io.lenses.streamreactor.connect.aws.s3.sink.S3SinkConnector"
    
    #"connect.s3.kcql"= format("INSERT INTO %s:%s SELECT * FROM `*` PARTITIONBY _topic, _header.year, _header.month, _header.day, _header.hour STOREAS `JSON`",module.s3_sink_bucket[0].s3_bucket_id,"topics")
    "connect.s3.kcql"= format("INSERT INTO %s:%s SELECT * FROM `*` STOREAS `JSON` PROPERTIES ('flush.size'=%s, 'flush.interval'=%s, 'flush.count'=%s, 'store.envelope'=true)",module.s3_sink_bucket[0].s3_bucket_id,"topics",var.flush_size,var.flush_interval,var.flush_count)
    "connect.s3.aws.region" =coalesce(var.region,data.aws_region.current.name)
    "connect.s3.skip.null.values" = true
    "topics.regex" = "^(?!.*amazon_msk).*"
    # In version 9, these properties were moved here
    # "flush.count" = 5
    # "flush.size" = 50000000 #(50MB)
    # "flush.interval" = 60 #1min
    # "partition.include.keys" = true
    "connect.s3.compression.codec" = "GZIP"
    "tasks.max" = 4
    "schema.enable" = false
    "errors.log.enable"= true
    # "value.converter"= "org.apache.kafka.connect.storage.StringConverter"
    # "key.converter" = "org.apache.kafka.connect.storage.StringConverter"
    "value.converter.schemas.enable" = false
    "key.converter.schemas.enable" = false
    "locale" = "en"
    "timezone" = "UTC" 
    # "transforms"="partition"
    # "transforms.partition.type"="io.lenses.connect.smt.header.InsertRecordTimestampHeaders"
    # "transforms.partition.year.format"="yyyy"
    # "transforms.partition.month.format"="MM"
    # "transforms.partition.day.format"="dd"
    # "transforms.partition.hour.format"="HH"

    # "transforms.insertFormattedTs.type"="io.lenses.connect.smt.header.TimestampConverter"
    # "transforms.insertFormattedTs.header.name"="ts"
    # "transforms.insertFormattedTs.field"="timestamp"
    # "transforms.insertFormattedTs.target.type"="string"
    #"transforms.insertFormattedTs.format.to.pattern"="yyyy-MM-dd-HH"

    # "connector.class" = "io.confluent.connect.s3.S3SinkConnector"
    # "s3.region" = coalesce(var.region,data.aws_region.current.name)
    # "flush.size" = "5"
    # "schema.compatibility" = "NONE"
    # "tasks.max" = "4"
    # #"topics" = var.topics
    # "topics.regex" = "^(?!.*amazon_msk).*"
    # # "output.data.format": "JSON",
    # # "compression.codec": "JSON - gzip",    
    # "format.class" = "io.confluent.connect.s3.format.json.JsonFormat"
    # "partitioner.class" = "io.confluent.connect.storage.partitioner.HourlyPartitioner"
    # # "value.converter.schemas.enable" = "false"
    # # "value.converter" = "org.apache.kafka.connect.json.JsonConverter"
    # "storage.class" = "io.confluent.connect.s3.storage.S3Storage"
    # "key.converter" = "org.apache.kafka.connect.storage.StringConverter"
    # "s3.bucket.name" = module.s3_sink_bucket[0].s3_bucket_id
    # "topics.dir" = var.topics_dir
    # "locale" = "en"
    # "timezone" = "UTC" 
    # "behavior.on.null.values" = "ignore"

  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = var.kafka_brokers

      vpc {
        security_groups = [aws_security_group.s3_connector[0].id]
        subnets         = var.vpc_subnets
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.plugin_s3_zip[0].arn
      revision = aws_mskconnect_custom_plugin.plugin_s3_zip[0].latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled = true
        log_group = aws_cloudwatch_log_group.s3_sink[0].name
      }
    }
  }
  service_execution_role_arn = aws_iam_role.s3_sink[0].arn
}



resource "aws_mskconnect_connector" s3_restore {
  count = var.create_restore_connector ? 1 : 0

  name = format("%s-s3-restore",var.name)

  kafkaconnect_version = var.kafka_version #"3.7.1"

  capacity {
    autoscaling {
      mcu_count        = 2
      min_worker_count = 1
      max_worker_count = 4

      scale_in_policy {
        cpu_utilization_percentage = 20
      }

      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class" = "io.lenses.streamreactor.connect.aws.s3.source.S3SourceConnector"
    "connect.s3.kcql"=join(";",formatlist(format("insert into %%s select * from %s:%s/%%s STOREAS `JSON` PROPERTIES ('store.envelope'=true)",var.restore_bucket_name,"topics"),var.topics_to_restore,var.topics_to_restore),[""])
    "connect.s3.aws.region" =coalesce(var.region,data.aws_region.current.name)
    "connect.s3.compression.codec" = "GZIP"
    "tasks.max" = 4
    #"topics.regex" = "^(?!.*amazon_msk).*"
    # "value.converter"= "org.apache.kafka.connect.storage.StringConverter"
    # "key.converter" = "org.apache.kafka.connect.storage.StringConverter"
    # "value.converter.schemas.enable" = false
    # "key.converter.schemas.enable" = false
    # "locale" = "en"
    # "timezone" = "UTC" 

  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = var.kafka_brokers

      vpc {
        security_groups = [aws_security_group.s3_connector[0].id]
        subnets         = var.vpc_subnets
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.plugin_s3_zip[0].arn
      revision = aws_mskconnect_custom_plugin.plugin_s3_zip[0].latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled = true
        log_group = aws_cloudwatch_log_group.s3_restore[0].name
      }
    }
  }
  service_execution_role_arn = aws_iam_role.s3_restore[0].arn
}


resource "aws_cloudwatch_log_group" "s3_sink" {
  count = var.create_sink ? 1 : 0

  name = format("kafka/connector/%s-s3-sink",var.name)

  log_group_class = "STANDARD"
  retention_in_days = 30

}

resource "aws_cloudwatch_log_group" "s3_restore" {
  count = var.create_restore_connector ? 1 : 0

  name = format("kafka/connector/%s-s3-restore",var.name)

  log_group_class = "STANDARD"
  retention_in_days = 30

}


resource "aws_iam_role" "s3_sink" {
  count = local.create_connector ? 1 : 0

  name               = format("%s-kafka-s3-sink",var.name)
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.role_assumable_by_msk.json
}

resource "aws_iam_role_policy_attachment" "s3_sink" {
  count = var.create_sink ? 1 : 0

  role       = aws_iam_role.s3_sink[0].name
  policy_arn = aws_iam_policy.s3_sink[0].arn
}


resource "aws_iam_policy" "s3_sink" {
  count = var.create_sink ? 1 : 0

  name   = format("%s-kafka-s3-sink",var.name)
  path   = "/"
  policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
         "Effect":"Allow",
         "Action":[
           "s3:ListAllMyBuckets"
         ],
         "Resource":"arn:aws:s3:::*"
        },        
        {
          "Sid": "S3DataFullAccess",
          "Action": [
            "s3:*"
          ],
          "Effect": "Allow",
          "Resource": ["${module.s3_sink_bucket[0].s3_bucket_arn}*"]
        }, 
        {
          "Sid": "S3ModuleReadAccess",
          "Action": [
            "s3:Get*",
            "s3:List*"
          ],
          "Effect": "Allow",
          "Resource": ["${module.plugin_s3_bucket[0].s3_bucket_arn}*"]
        },         
        {
          "Sid": "kafkaAccess",
          "Effect": "Allow",
          "Action": [
            "kafka-cluster:*",
            "kafkaconnect:*",
            "kafka:*"
            ],
          "Resource": [
            "*"
          ]
        }
      ]
    })

}


resource "aws_iam_role" "s3_restore" {
  count = var.create_restore_connector ? 1 : 0

  name               = format("%s-kafka-s3-restore",var.name)
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.role_assumable_by_msk.json
}

resource "aws_iam_role_policy_attachment" "s3_restore" {
  count = var.create_restore_connector ? 1 : 0

  role       = aws_iam_role.s3_restore[0].name
  policy_arn = aws_iam_policy.s3_restore[0].arn
}

resource "aws_iam_policy" "s3_restore" {
  count = var.create_restore_connector ? 1 : 0

  name   = format("%s-kafka-s3-restore",var.name)
  path   = "/"
  policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
         "Effect":"Allow",
         "Action":[
           "s3:ListAllMyBuckets"
         ],
         "Resource":"arn:aws:s3:::*"
        },        
        {
          "Sid": "S3DataReadAccess",
          "Action": [
            "s3:*"
          ],
          "Effect": "Allow",
          "Resource": ["arn:aws:s3:::${var.restore_bucket_name}*"]
        }, 
        {
          "Sid": "S3ModuleReadAccess",
          "Action": [
            "s3:Get*",
            "s3:List*"
          ],
          "Effect": "Allow",
          "Resource": ["arn:aws:s3:::${var.restore_bucket_name}*"]
        },         
        {
          "Sid": "kafkaAccess",
          "Effect": "Allow",
          "Action": [
            "kafka-cluster:*",
            "kafkaconnect:*",
            "kafka:*"
            ],
          "Resource": [
            "*"
          ]
        }
      ]
    })

}


            # "${replace(var.msk_cluster_arn,"cluster","topic")}/*",
            # "${var.msk_cluster_arn}",
            # "${replace(var.msk_cluster_arn,"cluster","group")}/*"

data "aws_iam_policy_document" "role_assumable_by_msk" {
  statement {
    effect = "Allow"
    actions = [ "sts:AssumeRole" ]
    principals {
      type        = "Service"
      identifiers = ["kafkaconnect.amazonaws.com"]
    }
  }
}


resource "aws_security_group" "s3_connector" {
  count = local.create_connector ? 1 : 0

  name     = format("%s-kafka-s3-connector",var.name)
  vpc_id   = var.vpc_id

  tags = merge({"Name" = format("%s-kafka-s3-connector",var.name)})

  egress {
      from_port       = 0
      to_port         = 0
      protocol        = -1
      cidr_blocks     = ["0.0.0.0/0"]
  }  

  ingress {
      from_port       = 0
      to_port         = 0
      protocol        = -1
      cidr_blocks     = ["0.0.0.0/0"]
  }  

  #lifecycle { ignore_changes = [ingress,egress] }

}


#aws_iam_role.s3_sink
#aws_security_group.s3_sink.

# resource "aws_mskconnect_connector" "s3_source_restore" {
#   name                = "s3-restore-source"
#   plugins { custom_plugin { arn = aws_mskconnect_custom_plugin.plugin_s3_zip.arn } }
#   service_execution_role_arn = aws_iam_role.msk_exec.arn
#   # …capacity, cluster, subnets, security groups…
#   connector_configuration = jsondecode(file("restore-config.json"))
# }

# resource "aws_iam_policy" "msk_connect_plugins_access" {
#   name   = "MSKConnectPluginsAccess"
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Effect   = "Allow",
#       Action   = ["s3:GetObject", "s3:GetObjectVersion"],
#       Resource = "${aws_s3_bucket.plugins.arn}/*"
#     }]
#   })
# }