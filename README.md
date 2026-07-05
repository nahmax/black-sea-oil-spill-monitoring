<!-- portfolio:start
{
  "title": "Black Sea Oil Spill Monitoring",
  "summary": "An n8n automation stack for monitoring Black Sea oil spill incidents with news search, PostgreSQL, Sentinel-1 imagery, AI detection, and Telegram publishing.",
  "domains": ["Automation", "AI", "Geospatial Monitoring", "Data Systems"],
  "stack": ["n8n", "PostgreSQL", "pgvector", "Sentinel Hub", "OpenAI", "Telegram Bot", "Docker"],
  "featured": true,
  "order": 1,
  "year": "2026",
  "status": "Public repo",
  "screenshots": []
}
portfolio:end -->

# Black Sea Oil Spill Monitoring System

An n8n-based monitoring platform for oil and fuel spill incidents in the Black Sea and Azov Sea region.

The repository contains exported n8n workflows, the PostgreSQL schema, and a local Docker setup that makes it easier to run the project as a portfolio-grade automation stack.

## What This Project Does

- Searches for fresh news about real spill incidents in the Black Sea region.
- Stores and deduplicates events in PostgreSQL with vector search support.
- Resolves event coordinates and enriches incidents with satellite imagery.
- Fetches Sentinel-1 scenes through Sentinel Hub.
- Runs a vision-based spill detection step over the latest satellite image.
- Publishes and refreshes Telegram channel posts for each event.
- Exposes a RAG-style chat workflow over the stored incident database.

## Main Workflows

- <code>WF_NEWS_ON_DEMAND</code> - searches the web, classifies fresh incidents, and inserts new events.
- <code>AGENT_RAG_QUERY</code> - performs semantic search over the event database.
- <code>WF_EVENT_UPSERT_MANUAL</code> - inserts or updates a hand-curated incident.
- <code>WF_EVENT_COORDS_AGENT</code> - infers coordinates for a specific event.
- <code>WF_EVENT_S1_AGENT</code> - requests a Sentinel-1 image for an event and stores the result.
- <code>WF_EVENT_DET_AGENT</code> - runs satellite-image spill detection.
- <code>WF_EVENT_PUBLISH_AGENT</code> - renders and synchronizes the Telegram channel post.
- <code>AGENT_CHAT_BOT</code> - orchestrates the user-facing Telegram assistant.

## Repository Layout

- <code>sql/bd.sql</code> - PostgreSQL schema, vector extension, helper functions, and tables.
- <code>workflows/</code> - exported n8n workflows ready to import.
- <code>docker-compose.yml</code> - local runtime for n8n plus PostgreSQL.
- <code>.env.example</code> - safe template for local secrets and runtime settings.
- <code>.gitignore</code> - keeps secrets and local data out of git.

## Quick Start with Docker

1. Copy <code>.env.example</code> to <code>.env</code>.
2. Fill in the required values in <code>.env</code>.
3. Start the stack with <code>docker compose up -d</code>.
4. Open <code>http://localhost:5678</code> and log in to n8n.
5. Wait for PostgreSQL to finish initializing. The schema in <code>sql/bd.sql</code> is applied automatically on the first database startup.

## Required Local Configuration

The Docker stack uses two sets of configuration values:

- Docker and runtime variables from <code>.env</code>.
- n8n credentials configured inside the n8n UI.

### Values Stored in <code>.env</code>

- <code>POSTGRES_DB</code> - database name for the project schema.
- <code>POSTGRES_USER</code> - database user for the project schema.
- <code>POSTGRES_PASSWORD</code> - database password.
- <code>POSTGRES_PORT</code> - host port for PostgreSQL.
- <code>N8N_HOST</code> - public host name used by n8n.
- <code>N8N_HOST_PORT</code> - host port mapped to the n8n container.
- <code>N8N_ENCRYPTION_KEY</code> - required n8n encryption key.
- <code>N8N_EDITOR_BASE_URL</code> - URL shown by the n8n editor.
- <code>WEBHOOK_URL</code> - public base URL for n8n webhooks.
- <code>GENERIC_TIMEZONE</code> and <code>TIMEZONE</code> - keep timestamps aligned.
- <code>SENTINEL_HUB_CLIENT_ID</code> and <code>SENTINEL_HUB_CLIENT_SECRET</code> - Sentinel Hub credentials used directly by the Sentinel-1 workflow.

### n8n Credentials to Create

Create these credentials inside n8n after the container starts:

- <code>OpenAi account</code> - OpenAI API key for news search, embeddings, and vision steps.
- <code>Postgres account</code> - points to the project PostgreSQL container (<code>postgres</code>, port <code>5432</code>, database <code>oil_spills</code> by default).
- <code>Telegram account</code> - bot token for Telegram posting and replies.

## Import Order in n8n

Import the workflows in this order so that the tool workflows exist before the main chat bot is linked:

1. <code>WF_NEWS_ON_DEMAND</code>
2. <code>AGENT_RAG_QUERY</code>
3. <code>WF_EVENT_UPSERT_MANUAL</code>
4. <code>WF_EVENT_COORDS_AGENT</code>
5. <code>WF_EVENT_S1_AGENT</code>
6. <code>WF_EVENT_DET_AGENT</code>
7. <code>WF_EVENT_PUBLISH_AGENT</code>
8. <code>AGENT_CHAT_BOT</code>

After import, open <code>AGENT_CHAT_BOT</code> and verify the subworkflow nodes if n8n does not automatically reconnect them by name.

## Security Notes

- No secrets are committed to the repository.
- Sensitive values live in <code>.env</code> or inside n8n credentials only.
- The Sentinel Hub client ID and secret are read from environment variables in <code>WF_EVENT_S1_AGENT</code>.
- Keep <code>N8N_ENCRYPTION_KEY</code> unique and private.
- Use a restricted Telegram bot and only the channel you actually intend to publish to.
- For production deployments, move n8n behind HTTPS and rotate tokens before sharing the project publicly.

## Data Model

The PostgreSQL schema in <code>sql/bd.sql</code> defines:

- <code>public.events</code> - core incident records.
- <code>public.users</code> - Telegram user metadata for the chat bot.
- <code>public.tg_posts</code> - Telegram post references for published events.
- <code>public.tg_media</code> - stored media references for satellite imagery.
- <code>public.evidence</code> - supporting evidence captured by the workflows.
- <code>public.agent_settings</code> - runtime settings such as the target channel.

## Maintainer

nahmax
