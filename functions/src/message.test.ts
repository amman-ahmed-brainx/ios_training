import { buildStatusMessages, isInvalidTokenError, parseTask, recipients, TaskSnapshot } from './message';

const before: TaskSnapshot = { title: 'Report', status: 'todo', memberIds: ['ada', 'grace', 'alan'], updatedBy: 'ada' };
const after: TaskSnapshot = { ...before, status: 'done', updatedBy: 'grace' };
const tokens = { ada: ['ada-phone'], grace: ['grace-phone'], alan: ['alan-phone', 'alan-ipad'] };

test('notifies every member except the updater, on every device', () => {
  const messages = buildStatusMessages('t1', before, after, 'Grace', tokens);
  expect(messages.map((m) => m.token).sort()).toEqual(['ada-phone', 'alan-ipad', 'alan-phone']);
});

test('builds title, status body, taskId data and apns fields', () => {
  const [message] = buildStatusMessages('t1', before, after, 'Grace', { ada: ['ada-phone'] });
  expect(message.notification).toEqual({ title: 'Grace updated Report', body: 'Status: Done' });
  expect(message.data).toEqual({ taskId: 't1' });
  expect(message.apns.payload.aps).toEqual({ sound: 'default', 'thread-id': 't1' });
});

test('sends nothing when the status did not change', () => {
  expect(buildStatusMessages('t1', before, { ...before, title: 'Renamed', updatedBy: 'grace' }, 'Grace', tokens)).toEqual([]);
});

test('recipients exclude the updater', () => {
  expect(recipients(after)).toEqual(['ada', 'alan']);
});

test('recognises permanently invalid tokens', () => {
  expect(isInvalidTokenError('messaging/registration-token-not-registered')).toBe(true);
  expect(isInvalidTokenError('messaging/internal-error')).toBe(false);
});

test('rejects malformed task documents', () => {
  expect(parseTask(undefined)).toBeUndefined();
  expect(parseTask({ title: 'x', status: 'done', memberIds: 'ada', updatedBy: 'ada' })).toBeUndefined();
  expect(parseTask({ title: 'x', status: 'done', memberIds: ['ada'], updatedBy: 'ada', extra: 1 }))
    .toEqual({ title: 'x', status: 'done', memberIds: ['ada'], updatedBy: 'ada' });
});
