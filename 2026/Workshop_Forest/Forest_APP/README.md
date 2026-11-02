# Oracle APEX Forest Application

This folder contains the Oracle APEX Forest application and the supporting database package required to run the application in **Oracle Autonomous AI Database**.

The application is provided as an APEX export file:

- `f104_ApexForest.sql` — Oracle APEX application export.

The supporting database package consists of:

- `nai_apex_ai.sql` — Database package installation script.
- `nai_apex_ai.plb` — Database package implementation script.

Follow the steps below to install and configure the application.

### 1. Prerequisites

Before installing the APEX application, ensure that:

- An Oracle Autonomous AI Database is available.
- A database user (`USERNAME`) has been created.
- The required database privileges have been granted.
- An APEX workspace is available and associated with the database schema `USERNAME`.
- The required Select AI credentials and AI profile have been configured, if used by the application.
- The application export and supporting database package files are available.

### 2. Create an APEX Workspace

If an APEX workspace has not already been created, create one for the database user.

1. Log in to **Oracle APEX Administration**.
2. Navigate to **Manage Workspaces → Create Workspace**.
3. Create a new workspace, for example `USERNAME`.
4. Associate the workspace with the existing database schema `USERNAME`.
5. Configure the workspace administrator account.
6. Complete the workspace creation process.

**Note:** The workspace name and database schema name can be different. In this example, both are named `USERNAME` for simplicity.

### 3. Install the Database Package NAI_APEX_AI

The APEX application requires the database package `NAI_APEX_AI`. Install the package before importing the application.

#### Step 1: Log in to APEX

1. Log in to the APEX workspace `USERNAME`.
2. Open **SQL Workshop → SQL Scripts**.

#### Step 2: Install the Package Specification

1. Click **Upload**.
2. Select the file `nai_apex_ai.sql`.
3. Upload the script.
4. Open the uploaded script.
5. Select `USERNAME` as the database schema.
6. Click **Run** to execute the script.
7. Review the execution results and verify that the script completed successfully.

#### Step 3: Install the Package Body

1. Return to **SQL Workshop → SQL Scripts**.
2. Click **Upload**.
3. Select the file `nai_apex_ai.plb`.
4. Upload the script.
5. Open the uploaded script.
6. Select `USERNAME` as the database schema.
7. Click **Run** to execute the script.
8. Review the execution results and verify that the package body was installed successfully.

**Important:** Install `nai_apex_ai.sql` before `nai_apex_ai.plb`, as the package specification must exist before the package body can be compiled.

#### Step 4: Verify Package Installation

Open **SQL Workshop → SQL Commands** and execute:

```sql
SELECT object_name, object_type, status
FROM user_objects
WHERE object_name = 'NAI_APEX_AI'
ORDER BY object_type;
```

Expected results:

| OBJECT_NAME | OBJECT_TYPE | STATUS |
|---|---|---|
| NAI_APEX_AI | PACKAGE | VALID |
| NAI_APEX_AI | PACKAGE BODY | VALID |

Both objects should have the status `VALID`.

If either object is invalid, review the script execution results and compilation errors before proceeding.

### 4. Import the APEX Application

Once the database package has been installed successfully, import the APEX application.

#### Step 1: Import the Application File

1. Log in to the APEX workspace `USERNAME`.
2. Open **App Builder**.
3. Click **Import**.
4. Select the application export file `f104_ApexForest.sql`.
5. Follow the import wizard to upload the application.

#### Step 2: Configure the Application

During the installation process:

1. Select the appropriate application ID, retaining the original ID if available or assigning a new one.
2. Select `USERNAME` as the **Parsing Schema**.
3. Review any additional installation options.
4. Complete the application installation.

**Note:** The parsing schema determines which database schema the application uses when executing SQL and PL/SQL.

### 5. Verify the Installation

After importing the application:

1. Open **App Builder**.
2. Locate the imported Forest application.
3. Open the application and review its configuration.
4. Verify that the parsing schema is set to `USERNAME`.
5. Confirm that the database package `NAI_APEX_AI` is valid.
6. Check any application settings, credentials, AI profile references, and required database objects.
7. Click **Run Application** to launch the application.

Test the main application functionality to confirm that the APEX application can communicate with the required database packages and AI services.


**Important:** The application may require additional database objects, configuration settings, or privileges depending on its implementation. Ensure that all dependencies are installed before running the application.