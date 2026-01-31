#!/usr/bin/env python3
"""
OpenAI-compatible API server for NotebookLM.

This server provides an OpenAI-compatible chat completion endpoint that uses
NotebookLM's ask functionality under the hood.

Environment Variables:
    NOTEBOOKLM_AUTH_JSON: Playwright storage state JSON for authentication
    NOTEBOOKLM_NOTEBOOK_ID: Default notebook ID to use for queries
    API_KEY: Optional API key for authentication (default: none)
    PORT: Server port (default: 8000)
    HOST: Server host (default: 0.0.0.0)

Usage:
    # Set environment variables
    export NOTEBOOKLM_AUTH_JSON='{"cookies":[...]}'
    export NOTEBOOKLM_NOTEBOOK_ID='your-notebook-id'
    export API_KEY='your-secret-key'
    
    # Run server
    python api_server.py
    
    # Or with Docker
    docker run -e NOTEBOOKLM_AUTH_JSON='...' -e NOTEBOOKLM_NOTEBOOK_ID='...' -p 8000:8000 notebooklm2api
"""

import asyncio
import json
import logging
import os
import time
import uuid
from typing import Any, AsyncGenerator, Optional

from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel, Field
import uvicorn

from notebooklm import NotebookLMClient
from notebooklm.auth import AuthTokens

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
API_KEY = os.getenv("API_KEY", "")  # Empty string means no auth required
DEFAULT_NOTEBOOK_ID = os.getenv("NOTEBOOKLM_NOTEBOOK_ID", "")
PORT = int(os.getenv("PORT", "8000"))
HOST = os.getenv("HOST", "0.0.0.0")

app = FastAPI(
    title="NotebookLM API",
    description="OpenAI-compatible API for NotebookLM",
    version="1.0.0"
)

# OpenAI-compatible request/response models
class Message(BaseModel):
    role: str
    content: str

class ChatCompletionRequest(BaseModel):
    model: str = Field(default="notebooklm", description="Model name (ignored, always uses NotebookLM)")
    messages: list[Message]
    stream: bool = False
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None
    notebook_id: Optional[str] = Field(default=None, description="NotebookLM notebook ID to query")

class ChatCompletionChoice(BaseModel):
    index: int
    message: Message
    finish_reason: str

class Usage(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int

class ChatCompletionResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: list[ChatCompletionChoice]
    usage: Usage

class ChatCompletionChunk(BaseModel):
    id: str
    object: str = "chat.completion.chunk"
    created: int
    model: str
    choices: list[dict]

class ErrorResponse(BaseModel):
    error: dict[str, Any]


def verify_api_key(authorization: Optional[str] = Header(None)) -> bool:
    """Verify API key if configured."""
    if not API_KEY:
        return True  # No auth required
    
    if not authorization:
        return False
    
    # Support both "Bearer <key>" and raw key
    if authorization.startswith("Bearer "):
        token = authorization[7:]
    else:
        token = authorization
    
    return token == API_KEY


async def get_notebooklm_client() -> NotebookLMClient:
    """Create and return an authenticated NotebookLM client."""
    try:
        auth = await AuthTokens.from_storage()
        return NotebookLMClient(auth)
    except Exception as e:
        logger.error(f"Failed to create NotebookLM client: {e}")
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "message": f"Authentication failed: {str(e)}",
                    "type": "authentication_error",
                    "code": "auth_failed"
                }
            }
        )


def extract_user_query(messages: list[Message]) -> str:
    """Extract the user's query from the message list."""
    # Get the last user message
    for message in reversed(messages):
        if message.role == "user":
            return message.content
    
    raise HTTPException(
        status_code=400,
        detail={
            "error": {
                "message": "No user message found in request",
                "type": "invalid_request_error",
                "code": "no_user_message"
            }
        }
    )


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}


@app.get("/v1/models")
async def list_models(authorization: Optional[str] = Header(None)):
    """List available models (OpenAI-compatible)."""
    if not verify_api_key(authorization):
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    return {
        "object": "list",
        "data": [
            {
                "id": "notebooklm",
                "object": "model",
                "created": int(time.time()),
                "owned_by": "notebooklm",
                "permission": [],
                "root": "notebooklm",
                "parent": None,
            }
        ]
    }


@app.post("/v1/chat/completions")
async def chat_completions(
    request: ChatCompletionRequest,
    authorization: Optional[str] = Header(None)
):
    """
    OpenAI-compatible chat completion endpoint.
    
    This endpoint accepts OpenAI-style chat completion requests and uses
    NotebookLM's ask functionality to generate responses.
    """
    if not verify_api_key(authorization):
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    # Determine notebook ID
    notebook_id = request.notebook_id or DEFAULT_NOTEBOOK_ID
    if not notebook_id:
        raise HTTPException(
            status_code=400,
            detail={
                "error": {
                    "message": "notebook_id is required (set in request or NOTEBOOKLM_NOTEBOOK_ID env var)",
                    "type": "invalid_request_error",
                    "code": "missing_notebook_id"
                }
            }
        )
    
    # Extract user query
    query = extract_user_query(request.messages)
    logger.info(f"Processing query for notebook {notebook_id}: {query[:100]}...")
    
    # Handle streaming vs non-streaming
    if request.stream:
        return StreamingResponse(
            stream_chat_completion(notebook_id, query, request.model),
            media_type="text/event-stream"
        )
    else:
        return await non_stream_chat_completion(notebook_id, query, request.model)


