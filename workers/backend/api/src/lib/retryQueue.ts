export function handleMessageFailure<T>(
  message: Message<T>,
  error: unknown,
  queueName: string
): void {
  const delaySeconds = 4 ** (message.attempts - 1); // 1, 4, 16

  if (message.attempts >= 3) {
    const body = message.body as Record<string, unknown>;
    console.error(JSON.stringify({
      queue: queueName,
      message_id: message.id,
      type: body.type ?? 'unknown',
      payload: body,
      error: error instanceof Error ? error.message : String(error),
      failed_at: new Date().toISOString(),
    }));
  }

  message.retry({ delaySeconds });
}
