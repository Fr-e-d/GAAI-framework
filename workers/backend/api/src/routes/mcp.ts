// E06S43: MCP (Model Context Protocol) JSON-RPC 2.0 server over HTTP
// Endpoint: POST /mcp
// Authentication: Bearer {agent-api-key} — same key as /api/agent/* endpoints
// Protocol: MCP 2024-11-05 spec (https://spec.modelcontextprotocol.io)
//
// Supported methods:
//   initialize            — returns server info and capabilities
//   tools/list            — returns available tools
//   tools/call            — call a tool by name
//
// Tools:
//   callibrate_describe_project   → handleAgentExtract
//   callibrate_find_experts        → handleAgentMatch
//   callibrate_request_reveal     → handleAgentRevealRequest
//   callibrate_request_booking    → handleAgentBookingRequest

import type { Env } from '../types/env';
import { agentAuth } from '../middleware/agentAuth';
import {
  handleAgentExtract,
  handleAgentMatch,
  handleAgentRevealRequest,
  handleAgentBookingRequest,
  type AgentCtx,
} from './agent';

// ── MCP Types ─────────────────────────────────────────────────────────────────

interface JsonRpcRequest {
  jsonrpc: '2.0';
  id: string | number | null;
  method: string;
  params?: unknown;
}

interface JsonRpcSuccess {
  jsonrpc: '2.0';
  id: string | number | null;
  result: unknown;
}

interface JsonRpcError {
  jsonrpc: '2.0';
  id: string | number | null;
  error: { code: number; message: string; data?: unknown };
}

type JsonRpcResponse = JsonRpcSuccess | JsonRpcError;

// JSON-RPC error codes
const PARSE_ERROR = -32700;
const INVALID_REQUEST = -32600;
const METHOD_NOT_FOUND = -32601;
const INVALID_PARAMS = -32602;
const INTERNAL_ERROR = -32603;

// ── Tool definitions ──────────────────────────────────────────────────────────

const TOOLS = [
  {
    name: 'callibrate_describe_project',
    description: 'Extract structured requirements from a freetext project description. Returns requirements, confidence scores, and confirmation questions for low-confidence fields.',
    inputSchema: {
      type: 'object',
      properties: {
        text: {
          type: 'string',
          description: 'Freetext description of the project (max 2000 chars)',
        },
        satellite_id: {
          type: 'string',
          description: 'Optional satellite ID for vertical-specific context',
        },
      },
      required: ['text'],
    },
  },
  {
    name: 'callibrate_find_experts',
    description: 'Run matching to find relevant experts for extracted requirements. Returns anonymized match results with match IDs and scores.',
    inputSchema: {
      type: 'object',
      properties: {
        requirements: {
          type: 'object',
          description: 'Extracted requirements object from callibrate_describe_project',
        },
        satellite_id: {
          type: 'string',
          description: 'Optional satellite ID for vertical-specific weights',
        },
        freetext: {
          type: 'string',
          description: 'Original freetext for storage purposes',
        },
      },
      required: ['requirements'],
    },
  },
  {
    name: 'callibrate_request_reveal',
    description: 'Request human confirmation to reveal an expert profile. Sends a confirmation email to the prospect. The prospect must confirm before the expert\'s contact details are accessible.',
    inputSchema: {
      type: 'object',
      properties: {
        match_id: {
          type: 'string',
          description: 'Match ID from callibrate_find_experts',
        },
        project_summary: {
          type: 'string',
          description: 'Brief summary of the project (shown in confirmation email)',
        },
      },
      required: ['match_id'],
    },
  },
  {
    name: 'callibrate_request_booking',
    description: 'Request a meeting booking with a revealed expert. Sends a booking email with a scheduling link to the prospect. Expert must have been revealed first via callibrate_request_reveal.',
    inputSchema: {
      type: 'object',
      properties: {
        match_id: {
          type: 'string',
          description: 'Match ID of a confirmed-reveal expert',
        },
        project_summary: {
          type: 'string',
          description: 'Brief summary of the project (shown in booking email)',
        },
      },
      required: ['match_id'],
    },
  },
];

// ── Main MCP handler ──────────────────────────────────────────────────────────

