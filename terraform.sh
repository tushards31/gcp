#!/bin/bash

# Prompt user for input values for bucket, instance, and VPC
read -p "Enter BUCKET: " BUCKET
read -p "Enter INSTANCE: " INSTANCE
read -p "Enter VPC: " VPC

# Get the default zone from the Google Cloud project's metadata
export ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")

# Extract the region from the zone by removing the last part
export REGION=$(echo "$ZONE" | cut -d '-' -f 1-2)

# Set the project ID from the Google Cloud Shell environment variable
export PROJECT_ID=$DEVSHELL_PROJECT_ID

# List all compute instance IDs in the project and store them
instances_output=$(gcloud compute instances list --format="value(id)")

# Read instance IDs into variables
IFS=$'\n' read -r -d '' instance_id_1 instance_id_2 <<< "$instances_output"

# Export the instance IDs for later use
export INSTANCE_ID_1=$instance_id_1
export INSTANCE_ID_2=$instance_id_2

# Create necessary files and directory structure for Terraform project
touch main.tf
touch variables.tf
mkdir modules
cd modules
mkdir instances
cd instances
touch instances.tf
touch outputs.tf
touch variables.tf
cd ..
mkdir storage
cd storage
touch storage.tf
touch outputs.tf
touch variables.tf
cd

# Define Terraform variables for the project
cat > variables.tf <<EOF_END
variable "region" {
 default = "$REGION"
}

variable "zone" {
 default = "$ZONE"
}

variable "project_id" {
 default = "$PROJECT_ID"
}
EOF_END

# Define main Terraform configuration
cat > main.tf <<EOF_END
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.53.0"
    }
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  zone        = var.zone
}

module "instances" {
  source     = "./modules/instances"
}
EOF_END

# Initialize Terraform
terraform init

# Create Terraform configuration for instances module
cat > modules/instances/instances.tf <<EOF_END
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "n1-standard-1"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
 network = "default"
  }
  metadata_startup_script = <<-EOT
        #!/bin/bash
    EOT
  allow_stopping_for_update = true
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "n1-standard-1"
  zone         =  "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
	  network = "default"
  }
  metadata_startup_script = <<-EOT
        #!/bin/bash
    EOT
  allow_stopping_for_update = true
}
EOF_END

# Import existing instances into Terraform state
terraform import module.instances.google_compute_instance.tf-instance-1 $INSTANCE_ID_1
terraform import module.instances.google_compute_instance.tf-instance-2 $INSTANCE_ID_2

# Plan and apply changes to the infrastructure
terraform plan
terraform apply -auto-approve

# Add configuration for a Google Cloud Storage bucket
cat > modules/storage/storage.tf <<EOF_END
resource "google_storage_bucket" "storage-bucket" {
  name          = "$BUCKET"
  location      = "us"
  force_destroy = true
  uniform_bucket_level_access = true
}
EOF_END

# Update the main configuration to include the storage module
cat >> main.tf <<EOF_END
module "storage" {
  source     = "./modules/storage"
}
EOF_END

# Reinitialize Terraform and apply the new configuration
terraform init
terraform apply -auto-approve

# Enable remote state storage using the created bucket
cat > main.tf <<EOF_END
terraform {
	backend "gcs" {
		bucket = "$BUCKET"
		prefix = "terraform/state"
	}
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.53.0"
    }
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  zone        = var.zone
}

module "instances" {
  source     = "./modules/instances"
}

module "storage" {
  source     = "./modules/storage"
}
EOF_END

# Reinitialize Terraform with the new backend
terraform init

# Update instance configurations for scaling and customization
cat > modules/instances/instances.tf <<EOF_END
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
 network = "default"
  }
  metadata_startup_script = <<-EOT
        #!/bin/bash
    EOT
  allow_stopping_for_update = true
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         =  "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
	  network = "default"
  }
  metadata_startup_script = <<-EOT
        #!/bin/bash
    EOT
  allow_stopping_for_update = true
}

resource "google_compute_instance" "$INSTANCE" {
  name         = "$INSTANCE"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
 network = "default"
  }
  metadata_startup_script = <<-EOT
        #!/bin/bash
    EOT
  allow_stopping_for_update = true
}
EOF_END

# Reinitialize and apply updated configurations
terraform init
terraform apply -auto-approve

# Force a recreation of the specified instance
terraform taint module.instances.google_compute_instance.$INSTANCE
terraform init
terraform plan
terraform apply -auto-approve

# Add VPC and subnet configurations
cat >> main.tf <<EOF_END
module "vpc" {
    source  = "terraform-google-modules/network/google"
    version = "~> 6.0.0"

    project_id   = "$PROJECT_ID"
    network_name = "$VPC"
    routing_mode = "GLOBAL"

    subnets = [
        {
            subnet_name           = "subnet-01"
            subnet_ip             = "10.10.10.0/24"
            subnet_region         = "$REGION"
        },
        {
            subnet_name           = "subnet-02"
            subnet_ip             = "10.10.20.0/24"
            subnet_region         = "$REGION"
            subnet_private_access = "true"
            subnet_flow_logs      = "true"
            description           = "Hola"
        },
    ]
}
EOF_END

# Reinitialize and apply updated configurations for VPC
terraform init
terraform plan
terraform apply -auto-approve

# Update instance networking configurations to use VPC subnets
cat > modules/instances/instances.tf <<EOF_END
resource "google_compute_instance" "tf-instance-1" {
  name         = "tf-instance-1"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
	  network = "$VPC"
    subnetwork = "subnet-01"
  }
  metadata_startup_script = <<-EOT
        #!/bin/bash
    EOT
  allow_stopping_for_update = true
}

resource "google_compute_instance" "tf-instance-2" {
  name         = "tf-instance-2"
  machine_type = "e2-standard-2"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
	  network = "$VPC"
    subnetwork = "subnet-02"
  }
  metadata_startup_script = <<-EOT
        #!/bin/bash
    EOT
  allow_stopping_for_update = true
}
EOF_END

# Apply the changes for updated instances
terraform init
terraform plan
terraform apply -auto-approve

# Add a firewall rule for allowing HTTP traffic
cat >> main.tf <<EOF_END
resource "google_compute_firewall" "tf-firewall"{
  name    = "tf-firewall"
	network = "projects/$PROJECT_ID/global/networks/$VPC"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_tags = ["web"]
  source_ranges = ["0.0.0.0/0"]
}
EOF_END

# Reinitialize and apply the firewall configuration
terraform init
terraform plan
terraform apply -auto-approve
