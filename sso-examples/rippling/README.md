# Rippling SSO

Steps to configure user authentication on Bowtie with Rippling SSO

## Configure the App Registration in Rippling


1. Visit Rippling Dashboard
2. Select `IT` > `Third Party Access` > `Add Integration` > `Create new custom integration`
4. Fill out app registration details, can use [attached svg](/rippling/bowtie.svg) if desired for SSO logo image
5. Select `Single Sign On (SAML)` for the app type, mark `JIT Provisioning` if not pre-provisioning users via SCIM or other means
6. Complete setup wizard until `SSO setup instructions` page
7. Copy the `Single Sign-on URL or Target URL` and paste it over `{{ SSO_URL }}` in the template below
8. Copy the `Issuer or IdP Entity ID` and paste it over `{{ SSO_ISSUER }}` in the template below
9. Copy the `X509 Certificate`, save it on the local file system as `rippling-ca.crt`
10. Insert `https://{{Bowtie_Controller_Hostname}}/dex/callback` into the `Assertion Consumer Service URL` on the Rippling setup page, replacing `{{ BOWTIE_CONTROLLER_HOSTNAME }}` with your own deployed controller's hostname
11. Replace `{{ ENTITY_ISSUER }}` in the template below with a customer-specific value (ie Organization name), copy the same value into the `Service Provider Entity ID` field on the Rippling setup page
12. Save the modified sso template as a new file on the local file system as `rippling-sso.yaml`
13. At the Rippling setup page, save and continue, finishing out the remainder of the setup wizard on Rippling
14. Once the integration has completed installation, navigate to `Settings` > `SAML attributes` > `Create New` > `Global attribute`
15. Enter `email` for `Global attribute name` and select `User's email address` for the Value
16. Create a second entry (`Create New` > `Global attribute`)
17. Enter `name` for `Global attribute name` and select `User's Full name` for the value

## Upload SSO Configuration file to Bowtie

- If your Bowtie cluster is already deployed, visit `Settings` in Controller dashboard in order to upload the certificate and sso configuration file
- If your Bowtie cluster is not yet deployed, you will be presented with an option to upload your sso configuration file during the setup process

## Yaml Template

```yaml
type: saml
id: rippling
name: Rippling
config:
  ssoURL: {{ SSO_URL }}
  ca: etc/dex/rippling-ca.crt
  redirectURI: $DEX_ORIGIN/dex/callback
  usernameAttr: name
  emailAttr: urn:oid:1.2.840.113549.1.9.1.1
  entityIssuer: {{ ENTITY_ISSUER }}
  ssoIssuer: {{ SSO_ISSUER }}
  nameIDPolicyFormat: emailAddress
```
