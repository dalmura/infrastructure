# Provision IAM Credential Vending for dal-indigo-core-1

This guide covers the setup of AWS IAM Credential vending for CNPG DB Backup IAM Credentials.

Each application that runs a DB and needs to upload its DB backups into S3 requires an IAM User and a scoped IAM Role for the specific S3 path they need to upload to.

We assume you've followed the steps at:
* [`dal-indigo-core-1` Apps - Wave 3](INDIGO-CORE-1-APPS-WAVE-3.md) and have Vault running

## Obtain AWS Credentials
You can get the required AWS Credentials & IAM Policy from the `dalmura/network` repo, the README.md contains the instructions how to get them.

## Vault Configuration
Ensure the `vault` CLI tool is installed locally.

Authenticate to vault:
```bash
export VAULT_ADDR=https://vault.indigo.dalmura.cloud
vault login -method=token

# Enter your root token from above
```

Create the AWS Secrets Engine:
```bash
vault secrets enable aws

vault write aws/config/root \
    access_key='<iam_vendor_key.id>' \
    secret_key='<iam_vendor_key.secret>' \
    region=us-east-1 \
    username_template='{{ printf "dal-indigo-vault-%s-%s-%s" (printf "%s" (.DisplayName) | truncate 42) (unix_time) (random 20) | truncate 64 }}'
```

## Example Usage

This setup asumes we have a new application that needs a vended DB Backup IAM User.

The IAM Policy has resource/condition key templates that asserts that the S3 path used must be: `${site}/${app-name}/${role}/`

For example this could be `indigo/example-app/postgres/` from the below example. So ensure any configuration in the app itself for S3 path matches this configuration.


Create the Vault AWS Role (aka IAM User Template):
```bash
vault write aws/roles/example-app-db-backup \
    credential_type=iam_user \
    policy_arns=<iam_vended_permissions.id> \
    iam_tags="domain=dalmura" \
    iam_tags="site=indigo" \
    iam_tags="app=example-app" \
    iam_tags="role=postgres"
```

Test this to generate a temporary user with above attached IAM Policy:
```bash
vault get aws/creds/example-app-db-backup
```

The above assumes you're running as the root token user as we've not setup any permissions to use this role yet. Let's do that now.

Create a Vault Permissions Role:
```bash
vault policy write workload-reader-example-app-db-backup -<<EOF
# App specific credentials path
path "aws/creds/example-app-db-backup" {
    capabilities = ["read"]
}
EOF

# Allow the Kubernetes Namespace & SA usage of our above policy via this 'auth role'
vault write auth/kubernetes/role/workload-reader-example-app-db-backup \
   bound_service_account_names=example-app-sa \
   bound_service_account_namespaces=example-app \
   token_policies=workload-reader-example-app-db-backup \
   audience='https://192.168.77.2:6443/' \
   ttl=24h

# WARNING: The above ttl will set the maximum lifetime of any IAM Users created
# WARNING: So ensure your ExternalSecret's refreshInterval is lower than this
```

The above assumes you already know the Namespace of your app along with the name of the Service Account created.

Once created, [External Secrets Operator](INDIGO-CORE-1-APPS-WAVE-3-EXTERNAL-SECRETS.md) will then use its permissions in Vault to vend new IAM Users and store the returned credentials in a secret.

Review the doco for this in [INDIGO-APPS-DB-MGMT.md](INDIGO-APPS-DB-MGMT.md) or review some examples in [Wave 5 Overlays](../clusters/dal-indigo-core-1/wave-5/overlays/).
