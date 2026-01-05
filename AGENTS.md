# AGENTS.md

Guidelines for AI agents working on `notebooklm-client`.

## Quick Reference

```bash
# Activate virtual environment FIRST
source .venv/bin/activate

# Run all tests (excludes e2e by default)
pytest

# Run a single test file
pytest tests/unit/test_decoder.py

# Run a single test function
pytest tests/unit/test_decoder.py::TestDecodeResponse::test_full_decode_pipeline

# Run a single test class
pytest tests/unit/test_decoder.py::TestDecodeResponse

# Run with verbose output
pytest -v tests/unit/test_decoder.py

# Run with coverage
pytest --cov

# Run e2e tests (requires auth)
pytest tests/e2e -m e2e

# Run slow tests (audio/video generation)
pytest -m slow

# Install in dev mode
pip install -e ".[all]"
playwright install chromium
```

## Architecture Overview

Three-layer design:

```
Services Layer (src/notebooklm/services/)
  └─> Client Layer (src/notebooklm/api_client.py)
        └─> RPC Layer (src/notebooklm/rpc/)
```

- **Services**: High-level wrappers with typed dataclasses (Notebook, Source)
- **Client**: `NotebookLMClient` async class, `_rpc_call()` for batchexecute
- **RPC**: `types.py` (method IDs), `encoder.py`, `decoder.py`

**Critical**: RPC method IDs in `types.py` are reverse-engineered. Google can change them.

## Code Style Guidelines

### Type Annotations (Python 3.9+)
```python
def process(items: list[str]) -> dict[str, Any]: ...
async def query(notebook_id: str, source_ids: Optional[list[str]] = None): ...

# Use TYPE_CHECKING for circular imports
from typing import TYPE_CHECKING
if TYPE_CHECKING:
    from ..api_client import NotebookLMClient
```

### Async Patterns
```python
# All client methods are async - use context managers
async with NotebookLMClient(auth) as client:
    notebooks = await client.list_notebooks()

# Or factory method
async with await NotebookLMClient.from_storage() as client: ...
```

### Data Structures
```python
@dataclass
class Notebook:
    id: str
    title: str
    created_at: Optional[datetime] = None
    
    @classmethod
    def from_api_response(cls, data: list[Any]) -> "Notebook": ...
```

### Enums for Constants
```python
class RPCMethod(str, Enum):
    LIST_NOTEBOOKS = "wXbhsf"

class AudioFormat(int, Enum):
    DEEP_DIVE = 1
```

### Error Handling
```python
class RPCError(Exception):
    def __init__(self, message: str, rpc_id: Optional[str] = None, code: Optional[Any] = None):
        self.rpc_id, self.code = rpc_id, code
        super().__init__(message)

raise RPCError(f"No result found for RPC ID: {rpc_id}", rpc_id=rpc_id)
raise ValueError(f"Invalid YouTube URL: {url}")  # For validation
```

### Docstrings
```python
def decode_response(raw_response: str, rpc_id: str, allow_null: bool = False) -> Any:
    """Complete decode pipeline: strip prefix -> parse chunks -> extract result.

    Args:
        raw_response: Raw response text from batchexecute
        rpc_id: RPC method ID to extract result for
        allow_null: If True, return None instead of raising when null

    Returns:
        Decoded result data

    Raises:
        RPCError: If RPC returned an error or result not found
    """
```

## Testing Patterns

```python
# Class-based for related tests
class TestDecodeResponse:
    def test_full_decode_pipeline(self): ...

# Markers
@pytest.mark.e2e      # End-to-end (requires auth)
@pytest.mark.slow     # Long-running (audio/video)
@pytest.mark.asyncio  # Async tests

# Async tests
@pytest.mark.asyncio
async def test_list_notebooks(self, client):
    notebooks = await client.list_notebooks()
    assert isinstance(notebooks, list)
```

## Adding New RPC Methods

1. Capture network traffic in DevTools (filter `batchexecute`)
2. Find method ID from `rpcids` parameter
3. Add to `types.py`: `NEW_METHOD = "XyZ123"`
4. Implement in `api_client.py`:
   ```python
   async def new_method(self, notebook_id: str) -> Any:
       params = [notebook_id, ...]  # Match captured structure
       return await self._rpc_call(RPCMethod.NEW_METHOD, params, allow_null=True)
   ```
5. Add tests in `tests/unit/` and optionally `tests/e2e/`

## Common Pitfalls

| Issue | Solution |
|-------|----------|
| `RuntimeError: Client not initialized` | Use `async with` context manager |
| `RPCError: No result found` | Check if `allow_null=True` needed, or API changed |
| `ValueError: Missing required cookies` | Run `notebooklm login` |
| Nested list parsing fails | RPC params are position-sensitive |
| Tests fail with auth errors | E2E tests need real auth; unit tests should mock |

## Key Constants

- **Default storage**: `~/.notebooklm/storage_state.json`
- **Batchexecute URL**: `https://notebooklm.google.com/_/LabsTailwindUi/data/batchexecute`

## Do NOT

- Suppress type errors with `# type: ignore`
- Commit `.env` files or credentials
- Add dependencies without updating `pyproject.toml`
- Change RPC method IDs without verifying via network capture
- Delete or modify e2e tests without running them