async def non_stream_chat_completion(
    notebook_id: str,
    query: str,
    model: str
) -> ChatCompletionResponse:
    """Handle non-streaming chat completion."""
    try:
        async with await get_notebooklm_client() as client:
            # Ask NotebookLM
            result = await client.chat.ask(notebook_id, query)
            
            # Create OpenAI-compatible response
            response = ChatCompletionResponse(
                id=f"chatcmpl-{uuid.uuid4().hex[:8]}",
                created=int(time.time()),
                model=model,
                choices=[
                    ChatCompletionChoice(
                        index=0,
                        message=Message(role="assistant", content=result.answer),
                        finish_reason="stop"
                    )
                ],
                usage=Usage(
                    prompt_tokens=len(query.split()),  # Rough estimate
                    completion_tokens=len(result.answer.split()),  # Rough estimate
                    total_tokens=len(query.split()) + len(result.answer.split())
                )
            )
            
            logger.info(f"Successfully processed query for notebook {notebook_id}")
            return response
            
    except Exception as e:
        logger.error(f"Error processing query: {e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail={
                "error": {
                    "message": str(e),
                    "type": "server_error",
                    "code": "processing_failed"
                }
            }
        )


async def stream_chat_completion(
    notebook_id: str,
    query: str,
    model: str
) -> AsyncGenerator[str, None]:
    """Handle streaming chat completion."""
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:8]}"
    created = int(time.time())
    
    try:
        async with await get_notebooklm_client() as client:
            # Ask NotebookLM (non-streaming, but we'll simulate streaming)
            result = await client.chat.ask(notebook_id, query)
            
            # Split response into chunks for streaming
            words = result.answer.split()
            chunk_size = max(1, len(words) // 20)  # ~20 chunks
            
            for i in range(0, len(words), chunk_size):
                chunk_words = words[i:i + chunk_size]
                content = " ".join(chunk_words)
                if i > 0:
                    content = " " + content  # Add space between chunks
                
                chunk = ChatCompletionChunk(
                    id=completion_id,
                    created=created,
                    model=model,
                    choices=[
                        {
                            "index": 0,
                            "delta": {"content": content},
                            "finish_reason": None
                        }
                    ]
                )
                
                yield f"data: {chunk.model_dump_json()}\n\n"
                await asyncio.sleep(0.05)  # Small delay for streaming effect
            
            # Send final chunk
            final_chunk = ChatCompletionChunk(
                id=completion_id,
                created=created,
                model=model,
                choices=[
                    {
                        "index": 0,
                        "delta": {},
                        "finish_reason": "stop"
                    }
                ]
            )
            yield f"data: {final_chunk.model_dump_json()}\n\n"
            yield "data: [DONE]\n\n"
            
            logger.info(f"Successfully streamed response for notebook {notebook_id}")
            
    except Exception as e:
        logger.error(f"Error streaming response: {e}", exc_info=True)
        error_chunk = {
            "error": {
                "message": str(e),
                "type": "server_error",
                "code": "streaming_failed"
            }
        }
        yield f"data: {json.dumps(error_chunk)}\n\n"


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Handle HTTP exceptions in OpenAI-compatible format."""
    if isinstance(exc.detail, dict) and "error" in exc.detail:
        return JSONResponse(
            status_code=exc.status_code,
            content=exc.detail
        )
    
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "message": str(exc.detail),
                "type": "api_error",
                "code": f"http_{exc.status_code}"
            }
        }
    )


if __name__ == "__main__":
    # Validate configuration
    if not os.getenv("NOTEBOOKLM_AUTH_JSON"):
        logger.warning(
            "NOTEBOOKLM_AUTH_JSON not set. Make sure authentication is configured."
        )
    
    if not DEFAULT_NOTEBOOK_ID:
        logger.warning(
            "NOTEBOOKLM_NOTEBOOK_ID not set. Clients must provide notebook_id in requests."
        )
    
    logger.info(f"Starting NotebookLM API server on {HOST}:{PORT}")
    logger.info(f"API Key authentication: {'enabled' if API_KEY else 'disabled'}")
    logger.info(f"Default notebook ID: {DEFAULT_NOTEBOOK_ID or 'not set'}")
    
    uvicorn.run(app, host=HOST, port=PORT)