export async function handleMcp(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  // Authenticate via agent API key
  const authResult = await agentAuth(request, env, ctx);
  if (authResult.response) {
    // Return JSON-RPC error for auth failure (not standard HTTP 401 in MCP context)
    return rpcErrorResponse(null, -32001, 'Authentication failed', authResult.response.status);
  }

  const agentCtx: AgentCtx = {
    prospect_id: authResult.prospect_id,
    key_id: authResult.key_id,
    key_hash: authResult.key_hash,
  };

  // Parse JSON-RPC request
  let rpcReq: JsonRpcRequest;
  try {
    rpcReq = await request.json() as JsonRpcRequest;
  } catch {
    return rpcErrorResponse(null, PARSE_ERROR, 'Parse error');
  }

  if (!rpcReq || typeof rpcReq !== 'object' || rpcReq.jsonrpc !== '2.0' || typeof rpcReq.method !== 'string') {
    return rpcErrorResponse(rpcReq?.id ?? null, INVALID_REQUEST, 'Invalid Request');
  }

  const { id, method, params } = rpcReq;

  try {
    switch (method) {
      case 'initialize':
        return rpcSuccessResponse(id, {
          protocolVersion: '2024-11-05',
          serverInfo: {
            name: 'callibrate-mcp',
            version: '1.0.0',
          },
          capabilities: {
            tools: {},
          },
        });

      case 'tools/list':
        return rpcSuccessResponse(id, { tools: TOOLS });

      case 'tools/call': {
        const p = params as { name?: string; arguments?: Record<string, unknown> } | null;
        if (!p || typeof p.name !== 'string') {
          return rpcErrorResponse(id, INVALID_PARAMS, 'Missing tool name');
        }

        const toolArgs = p.arguments ?? {};
        const toolResult = await callTool(p.name, toolArgs, request, env, ctx, agentCtx);
        return rpcSuccessResponse(id, toolResult);
      }

      default:
        return rpcErrorResponse(id, METHOD_NOT_FOUND, `Method not found: ${method}`);
    }
  } catch (err) {
    console.error('[mcp] handler error:', err);
    return rpcErrorResponse(id, INTERNAL_ERROR, 'Internal server error');
  }
}

// ── Tool dispatcher ───────────────────────────────────────────────────────────

async function callTool(
  toolName: string,
  args: Record<string, unknown>,
  originalRequest: Request,
  env: Env,
  ctx: ExecutionContext,
  agent: AgentCtx,
): Promise<{ content: { type: 'text'; text: string }[]; isError?: boolean }> {
  // Build a fake internal Request with the tool arguments as JSON body
  function makeFakeRequest(body: Record<string, unknown>): Request {
    return new Request('https://mcp-internal/tool', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  }

  let response: Response;

  switch (toolName) {
    case 'callibrate_describe_project':
      response = await handleAgentExtract(makeFakeRequest(args), env, ctx, agent);
      break;

    case 'callibrate_find_experts':
      response = await handleAgentMatch(makeFakeRequest(args), env, ctx, agent);
      break;

    case 'callibrate_request_reveal':
      response = await handleAgentRevealRequest(makeFakeRequest(args), env, ctx, agent);
      break;

    case 'callibrate_request_booking':
      response = await handleAgentBookingRequest(makeFakeRequest(args), env, ctx, agent);
      break;

    default:
      return {
        content: [{ type: 'text', text: JSON.stringify({ error: `Unknown tool: ${toolName}` }) }],
        isError: true,
      };
  }

  const resultBody = await response.text();
  const isError = !response.ok;

  return {
    content: [{ type: 'text', text: resultBody }],
    ...(isError ? { isError: true } : {}),
  };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function rpcSuccessResponse(id: string | number | null, result: unknown): Response {
  const body: JsonRpcSuccess = { jsonrpc: '2.0', id, result };
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

function rpcErrorResponse(
  id: string | number | null,
  code: number,
  message: string,
  httpStatus = 200,
): Response {
  const body: JsonRpcError = { jsonrpc: '2.0', id, error: { code, message } };
  return new Response(JSON.stringify(body), {
    status: httpStatus === 401 ? 200 : httpStatus, // MCP errors return 200 with error in body
    headers: { 'Content-Type': 'application/json' },
  });
}
