# delete secrets
kubectl delete secret coralogix-keys coralogix-rum-key
# delete RUM secret

# stop the collector
helm delete  otel-coralogix-integration

# stop the otel demo
helm delete my-otel-demo

# delete the expose services
kubectl delete svc awsexpose exposecollector