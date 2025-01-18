clear

#!/bin/bash

BOLD=`tput bold`
RESET=`tput sgr0`

# Array of color codes excluding black and white
TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)

# Pick random colors
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

#----------------------------------------------------start--------------------------------------------------#

# Step 1: Assigning variables
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")
export CLUSTER=hello-cluster
export REPO=my-repository

# Step 2: Enable required GCP services
gcloud services enable container.googleapis.com \
    cloudbuild.googleapis.com \
    sourcerepo.googleapis.com

# Step 3: Create Artifact Repository
gcloud artifacts repositories create $REPO \
    --repository-format=docker \
    --location=$REGION \
    --description="Awesome Lab"

sleep 20

# Step 4: Assign IAM roles to Cloud Build service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
--member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
--format="value(projectNumber)")@cloudbuild.gserviceaccount.com --role="roles/container.developer"

# Step 5: Install GitHub CLI and configure Git
curl -sS https://webi.sh/gh | sh
gh auth login
gh api user -q ".login"
GITHUB_USERNAME=$(gh api user -q ".login")
git config --global user.name "${GITHUB_USERNAME}"
git config --global user.email "${USER_EMAIL}"

# Step 6: Create Kubernetes cluster
gcloud beta container --project "$PROJECT_ID" clusters create "$CLUSTER" --zone "$ZONE" --no-enable-basic-auth --cluster-version latest --release-channel "regular" --machine-type "e2-medium" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "100" --metadata disable-legacy-endpoints=true  --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/$PROJECT_ID/global/networks/default" --subnetwork "projects/$PROJECT_ID/regions/$REGION/subnetworks/default" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --enable-autoscaling --min-nodes "2" --max-nodes "6" --location-policy "BALANCED" --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --enable-shielded-nodes --node-locations "$ZONE"

# Step 7: Configure Kubernetes
gcloud container clusters get-credentials hello-cluster --zone=$ZONE
kubectl create namespace prod
kubectl create namespace dev

# Step 8: Clone and Configure GitHub Repository
gh repo create sample-app --private
git clone https://github.com/${GITHUB_USERNAME}/sample-app.git
cd ~
gsutil cp -r gs://spls/gsp330/sample-app/* sample-app
for file in sample-app/cloudbuild-dev.yaml sample-app/cloudbuild.yaml; do
    sed -i "s/<your-region>/${REGION}/g" "$file"
    sed -i "s/<your-zone>/${ZONE}/g" "$file"
done

git init
cd sample-app/
git checkout -b master
git add .
git commit -m "Awesome Lab" 
git push -u origin master

git add .
git commit -m "Initial commit with sample code"
git push origin master
git checkout -b dev
git commit -m "Initial commit for dev branch"
git push origin dev

# Step 9: Output Cloud Build Trigger Link
echo "${BOLD}Visit this link to configure triggers: ${RESET}" "https://console.cloud.google.com/cloud-build/triggers;region=global/add?project=$PROJECT_ID"

# Production trigger info
echo -e "${BOLD}Production Deployment Trigger:${RESET}"
echo -e "${BOLD}Property Value Name:${RESET} sample-app-prod-deploy"
echo -e "${BOLD}Branch Pattern:${RESET} ^master$"
echo -e "${BOLD}Build Configuration File:${RESET} cloudbuild.yaml"
echo ""

# Development trigger info
echo -e "${BOLD}Development Deployment Trigger:${RESET}"
echo -e "${BOLD}Property Value Name:${RESET} sample-app-dev-deploy"
echo -e "${BOLD}Branch Pattern:${RESET} ^dev$"
echo -e "${BOLD}Build Configuration File:${RESET} cloudbuild-dev.yaml"
echo ""
