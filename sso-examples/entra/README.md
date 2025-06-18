# Entra SSO

Steps to configure user authentication on Bowtie with Microsoft Entra SSO

## Configure the App Registration in Entra


1. Visit Entra Admin Center or Microsoft Entra ID in Azure
2. Select `App registrations`
3. Select `New registration`
4. Assign a name
5. Set the Redirect URI to type `Web` and supply the callback url: `https://<Bowtie_Controller_Hostname>/dex/callback`
6. Copy the `Application ID`and paste it over `{{ CLIENT_ID }}` in the template below 
7. Copy the `Directory ID` and paste it over `{{ TENANT_ID }}` in the template below 
8. Visit `Certificate & secrets`
9. Select `New client secret`
10. Assign a name
11. Copy the `Value` and paste it over `{{ CLIENT_SECRET }}` in the template below 

## Upload SSO Configuration file to Bowtie

Save the below template (with your replaced variables) as a new `.yaml` file (ie `sso.yaml`)

- If your Bowtie cluster is already deployed, visit `Settings` in Controller dashboard in order to upload the sso configuration file
- If your Bowtie cluster is not yet deployed, you will be presented with an option to upload your sso configuration file during the setup process

## Yaml Template

```yaml
type: oidc
id: entra
name: Microsoft Entra ID
config:
  clientID: {{ CLIENT_ID }}
  clientSecret: {{ CLIENT_SECRET }}
  redirectURI: $DEX_ORIGIN/dex/callback
  issuer: https://login.microsoftonline.com/{{ TENANT_ID }}/v2.0
  scopes:
    - openid
    - profile
    - email
  insecureSkipEmailVerified: true
```

## Notes
- the `insecureSkipEmailVerified` attribute is required because Dex defaults to this claim (`EmailVerified`), however Entra does not support it
