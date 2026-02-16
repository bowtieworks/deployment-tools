# Okta SSO

Steps to configure user authentication on Bowtie with Okta SSO

## Configure the App Integration in Okta


1. Visit the Okta Admin Console
2. Select `Applications` > `Applications`
3. Select `Create App Integration`
4. Select `OIDC - OpenID Connect` as the sign-in method
5. Select `Web Application` as the application type
6. Click `Next`

### General Settings

7. Assign an app integration name (e.g. `Bowtie`)
8. Leave `Proof of possession` **unchecked** — Demonstrating Proof of Possession (DPoP) is not required
9. Under `Grant type`, ensure only **Authorization Code** is selected (this should be the default)

### Sign-in redirect URIs

10. Remove the default `http://localhost:8080/authorization-code/callback`
11. Add `https://<Bowtie_Controller_Hostname>/dex/callback`, replacing `<Bowtie_Controller_Hostname>` with your controller's hostname

### Sign-out redirect URIs

12. Remove the default `http://localhost:8080`
13. This field can be left empty

### Trusted Origins

14. Leave the `Base URIs` field empty — trusted origins are not required for this integration

### Assignments

15. Under `Assignments`, select the appropriate controlled access option for your organization:
    - **Allow everyone in your organization** — all Okta users can authenticate
    - **Limit access to selected groups** — restrict access to specific Okta groups
    - **Skip group assignment for now** — assign users or groups after creation

### Save and Collect Values

16. Click `Save`
17. Copy the `Client ID` and paste it over `{{ CLIENT_ID }}` in the template below
18. Copy the `Client Secret` and paste it over `{{ CLIENT_SECRET }}` in the template below
19. Copy your Okta domain (e.g. `https://yourorg.okta.com`) and paste it over `{{ OKTA_DOMAIN }}` in the template below

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
  insecureSkipEmailVerified: true
  scopes:
    - openid
    - profile
    - email
```

## Notes
- The `issuer` value should be your Okta domain (e.g. `https://yourorg.okta.com`). If you are using a custom authorization server, the issuer will be `https://yourorg.okta.com/oauth2/<authorization_server_id>`
- **Do not include a trailing slash** in the `issuer` URL. Dex performs a strict comparison between the configured issuer and the value returned by Okta's OIDC discovery endpoint. A trailing slash (e.g. `https://yourorg.okta.com/`) will cause Dex to fail with an issuer mismatch error.
- The `insecureSkipEmailVerified` attribute is required because Okta does not always include the `email_verified` claim in its ID tokens, and Dex expects it by default.
