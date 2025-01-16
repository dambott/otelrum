# Before you begin:
#
# Modify the CLUSTER variable (below) to match the otel collector value 'clusterName' in ./override-otel.yaml
# Set the env var CORALOGIX_API_KEY to your Coralogix ingestion key
# with:
# export CORALOGIX_API_KEY="<my key value>"
#
# Set the CORALOGIX_RUM values in values.yaml to the correct key and domain for your Coralogix team
# with:
# export CORALOGIX_RUM_KEY="<my key value>"
#
# Run this script to install the collector and otel demo to include Coralogix RUM and an auto-clicker for the frontend instead of the loadgenerator
# Access the frontend of the demo via the URL displayed at the end of the script
#
export CLUSTER=onlineboutique2
export EXPOSENAME=exposecollector

echo "Installing otel collector"
kubectl create secret generic coralogix-keys --from-literal=PRIVATE_KEY=${CORALOGIX_API_KEY}
helm dependency build otel-integration
helm upgrade --install otel-coralogix-integration ./otel-integration --render-subchart-notes --set global.domain="cx498.coralogix.com" --set global.clusterName=${CLUSTER}

ready=`kubectl get daemonset coralogix-opentelemetry-agent | awk 'FNR==2{print $4}'`
until [ $ready > 0 ];
do !!;
done

# Install override
echo "Installing otel collector override"
helm upgrade --install otel-coralogix-integration ./otel-integration --values override-otel.yaml --render-subchart-notes --set global.domain="cx498.coralogix.com" --set global.clusterName=${CLUSTER}

# Wait for it to start
while [[ $(kubectl get pods -l app.kubernetes.io/name=opentelemetry-agent  -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "Waiting for otel collector to start" && sleep 2; done

# Create loadbalancer to expose the collector to the internet
echo
echo "Creating otel collector loadbalancer for frontend traces"
kubectl expose deployment my-otel-demo-otelcol  --port=8080 --target-port=4318 --name=${EXPOSENAME} --type=LoadBalancer


# Wait for loadbalancer to start
x=`kubectl get svc ${EXPOSENAME} | grep -c pending`
until [ $x == 0 ];
do 
   x=`kubectl get svc ${EXPOSENAME} | grep -c pending`;
   sleep 1;
done

# Get the exposed path and parse it
OTELEXPOSE="http://"
OTELURL=`kubectl get svc ${EXPOSENAME}  | awk 'FNR==2{print $4}'`
OTELEXPOSE+="$OTELURL"
OTELEXPOSE+=":8080/v1/traces"
echo $OTELEXPOSE

# fixup backslashes in expose path
rhs=$(printf $OTELEXPOSE "$rhs" | sed 's:[\\/&]:\\&:g; $!s/$/\\/')
# Replace the line after the one that has PUBLIC_OTEL... in it, with the exposed path. This sets the frontend PUBLIC path correctly.
# naive version that does not fix backslashes
#sed -i '/PUBLIC_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT/{n;s/.*/        value: '$OTELEXPOSE'/}' values.yaml
#echo $rhs
#sed -i '/PUBLIC_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT/{n;s/.*/        value: '$OTELEXPOSE'/}' test.test
sed -i '/PUBLIC_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT/{n;s/.*/        value: '$rhs'/}' values.yaml

# Create RUM secret key - NB: this will be visible in the browser so it is not really secret
kubectl create secret generic coralogix-rum-key --from-literal=RUM_KEY=${CORALOGIX_RUM_KEY}

echo
echo "Install otel demo"
# install otel demo
helm install my-otel-demo . \
    --set opentelemetry-collector.enabled=false \
    --set jaeger.enabled=false \
    --set prometheus.enabled=false \
    --set grafana.enabled=false 

# wait for the frontend proxy to be ready
while [[ $(kubectl get pods -l app.kubernetes.io/name=my-otel-demo-frontendproxy -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "Waiting for otel demo to start (up to 5m)" && sleep 2; done

# Open front end proxy to the outside world
echo
echo "Creating otel demo loadbalancer endpoint to access demo:"
kubectl expose  deployment my-otel-demo-frontendproxy --port=8080 --target-port=8080 --name=awsexpose --type=LoadBalancer

x=`kubectl get svc awsexpose | grep -c pending`
until [ $x == 0 ];
do 
x=`kubectl get svc awsexpose | grep -c pending`;
sleep 2;
done

# Display the external IP that has been exposed - put this in a web browser  and the demo GUI should appear !
# e.g. http://afb9b47a7542a4549848671ec71fcca3-1333605269.us-east-2.elb.amazonaws.com:8080
# Note : it’s http not https so your browser may warn you - go there anyway
# Get the exposed path and parse it
AWSEXPOSE="http://"
AWSURL=`kubectl get svc awsexpose  | awk 'FNR==2{print $4}'`
AWSEXPOSE+="$AWSURL"
AWSEXPOSE+=":8080"
echo "Endpoint to access demo:"
echo $AWSEXPOSE
