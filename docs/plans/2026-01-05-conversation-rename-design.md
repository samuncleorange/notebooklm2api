# Conversation Service Rename Design

## Overview

Rename `query.py` to `conversation.py` and improve naming throughout the codebase to better reflect the conversational nature of the chat functionality.

## Motivation

- "query" sounds database-like, not conversational
- CLI command `notebooklm ask` is more natural than `notebooklm query`
- "Conversation" better describes the domain concept (chat history, message state)
- "Ask" is the user action, "Conversation" is the service managing it

## Design Decisions

1. **Full rename** - Clean break, no backward compatibility (v0.1.0)
2. **`ask` for CLI** - Natural language: `notebooklm ask "What are the themes?"`
3. **`ConversationService` internally** - Describes what it manages
4. **Local cache management** - Server-side clear RPC not yet discovered

## File Changes

### Renames

| Before | After |
|--------|-------|
| `src/notebooklm/services/query.py` | `src/notebooklm/services/conversation.py` |
| `tests/unit/test_query.py` | `tests/unit/test_conversation.py` |

### API Client (api_client.py)

```python
# Method renames
query() → ask()
_parse_query_response() → _parse_ask_response()
```

### Services Layer (conversation.py)

```python
from dataclasses import dataclass
from typing import Any, Optional, List, TYPE_CHECKING

if TYPE_CHECKING:
    from ..api_client import NotebookLMClient


@dataclass
class ConversationTurn:
    """Represents a single turn in a conversation."""
    query: str
    answer: str
    turn_number: int


@dataclass
class AskResult:
    """Result of asking the notebook a question."""
    answer: str
    conversation_id: str
    turn_number: int
    is_follow_up: bool
    raw_response: str = ""


class ConversationService:
    """Service for conversational interactions with notebooks."""

    def __init__(self, client: "NotebookLMClient"):
        self._client = client

    async def ask(
        self,
        notebook_id: str,
        question: str,
        source_ids: Optional[List[str]] = None,
        conversation_id: Optional[str] = None
    ) -> AskResult:
        """Ask the notebook a question.

        Args:
            notebook_id: The notebook to query
            question: The question to ask
            source_ids: Limit to specific sources (None = all sources)
            conversation_id: Continue existing conversation (None = new)

        Returns:
            AskResult with answer and conversation metadata
        """
        result = await self._client.ask(
            notebook_id, question, source_ids, conversation_id
        )
        return AskResult(
            answer=result["answer"],
            conversation_id=result["conversation_id"],
            turn_number=result["turn_number"],
            is_follow_up=result["is_follow_up"],
            raw_response=result.get("raw_response", "")
        )

    async def get_history(self, notebook_id: str, limit: int = 20) -> Any:
        """Get conversation history from server.

        Returns the last N conversation turns stored server-side.
        """
        return await self._client.get_conversation_history(notebook_id, limit)

    def get_cached_turns(self, conversation_id: str) -> List[ConversationTurn]:
        """Get locally cached conversation turns.

        Returns turns from the client's local cache (this session only).
        """
        turns_data = self._client._conversation_cache.get(conversation_id, [])
        return [
            ConversationTurn(
                query=turn["query"],
                answer=turn["answer"],
                turn_number=turn["turn_number"]
            )
            for turn in turns_data
        ]

    def clear_cache(self, conversation_id: Optional[str] = None) -> bool:
        """Clear local conversation cache.

        Args:
            conversation_id: Clear specific conversation (None = clear all)

        Returns:
            True if cleared successfully
        """
        if conversation_id:
            if conversation_id in self._client._conversation_cache:
                del self._client._conversation_cache[conversation_id]
                return True
            return False
        else:
            self._client._conversation_cache.clear()
            return True

    async def delete_history(self, notebook_id: str) -> bool:
        """Delete conversation history from server.

        Args:
            notebook_id: The notebook whose history to delete

        Returns:
            True if deleted successfully

        Note:
            TODO: Implement after discovering DELETE_CONVERSATION_HISTORY RPC
            from UI vertical menu > delete history option.
        """
        # TODO: await self._client.delete_conversation_history(notebook_id)
        raise NotImplementedError("Server-side history deletion not yet implemented")
```

### Services __init__.py

