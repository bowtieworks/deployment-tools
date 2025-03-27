# cloud-init-generator



## Getting started

This tool aims at making the process of constructing a well-formed cloud-init file simple and error free. This is achieved by starting with a template that includes the common options that new deployments will typically need, and then asking for the remaining inputs from the user in the console.    

## Requirements

- Python 3.6 or higher
- `pip` python package manager
- `argon2`

## Setup and Usage

- Clone repository
- Ensure included shell script is executable: `chmod +x generate-hash.sh`
- Run the script: `python3 create-cloud-init.py --input cloud-init-template.yaml`

## Inputs

The script will prompt for the following information:

### Required Inputs
- **Controller hostname** - The publicly accessible FQDN to be assigned to the controller

### Optional Inputs (can be auto-generated)
- **Site ID** - UUIDv4 that will be assigned to the networking site created with the controller
  - *Recommendation:* Leave blank to auto-generate
- **Sync PSK** - Private syncing key used when standing up additional sites and peers
  - *Recommendation:* Leave blank to auto-generate

### Configuration Options
- **Include an SSH key?** (y/n) 
  - If "y": Provide the public SSH key to be added to the authorized_keys list
- **Include a placeholder for root password?** (y/n)
  - If "y": A placeholder will be inserted for a hashed_password for the root user
  - *Recommendation:* Leave blank unless explicitly necessary
- **Use SSO for user authentication?** (y/n)
  - If "y": Select from the available SSO connectors by entering the associated number
  - Connector list available in [dex_templates](/tools/cloud-init-generator/dex_templates/)
- **Generate an initial admin user?** (y/n)
  - If "y": Create an initial admin user with your provided email and password
  - *Recommendation:* Create unless joining an existing Bowtie cluster
- **Join this controller to an existing cluster?** (y/n)
  - If "y": Provide the publicly accessible FQDN of a pre-existing Bowtie controller
  - Note: The Sync PSK must match the key of the pre-existing deployment

This will generate a new cloud-init file in the same directory, as well as pass the new file contents to stdout.

## Metadata.yaml

A [metadata.yaml](/tools/cloud-init-generator/metadata.yaml) file is also provided as a template for use when configuring static networking. 

## Misc
Reach out to support@bowtie.works if you have any questions or need any assistance.

