# Create zip for plugin.
It must include the sink + the transform class.
```
wget https://github.com/lensesio/kafka-connect-smt/releases/download/v1.4.0/kafka-connect-smt-v1.4.0.jar
wget https://github.com/lensesio/stream-reactor/releases/download/8.1.33/kafka-connect-aws-s3-8.1.33.zip

unzip kafka-connect-aws-s3-8.1.33.zip
cd extract
jar xf ../kafka-connect-aws-s3-8.1.33/kafka-connect-aws-s3-assembly-8.1.33.jar
jar xf ../kafka-connect-smt-v1.4.0.jar
jar cf ../kafka-connect-combined-8.1.33.jar *
cd ../
zip kafka-connect-combined-8.1.33.zip kafka-connect-combined-8.1.33.jar
```

## See
https://github.com/lensesio/stream-reactor/releases
https://docs.lenses.io/latest/connectors/kafka-connectors/sinks/aws-s3
https://aws.amazon.com/blogs/big-data/back-up-and-restore-kafka-topic-data-using-amazon-msk-connect/




### OLD
https://medium.com/@ericjalal/aws-msk-cluster-backup-with-confluent-s3-sink-plugin-89634b042c61


https://aws.amazon.com/blogs/big-data/externalize-amazon-msk-connect-configurations-with-terraform/
https://docs.aws.amazon.com/msk/latest/developerguide/mkc-S3sink-connector-example.html
https://aws.amazon.com/blogs/big-data/back-up-and-restore-kafka-topic-data-using-amazon-msk-connect/
https://docs.confluent.io/kafka-connectors/s3-sink/current/overview.html