# Testing Oracle AI Database MCP with cURL on macOS

This guide demonstrates how to connect to the **Oracle Autonomous AI Database MCP Server** using `curl` on macOS.

During the Forest Workshop, we will use the Model Context Protocol (MCP) to discover and execute AI Agent tools directly in Oracle Autonomous AI Database.

The example demonstrates how to invoke the `NF_RUN_FOREST_TEAM` tool, which executes the `NF_FOREST_TEAM` database AI Agent Team to analyze forest data using natural language.

### 1. Prerequisites

Before starting, ensure that:

- You have access to an Oracle Autonomous AI Database with MCP enabled.
- You have a valid database username and password.
- You have the Autonomous Database OCID.
- The Forest AI Agent Team and its MCP tool wrapper have been created.
- `curl` and `jq` are available on your Mac.

Check that the required tools are installed:

```bash
curl --version
jq --version
```

If `jq` is not installed, install it using Homebrew:

```bash
brew install jq
```

### 2. Configure Environment Variables

Open Terminal on your Mac and define the following environment variables.

Replace the placeholder values with your database credentials and Autonomous Database OCID.

```bash
export DB_USER="<username>"
export DB_PASSWORD="<password>"

export ADB_BASE="https://dataaccess.adb.eu-frankfurt-1.oraclecloudapps.com"
export ADB_OCID="<autonomous_database_ocid>"

export TOKEN_URL="$ADB_BASE/adb/auth/v1/databases/$ADB_OCID/token"
export MCP_URL="$ADB_BASE/adb/mcp/v1/databases/$ADB_OCID"
```

**Important:**

- Use the correct OCI region for your Autonomous Database.
- The `ADB_OCID` must identify your Autonomous Database instance.
- Do not include spaces before or after the OCID.
- Never commit passwords, access tokens, or other credentials to GitHub.

### 3. Authenticate and Retrieve an Access Token

Before calling the MCP endpoint, authenticate with the Autonomous Database authentication service.

The following request uses the database username and password to obtain an access token.

```bash
TOKEN_RESPONSE=$(curl -sS --fail-with-body --location \
  "$TOKEN_URL" \
  --header "Content-Type: application/json" \
  --header "Accept: application/json" \
  --data "$(jq -n \
    --arg username "$DB_USER" \
    --arg password "$DB_PASSWORD" \
    '{
      grant_type: "password",
      username: $username,
      password: $password
    }')")
```

The response is stored in the shell variable `TOKEN_RESPONSE`.

#### Inspect the Authentication Response

Check the JSON response structure without displaying the access token:

```bash
printf '%s' "$TOKEN_RESPONSE" | jq 'keys'
```

A successful response should contain an `access_token` field.

#### Extract the Access Token

```bash
export MCP_TOKEN=$(
  printf '%s' "$TOKEN_RESPONSE" |
  jq -r '.access_token // empty'
)
```

Verify that a token was returned:

```bash
echo "Token length: ${#MCP_TOKEN}"
```

The token length should be greater than zero.

You can also check:

```bash
if [ -z "$MCP_TOKEN" ]; then
  echo "ERROR: No access token received"
else
  echo "Authentication successful"
fi
```

**Security note:** Avoid printing the actual access token in terminal output or logs. The token grants authenticated access to the MCP endpoint until it expires or is revoked.

### 4. Initialize the MCP Connection

MCP uses JSON-RPC 2.0 messages to communicate between clients and servers.

The first step is to initialize the MCP session.

```bash
curl -sS -i "$MCP_URL" \
  -H "Authorization: Bearer ${MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  --data '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-06-18",
      "capabilities": {},
      "clientInfo": {
        "name": "forest-mcp-test",
        "version": "1.0.0"
      }
    }
  }'
```

#### Expected Result

A successful response contains information about the MCP server, including:

- Supported MCP protocol version.
- Server capabilities.
- Server name and version.

The server may return JSON directly or use Server-Sent Events (SSE).

**Note:** A complete stateful MCP client should also send `notifications/initialized` after successful initialization and preserve any `Mcp-Session-Id` returned by the server. For this workshop, the examples demonstrate individual HTTP requests. If the server requires session state, subsequent requests must include the session ID.

### 5. Discover Available MCP Tools

Use the MCP `tools/list` method to discover the tools exposed by the database MCP server.

```bash
curl -sS -i -X POST "$MCP_URL" \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-06-18" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }'
```

#### Expected Result

The response should contain a list of available tools, including their names, descriptions, and input schemas.

For this workshop, look for:

`NF_RUN_FOREST_TEAM`

This tool provides MCP access to the Forest AI Agent Team running inside Oracle Autonomous AI Database.

The tool accepts the following input parameter:

| Parameter | Description |
|---|---|
| `p_prompt` | Natural-language question or instruction sent to the Forest AI Agent Team. |

### 6. Execute the Forest AI Agent Team via MCP

Once the MCP connection has been established and the tool is available, use `tools/call` to execute it.

The following example asks the Forest AI Agent Team to identify spruce forest stands older than 50 years and return their coordinates.

```bash
curl -sS -i -X POST "$MCP_URL" \
  -H "Authorization: Bearer $MCP_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-06-18" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "NF_RUN_FOREST_TEAM",
      "arguments": {
        "p_prompt": "Find spruce stands older than 50 years and give me the coordinates of these areas"
      }
    }
  }'
```

#### How It Works

1. The MCP client sends a JSON-RPC `tools/call` request to the Autonomous Database MCP endpoint.
2. The MCP server identifies the `NF_RUN_FOREST_TEAM` tool.
3. The tool invokes the `NF_FOREST_TEAM` database AI Agent Team.
4. The team processes the natural-language question and may use database tools for forest search, spatial analysis, or GeoJSON generation.
5. The result is returned to the MCP client as an MCP tool response.

#### Expected Result

The response depends on the forest data available in the database.

It may include:

- Forest stands matching the specified criteria.
- Forest stand identifiers and attributes.
- Coordinates or spatial information.
- A natural-language summary of the results.

The actual output format depends on the tool implementation and the agent response.

### 7. Try Additional Questions

You can modify the `p_prompt` parameter to test different forest analysis questions.

**Example 1 — Search by forest species**

```json
{
  "p_prompt": "Which tree species do I have?"
}
```

**Example 2 — Spatial analysis**

```json
{
  "p_prompt": "Which forest stands overlap the selected area?"
}
```

**Example 3 — GeoJSON output**

```json
{
  "p_prompt": "Return GeoJSON for stand id 3"
}
```

Use the same `tools/call` request from Step 6 and replace the prompt text.



### 8. Security Considerations

When testing MCP access:

- Never store database passwords or access tokens in GitHub repositories.
- Avoid hardcoding credentials in shell scripts.
- Use environment variables or an approved secret-management solution.
- Do not include access tokens in shared logs or screenshots.
- Use dedicated database users with the minimum required privileges.
- Remove sensitive environment variables when testing is complete.

For example:

```bash
unset DB_PASSWORD
unset MCP_TOKEN
unset TOKEN_RESPONSE
```

### Summary

This workshop exercise demonstrates the basic MCP workflow for accessing Oracle Autonomous AI Database Agent Framework tools:

**Authenticate → Initialize MCP → Discover Tools → Execute Agent Tool → Receive Results**

By exposing database AI Agents through MCP, external applications and AI clients can interact with Oracle Autonomous AI Database capabilities, including Select AI, spatial analysis, and database-resident AI Agent Teams.