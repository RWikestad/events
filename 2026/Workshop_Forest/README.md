# Workshop Forest
The folder contains assets created for workshop Forest event in November 2026.

## Workshop Forest November 2026

[Workshop Forest - Notebook](Notebook/)

[Workshop Forest - APEX application](Forest_APP/)


## Create a Database User

To set up a new database user in **Oracle Autonomous AI Database**, follow these steps.

### 1. Create the Database User

Log in to **Database Actions** as the `ADMIN` user.

1. Navigate to **Database Users**.
2. Create a new database user.
3. Enable **Oracle Machine Learning (OML)** access for the user.
4. Assign the required roles and privileges.

### 2. Grant Required Privileges

Connect to the database as `ADMIN` and execute the following SQL statements.

Replace `USERNAME` with the actual database username.

**Select AI Agent Framework**

Enables the user to create and manage AI Agents, Tasks, Tools, and Teams.

```sql
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO USERNAME;
```

**Select AI**

Enables access to Select AI functionality, including AI profiles and conversations.

```sql
GRANT EXECUTE ON DBMS_CLOUD_AI TO USERNAME;
```

**Cloud Credentials and Object Storage**

Enables access to cloud credential management and Oracle Object Storage integration.

```sql
GRANT EXECUTE ON DBMS_CLOUD TO USERNAME;
```

**RAG and Document Processing**

Enables access to cloud data pipelines for data ingestion and document processing, including RAG workflows.

```sql
GRANT EXECUTE ON DBMS_CLOUD_PIPELINE TO USERNAME;
```

### 3. Create Credentials for Select AI

Before creating a **Select AI Profile**, the database user must configure credentials that allow Select AI to authenticate with the selected AI provider, such as OCI Generative AI.

Credentials are securely stored in the database and referenced by the AI profile.

**Example: Create an OCI Credential**

Connect as the newly created database user and execute:

```sql
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'CREDAI01',
    user_ocid       => '<OCI_USER_OCID>',
    tenancy_ocid    => '<OCI_TENANCY_OCID>',
    private_key     => '<OCI_PRIVATE_KEY>',
    fingerprint     => '<API_KEY_FINGERPRINT>'
  );
END;
/
```

Replace the placeholder values with the corresponding OCI configuration details.

**Important:** Never commit private keys, API tokens, or other credentials to GitHub. Use secure secret management and avoid storing sensitive values in SQL scripts or notebooks.

### 4. Create a Select AI Profile

Once the credential has been created, it can be referenced when configuring a Select AI profile.

**Example:**

```sql
BEGIN
  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'MY_AI_PROFILE',
    attributes   => '{
      "provider": "oci",
      "credential_name": "CREDAI01",
      "region": "eu-frankfurt-1",
      "model": "cohere.command-r-plus"
    }'
  );
END;
/
```

Update the region and model to match the OCI Generative AI service configuration and the models available in your tenancy.

The AI profile can then be used with **Select AI** and supported **Select AI Agent Framework** workflows.

### 5. Verify Access

Log in as the new database user and verify that:

- Oracle Machine Learning (OML) is accessible.
- The required OCI credential has been created.
- The Select AI profile can access the configured AI provider.
- The user can create and manage AI Agents, Tasks, Tools, and Teams.
- Required Object Storage resources are accessible.

**Note:** Package execution privileges alone may not be sufficient. Additional database roles, object privileges, OCI IAM policies, and service-specific permissions may be required depending on the environment and use case.