# Agent Instructions

Guidelines for AI agents working on this codebase.

## Project Overview

This is a Cloudflare Worker that runs [OpenClaw](https://github.com/openclaw/openclaw) (formerly Moltbot, formerly Clawdbot) in a Cloudflare Sandbox container. It provides:
- Proxying to the OpenClaw gateway (web UI + WebSocket)
- Admin UI at `/_admin/` for device management
- API endpoints at `/api/*` for device pairing and gateway control
- Debug endpoints at `/debug/*` for troubleshooting
- CDP (Chrome DevTools Protocol) shim at `/cdp/*` for browser automation

**Note:** The CLI tool is still named `clawdbot` (upstream hasn't renamed yet), so CLI commands and internal config paths still use that name.

## Project Structure

```
src/
├── index.ts              # Main Hono app, route mounting, request handling
├── types.ts              # TypeScript type definitions (MoltbotEnv, AppEnv, JWTPayload)
├── config.ts             # Constants (ports, timeouts, paths)
├── env.d.ts              # Environment type declarations
├── test-utils.ts         # Test utilities
├── assets/               # Static HTML assets
│   ├── loading.html      # Loading page shown while gateway starts
│   └── config-error.html # Error page for missing configuration
├── auth/                 # Cloudflare Access authentication
│   ├── index.ts          # Re-exports
│   ├── jwt.ts            # JWT verification using jose library
│   └── middleware.ts     # Hono middleware for CF Access auth
├── gateway/              # OpenClaw gateway management
│   ├── index.ts          # Re-exports
│   ├── process.ts        # Process lifecycle (find, start, ensure)
│   ├── env.ts            # Environment variable building for container
│   ├── r2.ts             # R2 bucket mounting (s3fs)
│   ├── sync.ts           # R2 backup sync logic
│   └── utils.ts          # Shared utilities (waitForProcess)
├── routes/               # API route handlers
│   ├── index.ts          # Re-exports
│   ├── public.ts         # Public routes (no auth): /sandbox-health, /api/status, logos
│   ├── api.ts            # Protected API: /api/admin/* (devices, storage, gateway)
│   ├── admin-ui.ts       # Admin UI SPA: /_admin/*
│   ├── debug.ts          # Debug endpoints: /debug/* (processes, logs, version, ws-test)
│   └── cdp.ts            # CDP shim: /cdp/* (WebSocket, json/version, json/list)
└── client/               # React admin UI (Vite + React)
    ├── main.tsx          # Entry point
    ├── App.tsx           # Main app component
    ├── App.css           # App styles
    ├── index.css         # Global styles
    ├── api.ts            # API client for admin endpoints
    └── pages/
        ├── AdminPage.tsx # Main admin page (devices, storage, gateway controls)
        └── AdminPage.css # Admin page styles
```

## Architecture

```
Browser
   │
   ▼
┌─────────────────────────────────────┐
│     Cloudflare Worker (index.ts)    │
│  - Request logging                    │
│  - Sandbox initialization             │
│  - Route authentication               │
│  - Proxy to gateway                   │
│  - WebSocket interception             │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│     Cloudflare Sandbox Container    │
│  ┌───────────────────────────────┐  │
│  │     OpenClaw Gateway          │  │
│  │  - Control UI on port 18789   │  │
│  │  - WebSocket RPC protocol     │  │
│  │  - Agent runtime              │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │     R2 Storage (optional)     │  │
│  │  - Mounted at /data/moltbot   │  │
│  │  - Syncs every 5 minutes      │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Key Files Reference

| File | Purpose | Key Exports/Functions |
|------|---------|----------------------|
| `src/index.ts` | Main worker entry | `app`, `scheduled`, `validateRequiredEnv`, `buildSandboxOptions` |
| `src/config.ts` | Constants | `MOLTBOT_PORT` (18789), `STARTUP_TIMEOUT_MS` (180s), `R2_MOUNT_PATH` |
| `src/types.ts` | TypeScript types | `MoltbotEnv`, `AppEnv`, `AccessUser`, `JWTPayload` |
| `src/gateway/process.ts` | Gateway lifecycle | `findExistingMoltbotProcess()`, `ensureMoltbotGateway()` |
| `src/gateway/env.ts` | Env var mapping | `buildEnvVars()` - maps worker env to container env |
| `src/gateway/r2.ts` | R2 mounting | `mountR2Storage()` - uses s3fs |
| `src/gateway/sync.ts` | Backup sync | `syncToR2()` - rsync to R2 |
| `src/auth/middleware.ts` | Auth middleware | `createAccessMiddleware()`, `isDevMode()`, `extractJWT()` |
| `src/routes/api.ts` | Admin API | Device listing/approval, storage sync, gateway restart |
| `src/routes/cdp.ts` | CDP shim | Browser automation via Puppeteer |
| `Dockerfile` | Container image | Based on `cloudflare/sandbox:0.7.0` + Node 22 + clawdbot |
| `start-moltbot.sh` | Startup script | Configures and launches gateway, handles R2 restore |
| `moltbot.json.template` | Default config | Minimal OpenClaw configuration |
| `wrangler.jsonc` | CF config | Worker + Container + R2 + Browser bindings |

## Route Structure

### Public Routes (No Authentication)
- `GET /sandbox-health` - Health check endpoint
- `GET /logo.png`, `/logo-small.png` - Static logos
- `GET /api/status` - Gateway status (running/not running)
- `GET /_admin/assets/*` - Admin UI static assets (CSS/JS)

### CDP Routes (Query Param Authentication)
- `GET /cdp?secret=<token>` - WebSocket upgrade for CDP
- `GET /cdp/json/version?secret=<token>` - Browser version info
- `GET /cdp/json/list?secret=<token>` - List available targets

### Protected Routes (Cloudflare Access Required)
- `GET /_admin/*` - Admin UI (serves SPA)
- `/api/admin/*` - Admin API endpoints:
  - `GET /devices` - List pending and paired devices
  - `POST /devices/:requestId/approve` - Approve a pending device
  - `POST /devices/approve-all` - Approve all pending devices
  - `GET /storage` - R2 storage status
  - `POST /storage/sync` - Trigger manual R2 sync
  - `POST /gateway/restart` - Restart gateway process
- `/debug/*` - Debug endpoints (when `DEBUG_ROUTES=true`):
  - `GET /version` - Container version info
  - `GET /processes` - List processes
  - `GET /logs?id=<process_id>` - Get process logs
  - `GET /env` - Environment config (sanitized)
  - `GET /cli?cmd=<command>` - Run CLI command
  - `GET /gateway-api?path=<path>` - Probe gateway API
  - `GET /container-config` - Read container config
  - `GET /ws-test` - Interactive WebSocket test page

### Catch-All (Proxy to Gateway)
- All other routes proxy to OpenClaw gateway on port 18789
- WebSocket connections are intercepted for error transformation

## Environment Variables

### Required for Production
- `MOLTBOT_GATEWAY_TOKEN` - Gateway access token (generate with `openssl rand -hex 32`)
- `CF_ACCESS_TEAM_DOMAIN` - Cloudflare Access team domain (e.g., `myteam.cloudflareaccess.com`)
- `CF_ACCESS_AUD` - Application Audience tag from Access
- `ANTHROPIC_API_KEY` OR (`AI_GATEWAY_API_KEY` + `AI_GATEWAY_BASE_URL`) - AI provider credentials

### Optional
- `DEV_MODE` - Set to `'true'` to skip CF Access auth and device pairing (local dev only)
- `DEBUG_ROUTES` - Set to `'true'` to enable `/debug/*` endpoints
- `SANDBOX_SLEEP_AFTER` - Container sleep timeout: `'never'` (default) or duration like `'10m'`, `'1h'`
- `ANTHROPIC_BASE_URL` - Override Anthropic API base URL
- `OPENAI_API_KEY` - OpenAI API key (alternative provider)
- `GLM_API_KEY` - Z.ai GLM API key (alternative provider)
- `GLM_BASE_URL` - Z.ai GLM Coding Plan API base URL (defaults to `https://api.z.ai/api/coding/paas/v4`)
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_DM_POLICY` - Telegram integration
- `DISCORD_BOT_TOKEN`, `DISCORD_DM_POLICY` - Discord integration
- `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN` - Slack integration
- `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `CF_ACCOUNT_ID` - R2 storage credentials
- `CDP_SECRET` - Shared secret for CDP endpoint
- `WORKER_URL` - Public worker URL (for CDP)

### Container Environment Variables (Mapped)
The `buildEnvVars()` function in `src/gateway/env.ts` maps worker env vars to container env vars:
- `MOLTBOT_GATEWAY_TOKEN` → `CLAWDBOT_GATEWAY_TOKEN`
- `DEV_MODE` → `CLAWDBOT_DEV_MODE`
- Chat tokens passed through as-is

## Key Patterns

### CLI Commands
When calling the OpenClaw CLI from the worker, always include `--url ws://localhost:18789`:
```typescript
sandbox.startProcess('clawdbot devices list --json --url ws://localhost:18789')
```

CLI commands take 10-15 seconds due to WebSocket connection overhead. Use the `waitForProcess()` helper:
```typescript
import { waitForProcess } from './gateway';
await waitForProcess(proc, 20000); // 20 second timeout
```

### Success Detection
The CLI outputs "Approved" (capital A). Use case-insensitive checks:
```typescript
stdout.toLowerCase().includes('approved')
```

### Process Status Checking
Don't rely on `proc.status` alone - the sandbox API may not update immediately. Always verify by checking expected output:
```typescript
// Check for timestamp file after sync
const timestampProc = await sandbox.startProcess(`cat ${R2_MOUNT_PATH}/.last-sync`);
await waitForProcess(timestampProc, 5000);
const logs = await timestampProc.getLogs();
const success = logs.stdout?.match(/^\d{4}-\d{2}-\d{2}/);
```

### R2 Mount Checking
Don't rely on `sandbox.mountBucket()` error messages. Instead, check the mount table:
```typescript
const proc = await sandbox.startProcess(`mount | grep "s3fs on ${R2_MOUNT_PATH}"`);
await waitForProcess(proc, 2000);
const logs = await proc.getLogs();
const mounted = logs.stdout?.includes('s3fs');
```

### R2 rsync
Use `--no-times` flag because s3fs doesn't support setting timestamps:
```bash
rsync -r --no-times --delete /source/ /dest/
```

### WebSocket Interception
WebSocket connections in `src/index.ts` are intercepted to transform error messages:
- "gateway token missing" → User-friendly redirect URL
- "pairing required" → Link to admin UI

## Commands

```bash
# Development
npm run dev             # Vite dev server for client
npm run start           # wrangler dev (local worker with sandbox)

# Building & Deploying
npm run build           # Build worker + client
npm run deploy          # Build and deploy to Cloudflare

# Testing
npm test                # Run tests (vitest)
npm run test:watch      # Run tests in watch mode
npm run test:coverage   # Run tests with coverage

# Type Checking
npm run typecheck       # TypeScript check
npm run types           # Generate wrangler types
```

## Testing

Tests use Vitest. Test files are colocated with source files (`*.test.ts`).

Current test coverage:
- `auth/jwt.test.ts` - JWT decoding and validation
- `auth/middleware.test.ts` - Auth middleware behavior
- `gateway/env.test.ts` - Environment variable building
- `gateway/process.test.ts` - Process finding logic
- `gateway/r2.test.ts` - R2 mounting logic
- `gateway/sync.test.ts` - R2 sync logic

When adding new functionality, add corresponding tests following the existing patterns.

## Code Style

- Use TypeScript strict mode
- Prefer explicit types over inference for function signatures
- Keep route handlers thin - extract logic to separate modules
- Use Hono's context methods (`c.json()`, `c.html()`) for responses
- Always use `waitForProcess()` instead of manual polling loops

## Documentation

- `README.md` - User-facing documentation (setup, configuration, usage)
- `AGENTS.md` - This file, for AI agents

Development documentation goes in AGENTS.md, not README.md.

## Local Development

```bash
npm install
cp .dev.vars.example .dev.vars
# Edit .dev.vars with your ANTHROPIC_API_KEY
npm run start
```

Create `.dev.vars`:
```bash
ANTHROPIC_API_KEY=sk-ant-...
DEV_MODE=true           # Skips CF Access auth + device pairing
DEBUG_ROUTES=true       # Enables /debug/* routes
```

### WebSocket Limitations
Local development with `wrangler dev` has issues proxying WebSocket connections through the sandbox. HTTP requests work but WebSocket connections may fail. Deploy to Cloudflare for full functionality.

## Docker Image Caching

The Dockerfile includes a cache bust comment. When changing `moltbot.json.template`, `start-moltbot.sh`, or skills, bump the version:

```dockerfile
# Build cache bust: 2026-01-28-v26-browser-skill
```

## Gateway Configuration

OpenClaw configuration is built at container startup:

1. `moltbot.json.template` is copied to `~/.clawdbot/clawdbot.json`
2. `start-moltbot.sh` updates the config with values from environment variables
3. Gateway starts with `--allow-unconfigured` flag (skips onboarding wizard)

### Configuration Schema Gotchas

- `agents.defaults.model` must be `{ "primary": "model/name" }` not a string
- `gateway.mode` must be `"local"` for headless operation
- No `webchat` channel - the Control UI is served automatically
- `gateway.bind` is not a config option - use `--bind` CLI flag

## Common Tasks

### Adding a New API Endpoint

1. Add route handler in `src/routes/api.ts`
2. Add types if needed in `src/types.ts`
3. Update client API in `src/client/api.ts` if frontend needs it
4. Add tests following existing patterns
5. Update AGENTS.md route documentation

### Adding a New Environment Variable

1. Add to `MoltbotEnv` interface in `src/types.ts`
2. If passed to container, add to `buildEnvVars()` in `src/gateway/env.ts`
3. If used in `start-moltbot.sh`, update the Node.js config script there
4. Update `.dev.vars.example`
5. Document in README.md secrets table

### Adding a New Debug Endpoint

1. Add route in `src/routes/debug.ts`
2. Use `waitForProcess()` for any CLI commands
3. Return consistent JSON structure with `status`, `error` fields
4. No need to update client - debug endpoints are API-only

### Debugging

```bash
# View live logs
npx wrangler tail

# Check secrets
npx wrangler secret list

# Check processes (requires DEBUG_ROUTES=true)
curl https://your-worker.workers.dev/debug/processes

# Check gateway logs
curl https://your-worker.workers.dev/debug/logs
```

## R2 Storage Notes

R2 is mounted via s3fs at `/data/moltbot`. Important gotchas:

- **rsync compatibility**: Use `rsync -r --no-times` instead of `rsync -a`. s3fs doesn't support setting timestamps, which causes rsync to fail with "Input/output error".

- **Mount checking**: Don't rely on `sandbox.mountBucket()` error messages to detect "already mounted" state. Instead, check `mount | grep s3fs` to verify the mount status.

- **Never delete R2 data**: The mount directory `/data/moltbot` IS the R2 bucket. Running `rm -rf /data/moltbot/*` will DELETE your backup data. Always check mount status before any destructive operations.

- **Process status**: The sandbox API's `proc.status` may not update immediately after a process completes. Instead of checking `proc.status === 'completed'`, verify success by checking for expected output (e.g., timestamp file exists after sync).

- **Backup structure**: Backups are stored at `${R2_MOUNT_PATH}/clawdbot/` (config) and `${R2_MOUNT_PATH}/skills/` (skills).

## CDP (Browser Automation)

The CDP shim allows browser automation via the `/cdp` endpoints. It uses Cloudflare's Browser Rendering binding (Puppeteer) to implement CDP protocol methods.

### Authentication
Pass `CDP_SECRET` as query param: `?secret=<token>`

### Supported Methods
- **Browser**: getVersion, close
- **Target**: createTarget, closeTarget, getTargets, attachToTarget
- **Page**: navigate, reload, getFrameTree, captureScreenshot, getLayoutMetrics, bringToFront, setContent, printToPDF, addScriptToEvaluateOnNewDocument, removeScriptToEvaluateOnNewDocument, handleJavaScriptDialog, stopLoading, getNavigationHistory, navigateToHistoryEntry, setBypassCSP
- **Runtime**: evaluate, callFunctionOn, getProperties, releaseObject, releaseObjectGroup
- **DOM**: getDocument, querySelector, querySelectorAll, getOuterHTML, getAttributes, setAttributeValue, focus, getBoxModel, scrollIntoViewIfNeeded, removeNode, setNodeValue, setFileInputFiles
- **Input**: dispatchMouseEvent, dispatchKeyEvent, insertText
- **Network**: enable, disable, setCacheDisabled, setExtraHTTPHeaders, setCookie, setCookies, getCookies, deleteCookies, clearBrowserCookies, setUserAgentOverride
- **Fetch**: enable, disable, continueRequest, fulfillRequest, failRequest, getResponseBody (request interception)
- **Emulation**: setDeviceMetricsOverride, clearDeviceMetricsOverride, setUserAgentOverride, setGeolocationOverride, clearGeolocationOverride, setTimezoneOverride, setTouchEmulationEnabled, setEmulatedMedia, setDefaultBackgroundColorOverride

## Skills

Custom skills are stored in `skills/` and copied to `/root/clawd/skills/` in the container.

### cloudflare-browser
Pre-installed skill for browser automation using the CDP shim.

Scripts:
- `screenshot.js` - Capture screenshots
- `video.js` - Create videos from page navigation
- `cdp-client.js` - Reusable CDP client library

See `skills/cloudflare-browser/SKILL.md` for full documentation.
