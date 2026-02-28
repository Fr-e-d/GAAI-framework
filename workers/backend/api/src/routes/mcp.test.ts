import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleMcp } from './mcp';
import type { Env } from '../types/env';

// Mock agentAuth to control auth results
vi.mock('../middleware/agentAuth', () => ({
  agentAuth: vi.fn(),
}));

// Mock agent handlers
vi.mock('./agent', () => ({
  handleAgentExtract: vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ requirements: {}, ready_to_match: true }), { status: 200 })
  ),
  handleAgentMatch: vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ project_id: 'proj-1', computed: 1, top_matches: [] }), { status: 200 })
  ),
  handleAgentRevealRequest: vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ match_id: 'match-1', status: 'pending' }), { status: 200 })
  ),
  handleAgentBookingRequest: vi.fn().mockResolvedValue(
    new Response(JSON.stringify({ match_id: 'match-1', status: 'booking_email_sent' }), { status: 200 })
  ),
}));

const mockCtx = { waitUntil: vi.fn(), passThroughOnException: vi.fn() } as unknown as ExecutionContext;

const mockEnv = {
  SESSIONS: {} as KVNamespace,
  AGENT_API_KEY_SECRET: 'test-agent-secret',
} as unknown as Env;

const VALID_AUTH = {
  prospect_id: 'prospect-uuid',
  key_id: 'key-id',
  key_hash: 'a'.repeat(64),
};

function makeMcpRequest(body: unknown, withAuth = true): Request {
  return new Request('https://test.workers.dev/mcp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(withAuth ? { Authorization: 'Bearer ' + 'a'.repeat(64) } : {}) },
    body: JSON.stringify(body),
  });
}

describe('handleMcp', () => {
  beforeEach(async () => {
    const { agentAuth } = await import('../middleware/agentAuth');
    vi.mocked(agentAuth).mockResolvedValue(VALID_AUTH);
  });

  it('returns auth error for unauthenticated request', async () => {
    const { agentAuth } = await import('../middleware/agentAuth');
    vi.mocked(agentAuth).mockResolvedValue({
      response: new Response(JSON.stringify({ error: 'missing_api_key' }), { status: 401 }),
    });

    const request = makeMcpRequest({ jsonrpc: '2.0', id: 1, method: 'initialize' }, false);
    const response = await handleMcp(request, mockEnv, mockCtx);
    const body = await response.json() as { error: { code: number } };
    expect(body.error).toBeTruthy();
    expect(body.error.code).toBe(-32001);
  });

  it('returns PARSE_ERROR for invalid JSON', async () => {
    const request = new Request('https://test.workers.dev/mcp', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + 'a'.repeat(64) },
      body: 'not-json',
    });
    const response = await handleMcp(request, mockEnv, mockCtx);
    const body = await response.json() as { error: { code: number } };
    expect(body.error.code).toBe(-32700);
  });

  it('handles initialize method', async () => {
    const request = makeMcpRequest({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} });
    const response = await handleMcp(request, mockEnv, mockCtx);
    expect(response.status).toBe(200);
    const body = await response.json() as { result: { serverInfo: { name: string } } };
    expect(body.result.serverInfo.name).toBe('callibrate-mcp');
  });

  it('handles tools/list method', async () => {
    const request = makeMcpRequest({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
    const response = await handleMcp(request, mockEnv, mockCtx);
    const body = await response.json() as { result: { tools: unknown[] } };
    expect(Array.isArray(body.result.tools)).toBe(true);
    expect(body.result.tools.length).toBe(4);
  });

  it('returns method_not_found for unknown methods', async () => {
    const request = makeMcpRequest({ jsonrpc: '2.0', id: 3, method: 'unknown/method' });
    const response = await handleMcp(request, mockEnv, mockCtx);
    const body = await response.json() as { error: { code: number } };
    expect(body.error.code).toBe(-32601);
  });

  it('dispatches callibrate_describe_project tool call', async () => {
    const request = makeMcpRequest({
      jsonrpc: '2.0',
      id: 4,
      method: 'tools/call',
      params: { name: 'callibrate_describe_project', arguments: { text: 'I need n8n automation' } },
    });
    const response = await handleMcp(request, mockEnv, mockCtx);
    const body = await response.json() as { result: { content: { type: string; text: string }[] } };
    expect(body.result.content).toHaveLength(1);
    const firstContent = body.result.content[0]!;
    expect(firstContent.type).toBe('text');
    const toolResult = JSON.parse(firstContent.text) as Record<string, unknown>;
    expect(toolResult['ready_to_match']).toBe(true);
  });

  it('dispatches callibrate_find_experts tool call', async () => {
    const request = makeMcpRequest({
      jsonrpc: '2.0',
      id: 5,
      method: 'tools/call',
      params: { name: 'callibrate_find_experts', arguments: { requirements: { challenge: 'test' } } },
    });
    const response = await handleMcp(request, mockEnv, mockCtx);
    const body = await response.json() as { result: { content: unknown[] } };
    expect(body.result.content).toHaveLength(1);
  });

  it('returns error content for unknown tool', async () => {
    const request = makeMcpRequest({
      jsonrpc: '2.0',
      id: 6,
      method: 'tools/call',
      params: { name: 'unknown_tool', arguments: {} },
    });
    const response = await handleMcp(request, mockEnv, mockCtx);
    const body = await response.json() as { result: { content: { text: string }[]; isError: boolean } };
    expect(body.result.isError).toBe(true);
    const toolResult = JSON.parse(body.result.content[0]!.text) as { error: string };
    expect(toolResult.error).toContain('Unknown tool');
  });
});
