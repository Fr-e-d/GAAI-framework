import { describe, it, expect } from 'vitest';
import { signBookingToken, verifyBookingToken } from './bookingToken';

const SECRET = 'test-secret-32-chars-minimum-ok!';

describe('bookingToken', () => {
  it('generates a valid confirm token', async () => {
    const token = await signBookingToken('booking-123', 'confirm', SECRET, 1800);
    expect(token).toMatch(/^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$/);
  });

  it('verifies a valid confirm token', async () => {
    const token = await signBookingToken('booking-123', 'confirm', SECRET, 1800);
    const result = await verifyBookingToken(token, 'booking-123', 'confirm', SECRET);
    expect(result).toBe('valid');
  });

  it('rejects a token used for wrong action', async () => {
    const token = await signBookingToken('booking-123', 'confirm', SECRET, 1800);
    const result = await verifyBookingToken(token, 'booking-123', 'cancel', SECRET);
    expect(result).toBe('invalid');
  });

  it('rejects a token for wrong booking_id', async () => {
    const token = await signBookingToken('booking-123', 'confirm', SECRET, 1800);
    const result = await verifyBookingToken(token, 'booking-456', 'confirm', SECRET);
    expect(result).toBe('invalid');
  });

  it('returns expired for an expired token', async () => {
    const token = await signBookingToken('booking-123', 'confirm', SECRET, -1); // already expired
    const result = await verifyBookingToken(token, 'booking-123', 'confirm', SECRET);
    expect(result).toBe('expired');
  });

  it('rejects a tampered token', async () => {
    const token = await signBookingToken('booking-123', 'confirm', SECRET, 1800);
    const parts = token.split('.');
    parts[1] = btoa(JSON.stringify({ booking_id: 'attacker', action: 'confirm', exp: 9999999999 })).replace(/=/g, '');
    const tampered = parts.join('.');
    const result = await verifyBookingToken(tampered, 'attacker', 'confirm', SECRET);
    expect(result).toBe('invalid');
  });

  it('generates expert-approve token with 24h TTL', async () => {
    const token = await signBookingToken('booking-123', 'expert-approve', SECRET, 86400);
    const result = await verifyBookingToken(token, 'booking-123', 'expert-approve', SECRET);
    expect(result).toBe('valid');
  });
});
