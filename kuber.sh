#!/bin/bash

# export REPO=
# export DCKR_IMG=
# export TAG=
# export ZONE=

#----------------------------------------------------start--------------------------------------------------#

# Prompt the user to input repository name, Docker image, tag, and zone
read -p "Enter REPO: " REPO
read -p "Enter DOCKER IMAGE: " DCKR_IMG
read -p "Enter TAG: " TAG
read -p "Enter ZONE: " ZONE

# Extract the region from the zone (e.g., us-central1 from us-central1-a)
export REGION="${ZONE%-*}"

# List currently authenticated Google Cloud accounts
gcloud auth list

# Run a setup script for marking provided by the training resources
gsutil cat gs://cloud-training/gsp318/marking/setup_marking_v2.sh | bash

# Clone the source code repository for the application
gcloud source repos clone valkyrie-app
cd valkyrie-app

# Create a Dockerfile for the application
cat > Dockerfile <<EOF
FROM golang:1.10
WORKDIR /go/src/app
COPY source .
RUN go install -v
ENTRYPOINT ["app","-single=true","-port=8080"]
EOF

# Build the Docker image for the application
docker build -t $DCKR_IMG:$TAG .

# Run the first marking script
cd ..
cd marking
./step1_v2.sh

# Run the Docker container with the built image
cd ..
cd valkyrie-app
docker run -p 8080:8080 $DCKR_IMG:$TAG &

# Run the second marking script
cd ..
cd marking
./step2_v2.sh
bash ~/marking/step2_v2.sh

# Switch back to the application directory
cd ..
cd valkyrie-app

# Create an Artifact Registry repository for storing Docker images
gcloud artifacts repositories create $REPO \
    --repository-format=docker \
    --location=$REGION \
    --description="awesome lab" \
    --async 

# Configure Docker to authenticate with the Artifact Registry
gcloud auth configure-docker $REGION-docker.pkg.dev --quiet

# Pause to ensure the repository is created
sleep 30

# Retrieve the ID of the most recently built Docker image
Image_ID=$(docker images --format='{{.ID}}')

# Tag the Docker image with the Artifact Registry repository name
docker tag $Image_ID $REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$REPO/$DCKR_IMG:$TAG

# Push the Docker image to the Artifact Registry repository
docker push $REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$REPO/$DCKR_IMG:$TAG

# Update the Kubernetes deployment YAML file with the pushed image
sed -i s#IMAGE_HERE#$REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$REPO/$DCKR_IMG:$TAG#g k8s/deployment.yaml

# Get credentials for the Kubernetes cluster
gcloud container clusters get-credentials valkyrie-dev --zone $ZONE

# Apply the Kubernetes deployment and service configurations
kubectl create -f k8s/deployment.yaml
kubectl create -f k8s/service.yaml

#-----------------------------------------------------end----------------------------------------------------------#
