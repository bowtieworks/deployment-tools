import re
import argparse
import os
import subprocess
import getpass
import readline
import uuid

# Define templates directory and Dex connectors
TEMPLATES_DIR = "./dex_templates"
DEX_CONNECTORS = {
    "github": "github_connector.yaml",
    "gitlab": "gitlab_connector.yaml",
    "entra": "entra_connector.yaml",
    "google": "google_connector.yaml",
    "pingid": "pingid_connector.yaml",
    "oidc": "oidc_connector.yaml",
    "saml": "saml_connector.yaml",
}

def get_user_input(prompt, required=True, auto_generate=False, default=None, validator=None):
    while True:
        value = input(prompt).strip()
        if not value:
            if auto_generate:
                return str(uuid.uuid4())
            elif default:
                return default
            elif not required:
                return ""
            else:
                print("This field is required.")
                continue
        if validator and not validator(value):
            print("Invalid input. Please try again.")
        else:
            return value

def get_sensitive_user_input(prompt):
    return getpass.getpass(prompt)

def validate_uuid(value):
    try:
        uuid.UUID(value, version=4)
        return True
    except ValueError:
        return False

def remove_block(content, block_name):
    pattern = re.compile(rf'# start {block_name} block #.*?# end {block_name} block #', re.DOTALL)
    return re.sub(pattern, '', content)

def remove_empty_lines(content):
    return "\n".join(line for line in content.split("\n") if line.strip())

def remove_comments(content):
    lines = content.split('\n')
    return "\n".join(line for line in lines if not line.strip().startswith('#') or line.strip() == '#cloud-config')

def generate_init_user_credentials(email, password):
    script_path = os.path.abspath('./generate-hash.sh')
    result = subprocess.run([script_path, email, password], capture_output=True, text=True)
    return next((line for line in result.stdout.splitlines() if line.startswith(email)), None)

def format_entrypoint(entrypoint):
    entrypoint = entrypoint.strip('"')
    return f'"{entrypoint if entrypoint.startswith("https://") else f"https://{entrypoint}"}"'

def list_dex_connectors():
    print("\nChoose one of the below options:")
    for index, connector in enumerate(DEX_CONNECTORS, start=1):
        print(f"{index}. {connector.replace('_', ' ').capitalize()}")
    print(f"{len(DEX_CONNECTORS) + 1}. Create my own SSO configuration")

    choice = get_user_input(
        "Choose a Dex connector (number): ",
        validator=lambda x: x.isdigit() and 1 <= int(x) <= len(DEX_CONNECTORS) + 1
    )
    return "none" if int(choice) == len(DEX_CONNECTORS) + 1 else list(DEX_CONNECTORS.keys())[int(choice) - 1]

def load_template(connector_key):
    if connector_key == "none":
        return ""
    template_file = os.path.join(TEMPLATES_DIR, DEX_CONNECTORS[connector_key])
    if not os.path.isfile(template_file):
        print(f"Template for {connector_key} not found.")
        return None
    with open(template_file, 'r') as file:
        return file.read()

def extract_placeholders(template):
    return re.findall(r'{{\s*(\w+)\s*}}', template)

def gather_user_input_for_placeholders(placeholders):
    return {placeholder: get_sensitive_user_input(f"Enter value for {placeholder}: ") if "SECRET" in placeholder.upper()
            else get_user_input(f"Enter value for {placeholder}: ") for placeholder in placeholders}

def replace_placeholders_in_template(template, user_data):
    for key, value in user_data.items():
        template = template.replace(f"{{{{ {key} }}}}", value)
    return template

def format_template_for_cloud_init(template_content):
    lines = [line for line in template_content.split('\n') if line.strip()]
    
    formatted_lines = []
    
    # Define states for different sections of the document
    TOP_LEVEL = 'top'
    CONFIG = 'config'
    SCOPES = 'scopes'
    CLAIM_MAPPING = 'claim_mapping'
    
    current_state = TOP_LEVEL
    
    for line in lines:
        stripped = line.strip()
        
        # Determine the new state based on the line content
        if stripped.startswith('type:'):
            current_state = TOP_LEVEL
        elif stripped.startswith('config:'):
            current_state = CONFIG
        elif stripped.startswith('scopes:'):
            current_state = SCOPES
        elif stripped.startswith('claimMapping:'):
            current_state = CLAIM_MAPPING
        # If we're in the SCOPES state and encounter a line that doesn't start with '-',
        # we've left the scopes section
        elif current_state == SCOPES and not stripped.startswith('-'):
            current_state = CONFIG
        # Special check for when we leave the claim_mapping section
        elif current_state == CLAIM_MAPPING and (
            stripped.startswith('userIDKey:') or 
            stripped.startswith('userNameKey:') or
            not ':' in stripped
        ):
            current_state = CONFIG
        
        # Apply indentation based on the current state
        if current_state == TOP_LEVEL:
            formatted_lines.append(stripped)
        elif current_state == CONFIG:
            if stripped.startswith('config:'):
                formatted_lines.append(stripped)
            else:
                formatted_lines.append('  ' + stripped)
        elif current_state == SCOPES:
            if stripped.startswith('scopes:'):
                formatted_lines.append('  ' + stripped)
            else:  # List items
                formatted_lines.append('    ' + stripped)
        elif current_state == CLAIM_MAPPING:
            if stripped.startswith('claimMapping:'):
                formatted_lines.append('  ' + stripped)
            else:  # Items under claimMapping
                formatted_lines.append('    ' + stripped)
    
    return formatted_lines

