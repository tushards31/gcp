echo "" 
echo ""

# Prompt the user to input a region
read -p "Enter ZONE: " ZONE

# Set environment variables for project ID and project number
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export REGION="${ZONE%-*}"  # Extract the region from the zone by removing the suffix

# Configure the compute region for gcloud
gcloud config set compute/region $REGION

# Enable required Google Cloud services
gcloud services enable \
container.googleapis.com \
clouddeploy.googleapis.com \
artifactregistry.googleapis.com \
cloudbuild.googleapis.com \
clouddeploy.googleapis.com

# Pause for 20 seconds to allow services to initialize
sleep 20

# Add IAM policy bindings for the service account to access required roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
--format="value(projectNumber)")-compute@developer.gserviceaccount.com \
--role="roles/clouddeploy.jobRunner"

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
--format="value(projectNumber)")-compute@developer.gserviceaccount.com \
--role="roles/container.developer"

# Create an Artifact Registry repository for storing Docker images
gcloud artifacts repositories create cicd-challenge \
--description="Image registry for tutorial web app" \
--repository-format=docker \
--location=$REGION

# Create two GKE clusters for staging and production environments
gcloud container clusters create cd-staging --node-locations=$ZONE --num-nodes=1 --async
gcloud container clusters create cd-production --node-locations=$ZONE --num-nodes=1 --async

# Clone the Cloud Deploy tutorials repository
cd ~/
git clone https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git
cd cloud-deploy-tutorials
git checkout c3cae80 --quiet  # Checkout a specific commit
cd tutorials/base

# Replace environment variables in the Skaffold YAML template
envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml
cat web/skaffold.yaml  # Display the generated Skaffold YAML

# Build Docker images using Skaffold and save artifact metadata
cd web
skaffold build --interactive=false \
--default-repo $REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/cicd-challenge \
--file-output artifacts.json
cd ..

# Update the delivery pipeline configuration
cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
sed -i "s/targetId: staging/targetId: cd-staging/" clouddeploy-config/delivery-pipeline.yaml
sed -i "s/targetId: prod/targetId: cd-production/" clouddeploy-config/delivery-pipeline.yaml
sed -i "/targetId: test/d" clouddeploy-config/delivery-pipeline.yaml

# Apply the updated delivery pipeline configuration
gcloud config set deploy/region $REGION
gcloud beta deploy apply --file=clouddeploy-config/delivery-pipeline.yaml

# Describe the delivery pipeline to confirm the configuration
gcloud beta deploy delivery-pipelines describe web-app

# Wait for the GKE clusters to be in the RUNNING state
CLUSTERS=("cd-production" "cd-staging")
for cluster in "${CLUSTERS[@]}"; do
  status=$(gcloud container clusters describe "$cluster" --format="value(status)")
  
  while [ "$status" != "RUNNING" ]; do
    echo "Waiting for $cluster to be RUNNING..."
    echo "Like Share and Subscribe to QUICKLAB [https://www.youtube.com/@quick_lab]..."
    sleep 10  # Wait before checking again
    status=$(gcloud container clusters describe "$cluster" --format="value(status)")
  done
  echo "$cluster is now RUNNING."
done

# Set up Kubernetes contexts for the clusters
CONTEXTS=("cd-staging" "cd-production")
for CONTEXT in ${CONTEXTS[@]}; do
    gcloud container clusters get-credentials ${CONTEXT} --region ${REGION}
    kubectl config rename-context gke_${PROJECT_ID}_${REGION}_${CONTEXT} ${CONTEXT}
done

# Apply Kubernetes namespace configuration for the web app
for CONTEXT in ${CONTEXTS[@]}; do
    kubectl --context ${CONTEXT} apply -f kubernetes-config/web-app-namespace.yaml
done

# Generate target configurations for staging and production
envsubst < clouddeploy-config/target-staging.yaml.template > clouddeploy-config/target-cd-staging.yaml
envsubst < clouddeploy-config/target-prod.yaml.template > clouddeploy-config/target-cd-production.yaml
sed -i "s/staging/cd-staging/" clouddeploy-config/target-cd-staging.yaml
sed -i "s/prod/cd-production/" clouddeploy-config/target-cd-production.yaml

# Apply the target configurations
gcloud beta deploy apply --file clouddeploy-config/target-cd-staging.yaml
gcloud beta deploy apply --file clouddeploy-config/target-cd-production.yaml

# Create a new release for the web app
gcloud beta deploy releases create web-app-001 \
--delivery-pipeline web-app \
--build-artifacts web/artifacts.json \
--source web/

# Monitor the rollout process
while true; do
  status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --format="value(state)" | head -n 1)
  if [ "$status" == "SUCCEEDED" ]; then
    break
  fi
  sleep 10

done

# Promote the release to production
gcloud beta deploy releases promote \
--delivery-pipeline web-app \
--release web-app-001 \
--quiet

# Wait for the rollout to reach a pending approval state
while true; do
  status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --format="value(state)" | head -n 1)
  if [ "$status" == "PENDING_APPROVAL" ]; then
    break
  fi
  sleep 10
done

# Approve the rollout for production
gcloud beta deploy rollouts approve web-app-001-to-cd-production-0001 \
--delivery-pipeline web-app \
--release web-app-001 \
--quiet

# Wait for the rollout to complete
while true; do
  status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --format="value(state)" | head -n 1)
  if [ "$status" == "SUCCEEDED" ]; then
    break
  fi
  sleep 10
done

# Enable the Cloud Build service
gcloud services enable cloudbuild.googleapis.com

# Clone and prepare the Cloud Deploy tutorials repository
cd ~/
git clone https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git
cd cloud-deploy-tutorials
git checkout c3cae80 --quiet
cd tutorials/base

envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml
cat web/skaffold.yaml

# Build Docker images using Skaffold
cd web
skaffold build --interactive=false \
--default-repo $REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/cicd-challenge \
--file-output artifacts.json
cd ..

# Create another release for the web app
gcloud beta deploy releases create web-app-002 \
--delivery-pipeline web-app \
--build-artifacts web/artifacts.json \
--source web/

# Monitor the rollout process for the new release
while true; do
  status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-002 --format="value(state)" | head -n 1)
  if [ "$status" == "SUCCEEDED" ]; then
    break
  fi
  sleep 10
done

# Roll back the staging environment if needed
gcloud deploy targets rollback cd-staging \
   --delivery-pipeline=web-app \
   --quiet
