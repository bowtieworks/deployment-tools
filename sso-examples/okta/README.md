# Okta SSO

Steps to configure user authentication on Bowtie with Okta SSO

## Configure the App Integration in Okta


1. Visit the Okta Admin Console
2. Select `Applications` > `Applications`
3. Select `Create App Integration`
4. Select `OIDC - OpenID Connect` as the sign-in method
5. Select `Web Application` as the application type
6. Assign a name
7. Set the `Sign-in redirect URIs` to `https://<Bowtie_Controller_Hostname>/dex/callback`
8. Under `Assignments`, configure access for the desired users or groups
9. Save the application
10. Copy the `Client ID` and paste it over `{{ CLIENT_ID }}` in the template below
11. Copy the `Client Secret` and paste it over `{{ CLIENT_SECRET }}` in the template below
12. Copy your Okta domain (e.g. `https://yourorg.okta.com`) and paste it over `{{ OKTA_DOMAIN }}` in the template below

## Upload SSO Configuration file to Bowtie

Save the below template (with your replaced variables) as a new `.yaml` file (ie `sso.yaml`)

- If your Bowtie cluster is already deployed, visit `Settings` in Controller dashboard in order to upload the sso configuration file
- If your Bowtie cluster is not yet deployed, you will be presented with an option to upload your sso configuration file during the setup process

## Yaml Template

```yaml
type: oidc
id: okta
name: Okta
config:
  clientID: {{ CLIENT_ID }}
  clientSecret: {{ CLIENT_SECRET }}
  redirectURI: $DEX_ORIGIN/dex/callback
  issuer: {{ OKTA_DOMAIN }}
  scopes:
    - openid
    - profile
    - email
```

## Notes
- The `issuer` value should be your Okta domain (e.g. `https://yourorg.okta.com`). If you are using a custom authorization server, the issuer will be `https://yourorg.okta.com/oauth2/<authorization_server_id>`
