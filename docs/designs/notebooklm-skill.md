# NotebookLM Skill for Claude Code

**Status:** Implemented
**Date:** 2026-01-07

## Overview

A Claude Code skill that enables natural language automation of Google NotebookLM through the `notebooklm` CLI. The skill activates on explicit invocation (`/notebooklm`) or intent detection ("create a podcast about X").

## Design Decisions

### Autonomy Model

**Adaptive autonomy** - balance between automation and user control:

| Operation Type | Behavior |
|----------------|----------|
| Safe (list, status, create, ask, source add) | Run automatically |
| Destructive (delete) | Ask confirmation |
| Long-running (generate) | Ask confirmation |
| Filesystem writes (download) | Ask confirmation |

### Trigger Modes

1. **Explicit invocation**: `/notebooklm`, "use notebooklm"
2. **Intent detection**: "create a podcast about X", "summarize these URLs"

### Long Operation Handling

**Fire-and-forget pattern**:
- Start generation, return task ID immediately
- Do NOT poll or wait (generation takes 2-5 minutes)
- User checks status manually with `notebooklm artifact list`

Rationale: Keeps conversation flowing, enables parallel operations, avoids blocking.

### Error Handling

On failure, offer user a choice:
1. Retry the operation
2. Skip and continue
3. Investigate the error

### Distribution Model

**Hybrid approach**:
- Skill source lives in repo at `skills/notebooklm/SKILL.md`
- CLI command `notebooklm skill install` copies to `~/.claude/skills/`
- Version embedded in installed skill for mismatch detection

Benefits:
- Single source of truth (skill versioned with CLI)
- Easy installation: `pip install notebooklm-client && notebooklm skill install`
- Automatic upgrade detection

## Implementation

### Files Created

| File | Purpose |
|------|---------|
| `skills/notebooklm/SKILL.md` | The skill definition |
| `src/notebooklm/cli/skill.py` | CLI commands for skill management |

### CLI Commands

```bash
notebooklm skill install    # Install/update skill to ~/.claude/skills/
notebooklm skill status     # Check installation and version
notebooklm skill uninstall  # Remove skill
notebooklm skill show       # Display skill content
```

### Skill Content

The skill includes:
- Prerequisites (authentication)
- Autonomy rules
- Quick reference table
- Generation types with downloadable status
- Common workflows (research→podcast, document analysis, bulk import)
- Error handling decision tree
- Known limitations (rate limiting)

## User Experience

### Installation Flow

```bash
pip install notebooklm-client
notebooklm login              # Authenticate first
notebooklm skill install      # One command to enable skill
```

### Usage Examples

```
User: Create a podcast about quantum computing
Claude: [Activates notebooklm skill]
        Creating notebook 'Research: quantum computing'...
        What sources should I add? URLs, files, or should I search?
```

```
User: /notebooklm list
Claude: [Runs notebooklm list automatically]
        Found 3 notebooks:
        - abc123: Research: AI
        - def456: Project Notes
        - ghi789: Book Club
```

## Alternatives Considered

### Autonomy Models

1. **Fully autonomous** - Rejected: Too much risk of unintended actions
2. **Step-by-step** - Rejected: Too slow for simple operations
3. **Checkpoint-based** - Similar to chosen, but less granular

### Distribution Models

1. **Manual installation** - Rejected: Too error-prone
2. **Repo-only** - Rejected: Only works in repo directory
3. **Marketplace** - Future option when Claude skills marketplace exists

### Long Operation Handling

1. **Background with check-in** - Rejected: Clutters conversation with status updates
2. **Background with notification** - Considered but adds complexity
3. **User controls** - Adds friction for common case

## Future Enhancements

1. **Auto-install prompt**: During `notebooklm login`, offer to install skill
2. **Skill marketplace**: Publish when Claude Code marketplace is available
3. **Workflow templates**: Pre-built complex workflows as skill extensions
