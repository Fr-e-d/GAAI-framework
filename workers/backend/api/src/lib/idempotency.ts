export async function isAlreadyProcessed(
  kv: KVNamespace,
  queue: string,
  messageId: string
): Promise<boolean> {
  const key = `idem:${queue}:${messageId}`;
  const val = await kv.get(key);
  return val !== null;
}

export async function markProcessed(
  kv: KVNamespace,
  queue: string,
  messageId: string
): Promise<void> {
  const key = `idem:${queue}:${messageId}`;
  await kv.put(key, '1', { expirationTtl: 86400 });
}
