# APEX App
The folder contains the APEX application (f104_ApexForest.sql).

## Pre-install database package
1. Create an APEX Workspace for the user "USERNAME"
2. Install the database package NAI_APEX_AI (nai_apex_ai.sql & nai_apex_ai.plb)

       - Logg in to tne APEX workspace "USERNAME"
       - Open SQL Workshop > SQL Scripts
       - Upload nai_apex_ai.sql 
       - Select USERNAME as the schema, and run the scripts.
       - Upload nai_apex_ai.plb
       - Select USERNAME as the schema, and run the scripts
      
## Import APEX application
3. Import the APEX application f104_ApexForest.sql