def replace_sso_block_in_cloud_init(cloud_config, formatted_lines):
    sso_block = f"""- path: /etc/dex/sso.yaml
  content: |
    {formatted_lines[0]}
    {formatted_lines[1]}
    {formatted_lines[2]}
    {formatted_lines[3]}"""
    
    for i in range(4, len(formatted_lines)):
        sso_block += f"\n    {formatted_lines[i]}"
    
    cloud_lines = cloud_config.split('\n')
    
    sso_start = -1
    sso_end = -1
    
    for i, line in enumerate(cloud_lines):
        if '- path: /etc/dex/sso.yaml' in line:
            sso_start = i
            for j in range(i + 1, len(cloud_lines)):
                if cloud_lines[j].strip().startswith('- path:'):
                    sso_end = j
                    break
            break
    
    if sso_start == -1:
        return cloud_config
    
    if sso_end == -1:
        for j in range(sso_start + 1, len(cloud_lines)):
            if not cloud_lines[j].startswith(' '):
                sso_end = j
                break
        
        if sso_end == -1:
            sso_end = len(cloud_lines)
    
    result = cloud_lines[:sso_start] + sso_block.split('\n') + cloud_lines[sso_end:]
    return '\n'.join(result)

def handle_template_sso(cloud_config, connector_key, replacements):
    connector_template = load_template(connector_key)
    
    if connector_template is None:
        print(f"Failed to load template for {connector_key}")
        return cloud_config, replacements
    
    placeholders = extract_placeholders(connector_template)
    user_data = gather_user_input_for_placeholders(placeholders)
    
    filled_template = replace_placeholders_in_template(connector_template, user_data)
    
    formatted_lines = format_template_for_cloud_init(filled_template)
    
    modified_config = replace_sso_block_in_cloud_init(cloud_config, formatted_lines)
    
    if 'DEX_SSO_CONFIG' in replacements:
        del replacements['DEX_SSO_CONFIG']
    
    return modified_config, replacements

def main(args):
    with open(args.input, 'r') as file:
        cloud_config = file.read()

    replacements = {
        'CONTROLLER_HOSTNAME': get_user_input("Controller hostname: "),
        'SITE_ID': get_user_input("Site ID (leave blank to auto-generate): ", auto_generate=True, validator=validate_uuid),
        'SYNC_PSK': get_user_input("Sync PSK (leave blank to auto-generate): ", auto_generate=True),
    }

    if get_user_input("Include an SSH key? (y/n): ").lower() == 'y':
        replacements['PUBLIC_SSH_KEY'] = get_user_input("Public SSH key: ")
    else:
        cloud_config = remove_block(cloud_config, 'ssh key')

    if get_user_input("Include a placeholder for root password? (y/n): ").lower() == 'y':
        replacements['ROOT_HASHED_PASSWORD'] = '{{ ROOT_HASHED_PASSWORD }}'
    else:
        cloud_config = remove_block(cloud_config, 'root password')

    if get_user_input("Use SSO for user authentication? (y/n): ").lower() == 'y':
        connector_key = list_dex_connectors()
        
        if connector_key == "none":
            print("Entering a placeholder for manual SSO insertion.")
            replacements['DEX_SSO_CONFIG'] = "{{ DEX_SSO_CONFIG }}"
        else:
            # Use the template-based SSO handler
            cloud_config, replacements = handle_template_sso(cloud_config, connector_key, replacements)
    else:
        cloud_config = remove_block(cloud_config, 'sso')

    if get_user_input("Generate an initial admin user? (y/n): ").lower() == 'y':
        init_user_email = get_user_input("Initial user email: ")
        init_user_password = get_sensitive_user_input("Initial user password: ")
        replacements['INIT_USER_CREDENTIALS'] = generate_init_user_credentials(init_user_email, init_user_password) or ''
    else:
        cloud_config = remove_block(cloud_config, 'init-users')

    if get_user_input("Join this controller to an existing cluster? (y/n): ").lower() == 'y':
        replacements['FIRST_CONTROLLER_HOSTNAME'] = format_entrypoint(get_user_input("Existing controller hostname: "))
    else:
        cloud_config = remove_block(cloud_config, 'should-join')

    for key, value in replacements.items():
        cloud_config = cloud_config.replace(f"{{{{ {key} }}}}", value)

    cloud_config = remove_empty_lines(remove_comments(cloud_config))

    output_file = os.path.join(os.path.dirname(args.input), 'generated-cloud-init.yaml')
    with open(output_file, 'w') as file:
        file.write(cloud_config)

    print(cloud_config)
    print(f"\nProcessed cloud-config YAML has been written to {output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Dex SSO Cloud-init Generator')
    parser.add_argument('--input', required=True, help='Input cloud-init YAML file path')
    args = parser.parse_args()
    main(args)