# Intuit Webhooks

There are two options to capture event notifications in Salesforce

- Direct callback into Salesforce
  - Requires a publicly accessible Apex REST endpoint that does not use OAuth authentication (e.g., exposed through a Salesforce Site).
  - Currently I am _not_ bundling the Apex RestResource in the package. Instead this is a post-install step to setup.
    - Admins of subscriber orgs likely won't want a publicly accessible Apex REST endpoint being handled by a black box.
    - I do provide documentation on setting up the Salesforce Site along with working Apex examples that can be reviewed and used by Admins of subscriber orgs.
- Proxied through a middleware tool
  - e.g. Heroku or Make.com
  - Then the middleware tool can connect to Salesforce using OAuth.

## Direct Callback Into Salesforce

The tricky part here was figuring out how to securely store the Intuit Verification Token needed verify the HMAC signature.

I decided to use a custom object with an encrypted field ([classic encryption](https://help.salesforce.com/s/articleView?id=platform.fields_about_encrypted_fields.htm&type=5))

- [Custom Settings](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_customsettings.htm) aren't an option since I'm not bundling the Apex RestResource in the package (plus it needs to visible & editable by admins in the subscriber orgs).
  - > Use protected custom settings only in managed packages. Outside of a managed package, use named credentials or encrypted custom fields to store secrets like OAuth tokens, passwords, and other confidential material.

The publicly accessible Apex REST endpoint (exposed through a Salesforce Site) runs under the context of the Site's Guest user, which by default does not have access to the custom object/fields containing the Intuit Verification Token (plus other miscellaneous configs). I saw two options to grant the Apex access to the custom object/fields:

- Custom Sharing Rule (type: _Guest user access, based on criteria_) - ❌ **NOT** recommended
  - I tested this and it does work, but does not seem safe.
  - [Guest User Technical Details](https://help.salesforce.com/s/articleView?id=ind.v_admin_guest_user_technical_details_27809.htm&type=5)
    - > Configuring sharing rules for a guest user grants record-read access to the entire external Web. If a user bypasses your site’s UI and can make requests against your org, your guest user sharing allows them to view records.
- Use `without sharing` on the Apex class - ✅ recommended
  - ⚠️ This does mean you will have a _publicly accessible_ Apex REST endpoint (no OAuth authentication) and _executes in system context_. So caution should be taken.

## Proxied Through Middleware Tool

⚠️ TODO: Not yet explored, but may be preferred by some subscriber orgs given the limited secure storage & access options for the Intuit Verification Token.
