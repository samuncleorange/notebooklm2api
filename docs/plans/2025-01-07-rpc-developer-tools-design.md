# RPC Developer Tools Design

**Date**: 2025-01-07
**Status**: Approved
**Priority Order**: Maintenance > Debugging > Discovery

## Problem Statement

`notebooklm-py` uses reverse-engineered RPC method IDs (like `wXbhsf`, `CCqFvf`) that Google can change at any time. Currently, discovering and updating these IDs requires manual network traffic analysis.

## Solution Overview

A suite of developer scripts for automated RPC maintenance, debugging, and discovery:

| Script | Purpose |
|--------|---------|
| `scripts/rpc/check.py` | Detect RPC breakage (CI + local) |
| `scripts/rpc/capture.py` | Record RPC calls to HAR + JSON |
| `scripts/rpc/discover.py` | Headed browser for exploring new RPCs |
| `scripts/rpc/review.py` | Interactive add discovered RPCs to types.py |
| `scripts/rpc/suggest.py` | Auto-suggest enum names from context |
| `scripts/rpc/config.py` | Critical methods list configuration |

## Architecture

```
scripts/rpc/                          # Developer tools (not installed)
├── __init__.py
├── config.py                         # Critical methods list
├── check.py                          # Health checker
├── capture.py                        # HAR + JSON capture
├── discover.py                       # Headed browser discovery
├── review.py                         # Interactive review
└── suggest.py                        # Enum name heuristics

src/notebooklm/rpc/                   # Existing (reused)
├── types.py                          # RPCMethod enum (modified by review.py)
├── encoder.py                        # Request encoding
└── decoder.py                        # Response parsing
```

## Component Designs

### 1. RPC Health Checker (`check.py`)

**Purpose**: Detect when Google changes RPC method IDs.

**Configuration** (`config.py`):
```python
CRITICAL_METHODS = [
    "LIST_NOTEBOOKS",
    "CREATE_NOTEBOOK",
    "GET_NOTEBOOK",
    "DELETE_NOTEBOOK",
    "ADD_SOURCE",
    "GET_SOURCE",
    "DELETE_SOURCE",
    "GET_CONVERSATION_HISTORY",
    "CREATE_AUDIO",
    "GET_AUDIO",
    "POLL_STUDIO",
]
```

**CLI Interface**:
```bash
python scripts/rpc/check.py              # Check critical methods
python scripts/rpc/check.py --all        # Check all methods
python scripts/rpc/check.py --format json  # JSON output for CI
```

**Output**:
```
RPC Health Check
================
✅ LIST_NOTEBOOKS (wXbhsf) - OK
✅ CREATE_NOTEBOOK (CCqFvf) - OK
❌ GET_NOTEBOOK (rLM1Ne) - RPC error: method not found
...
Summary: 14/15 methods OK, 1 failed
```

### 2. RPC Capture (`capture.py`)

**Purpose**: Record RPC calls during automated sessions for debugging.

**Dual Output**:
1. **HAR file**: Raw HTTP traffic, Playwright-compatible
2. **Parsed JSON**: Human-readable with decoded batchexecute payloads

**Parsed JSON Format**:
```json
{
  "captures": [
    {
      "timestamp": "2025-01-07T10:30:00Z",
      "method": "LIST_NOTEBOOKS",
      "rpc_id": "wXbhsf",
      "request_params": [],
      "response_parsed": {"notebooks": [...]},
      "duration_ms": 245
    }
  ]
}
```

**CLI Interface**:
```bash
python scripts/rpc/capture.py --run "python examples/list_notebooks.py"
python scripts/rpc/capture.py --run "..." --trace    # With Playwright trace
python scripts/rpc/capture.py --run "..." --har-only # HAR only
```

### 3. RPC Discovery (`discover.py`)

**Purpose**: Headed browser session to discover new RPC methods.

**Workflow**:
1. Launch headed browser with stored auth
2. User interacts with NotebookLM UI
3. Terminal shows captured RPCs in real-time
4. Ctrl+C ends session, prompts for review

