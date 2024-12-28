clear

#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

# Array of color codes excluding black and white
TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)

# Pick random colors
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

#----------------------------------------------------start--------------------------------------------------#

# Step 0: Assigning variables
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")
export CLUSTER=hello-cluster
export REPO=my-repository

# Step 1: Navigate to the sample-app directory
cd sample-app

# Step 2: Build and push Docker image using Cloud Build
COMMIT_ID="$(git rev-parse --short=7 HEAD)"
gcloud builds submit --tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/$REPO/hello-cloudbuild:${COMMIT_ID}" .

EXPORTED_IMAGE="$(gcloud builds submit --tag="${REGION}-docker.pkg.dev/${PROJECT_ID}/$REPO/hello-cloudbuild:${COMMIT_ID}" . | grep IMAGES | awk '{print $2}')"

# Step 3: Switch to the 'dev' branch and update Cloud Build configuration
git checkout dev

sed -i "9c\    args: ['build', '-t', '$REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild-dev:v1.0', '.']" cloudbuild-dev.yaml

sed -i "13c\    args: ['push', '$REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild-dev:v1.0']" cloudbuild-dev.yaml

sed -i "17s|        image: <todo>|        image: $REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild-dev:v1.0|" dev/deployment.yaml

git add .
git commit -m "Awesome Lab" 
git push -u origin dev

sleep 120

# Step 4: Switch to the 'master' branch and expose development deployment
git checkout master

kubectl expose deployment development-deployment -n dev --name=dev-deployment-service --type=LoadBalancer --port 8080 --target-port 8080

sed -i "11c\    args: ['build', '-t', '$REGION-docker.pkg.dev/\$PROJECT_ID/my-repository/hello-cloudbuild:v1.0', '.']" cloudbuild.yaml

sed -i "16c\    args: ['push', '$REGION-docker.pkg.dev/\$PROJECT_ID/my-repository/hello-cloudbuild:v1.0']" cloudbuild.yaml

sed -i "17c\        image:  $REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:v1.0" prod/deployment.yaml

git add .
git commit -m "Awesome Lab" 
git push -u origin master

sleep 80

# Step 5: Expose the production deployment
kubectl expose deployment production-deployment -n prod --name=prod-deployment-service --type=LoadBalancer --port 8080 --target-port 8080

# Step 6: Modify the dev branch for version 2.0 updates
git checkout dev

sed -i '28a\	http.HandleFunc("/red", redHandler)' main.go

sed -i '32a\
func redHandler(w http.ResponseWriter, r *http.Request) { \
	img := image.NewRGBA(image.Rect(0, 0, 100, 100)) \
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src) \
	w.Header().Set("Content-Type", "image/png") \
	png.Encode(w, img) \
}' main.go

sed -i "9c\    args: ['build', '-t', '$REGION-docker.pkg.dev/\$PROJECT_ID/my-repository/hello-cloudbuild-dev:v2.0', '.']" cloudbuild-dev.yaml

sed -i "13c\    args: ['push', '$REGION-docker.pkg.dev/\$PROJECT_ID/my-repository/hello-cloudbuild-dev:v2.0']" cloudbuild-dev.yaml

sed -i "17c\        image: $REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:v2.0" dev/deployment.yaml

git add .
git commit -m "Awesome Lab" 
git push -u origin dev

sleep 10

# Step 7: Modify the master branch for version 2.0 updates
git checkout master

sed -i '28a\	http.HandleFunc("/red", redHandler)' main.go

sed -i '32a\
func redHandler(w http.ResponseWriter, r *http.Request) { \
	img := image.NewRGBA(image.Rect(0, 0, 100, 100)) \
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src) \
	w.Header().Set("Content-Type", "image/png") \
	png.Encode(w, img) \
}' main.go


sed -i "11c\    args: ['build', '-t', '$REGION-docker.pkg.dev/\$PROJECT_ID/my-repository/hello-cloudbuild:v2.0', '.']" cloudbuild.yaml

sed -i "16c\    args: ['push', '$REGION-docker.pkg.dev/\$PROJECT_ID/my-repository/hello-cloudbuild:v2.0']" cloudbuild.yaml

sed -i "17c\        image: $REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:v2.0" prod/deployment.yaml

git add .
git commit -m "Awesome Lab" 
git push -u origin master

sleep 70

# Step 8: Rollback deployment and validate
kubectl -n prod rollout undo deployment/production-deployment

kubectl -n prod get pods -o jsonpath --template='{range .items[*]}{.metadata.name}{"\t"}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

cd

echo

echo -e "\n"  # Adding one blank line

cd

remove_files() {
    # Loop through all files in the current directory
    for file in *; do
        # Check if the file name starts with "gsp", "arc", or "shell"
        if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
            # Check if it's a regular file (not a directory)
            if [[ -f "$file" ]]; then
                # Remove the file and echo the file name
                rm "$file"
                echo "File removed: $file"
            fi
        fi
    done
}

remove_files