```python
from .conversation import ConversationService, AskResult, ConversationTurn

__all__ = [
    "NotebookService",
    "Notebook",
    "SourceService",
    "Source",
    "ArtifactService",
    "Artifact",
    "ArtifactStatus",
    "ConversationService",
    "AskResult",
    "ConversationTurn",
]
```

### CLI Commands (notebooklm_cli.py)

**Remove:**
```
notebooklm query
notebooklm notebook query
```

**Add:**
```bash
# Primary ask command
notebooklm ask "What are the main themes?"
notebooklm ask "Tell me more" -c <conversation_id>

# Grouped version
notebooklm notebook ask <notebook_id> "question"

# History management
notebooklm history                    # Show server history
notebooklm history --cached           # Show local cached turns
notebooklm history --clear            # Clear local cache
notebooklm history --clear -c <id>    # Clear specific conversation
```

### RPC Types (types.py)

```python
# Conversation
GET_CONVERSATION_HISTORY = "hPTbtc"
# TODO: DELETE_CONVERSATION_HISTORY = "???" - Discover from UI (vertical menu > delete history)
# TODO: GET_CHAT_CONFIG = "???" - Get current chat configuration
# TODO: SET_CHAT_CONFIG = "???" - Set chat configuration
```

## Chat Configuration (TODO)

The NotebookLM UI has a "Configure Chat" dialog with these options:

### Conversational Style/Role
| Option | Description |
|--------|-------------|
| `Default` | Best for general purpose research and brainstorming tasks |
| `Learning Guide` | Educational focus (tutoring mode) |
| `Custom` | User-defined custom instructions |

### Response Length
| Option | Description |
|--------|-------------|
| `Default` | Standard response length |
| `Longer` | More detailed responses |
| `Shorter` | Concise responses |

### Future Enums (to be added after RPC discovery)

```python
class ChatStyle(int, Enum):
    """Chat conversational style options."""
    DEFAULT = 1      # General research/brainstorming
    LEARNING_GUIDE = 2  # Educational/tutoring
    CUSTOM = 3       # Custom instructions

class ResponseLength(int, Enum):
    """Chat response length options."""
    DEFAULT = 1
    LONGER = 2
    SHORTER = 3
```

### Future CLI Commands

```bash
# Configure chat settings
notebooklm chat config                     # Show current config
notebooklm chat config --style learning    # Set learning guide mode
notebooklm chat config --style custom "Act as a debate partner"
notebooklm chat config --length longer     # Set longer responses
```

### Future Service Methods

```python
class ConversationService:
    # ... existing methods ...

    async def get_config(self, notebook_id: str) -> ChatConfig:
        """Get chat configuration for a notebook."""
        # TODO: Implement after RPC discovery
        pass

    async def set_config(
        self,
        notebook_id: str,
        style: Optional[ChatStyle] = None,
        response_length: Optional[ResponseLength] = None,
        custom_instructions: Optional[str] = None
    ) -> ChatConfig:
        """Set chat configuration for a notebook."""
        # TODO: Implement after RPC discovery
        pass
```

## CLI Usage Examples

```bash
# Set context and ask questions
notebooklm use nb123
notebooklm ask "What are the key findings?"
# Returns: Answer + conversation_id

# Continue conversation
notebooklm ask "Can you elaborate on point 2?" -c abc-123-def

# View history
notebooklm history
notebooklm history --limit 5

# Clear local cache
notebooklm history --clear
```

## Test Updates

Rename `tests/unit/test_query.py` to `tests/unit/test_conversation.py` and update:

```python
# Before
from notebooklm.services.query import QueryResult, ConversationTurn

# After
from notebooklm.services.conversation import AskResult, ConversationTurn
```

## Implementation Checklist

- [ ] Rename `query.py` → `conversation.py`
- [ ] Create `ConversationService` class
- [ ] Rename `QueryResult` → `AskResult`
- [ ] Update `services/__init__.py` exports
- [ ] Rename `client.query()` → `client.ask()` in api_client.py
- [ ] Rename `_parse_query_response()` → `_parse_ask_response()`
- [ ] Update CLI: remove `query` commands, add `ask` commands
- [ ] Add `history` CLI command
- [ ] Rename test file and update imports
- [ ] Update any documentation references
- [ ] Add TODO comment for CLEAR_CONVERSATION_HISTORY RPC

## References

- jacob-bd/notebooklm-mcp: Local cache management pattern
- tmc/nlm: RPC method IDs reference
- Neither has server-side conversation clear - confirms our TODO approach