**Live Output**:
```
🔍 RPC Discovery Mode
━━━━━━━━━━━━━━━━━━━━━
Browser opened. Interact with NotebookLM to discover RPCs.
Press Ctrl+C when done.

[10:30:01] ✓ wXbhsf → LIST_NOTEBOOKS
[10:30:05] ✓ CCqFvf → CREATE_NOTEBOOK
[10:30:12] ? xYz123 → (unknown) triggered by: clicked "Export"
[10:30:15] ? aBc456 → (unknown) triggered by: clicked "Share"

^C
━━━━━━━━━━━━━━━━━━━━━
Session ended. Found 2 unknown RPC methods.
Saved to: captures/discovered_2025-01-07.jsonl

Review and add to types.py now? [y/N]:
```

**Discovery Log** (`discovered_*.jsonl`):
```jsonl
{"rpc_id": "xYz123", "timestamp": "...", "trigger_url": "...", "request_params": [...], "response_preview": "..."}
```

**CLI Interface**:
```bash
python scripts/rpc/discover.py           # Basic session
python scripts/rpc/discover.py --trace   # With Playwright trace
python scripts/rpc/discover.py --review  # Auto-review at end
```

### 4. Interactive Review (`review.py`)

**Purpose**: Add discovered RPCs to `types.py` with confirmation.

**Flow**:
```
[1/2] RPC ID: xYz123
      Triggered: clicked near "Export to Slides"
      Suggested: EXPORT_SLIDES

      [a] Add as EXPORT_SLIDES
      [r] Rename → enter custom name
      [s] Skip
      [v] View full request/response
      [q] Quit review

      Choice: a

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Review Complete. Pending changes:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  + EXPORT_SLIDES = "xYz123"
  + SHARE_PROJECT_PUBLIC = "aBc456"

Apply these changes to src/notebooklm/rpc/types.py? [y/N]: y

✓ Updated types.py with 2 new methods.
```

**CLI Interface**:
```bash
python scripts/rpc/review.py                              # Review pending
python scripts/rpc/review.py captures/discovered_*.jsonl  # Specific file
python scripts/rpc/review.py --auto                       # Use suggested names (still confirms)
python scripts/rpc/review.py --dry-run                    # Preview only
```

### 5. Auto-Suggest (`suggest.py`)

**Purpose**: Guess enum names from context clues.

**Heuristics**:
1. Request params keywords (export, share, create, delete, etc.)
2. Trigger URL path segments
3. Response structure (list vs single item)
4. Fallback: `UNKNOWN_{RPC_ID}`

## Authentication

**Dual-mode support**:
- **Headless (CI)**: Uses stored auth from `~/.notebooklm/auth.json`
- **Headed (Discovery)**: Uses Playwright persistent context

**Shared auth source**:
```python
context = browser.new_context(storage_state="~/.notebooklm/browser_state")
```

## CI Integration

**GitHub Actions Workflow** (`.github/workflows/rpc-health-check.yml`):

```yaml
name: RPC Health Check

on:
  schedule:
    - cron: '0 8 * * *'  # Daily at 8am UTC
  workflow_dispatch:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install -e .
          playwright install chromium

      - name: Restore auth session
        run: |
          echo "${{ secrets.NOTEBOOKLM_AUTH }}" | base64 -d > ~/.notebooklm/auth.json

      - name: Run RPC health check
        run: python scripts/rpc/check.py --format json > results.json

      - name: Check for failures
        run: |
          if jq -e '.failed | length > 0' results.json; then
            echo "::error::RPC methods have changed!"
            exit 1
          fi
```

**Notification**: GitHub sends email on workflow failure.

## File Structure

```
scripts/rpc/
├── __init__.py
├── config.py          # CRITICAL_METHODS list
├── check.py           # Health checker (~150 lines)
├── capture.py         # HAR + JSON capture (~200 lines)
├── discover.py        # Headed browser discovery (~250 lines)
├── review.py          # Interactive review (~200 lines)
└── suggest.py         # Enum name heuristics (~100 lines)

captures/              # Generated output directory
├── *.har              # HAR files
├── *.json             # Parsed capture files
└── discovered_*.jsonl # Discovery logs

.github/workflows/
└── rpc-health-check.yml
```

## Implementation Order

1. **config.py + check.py** - Core maintenance functionality
2. **capture.py** - Debugging capability
3. **suggest.py** - Heuristics module
4. **discover.py + review.py** - Discovery workflow
5. **GitHub Actions workflow** - CI integration

## Dependencies

Existing:
- `playwright` (already in project for auth)
- `httpx` (already in project for HTTP)

No new dependencies required.
