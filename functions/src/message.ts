/** Pure push-building logic for task updates, kept free of Firebase so it is unit-testable. */

export interface TaskSnapshot {
  title: string;
  status: string;
  memberIds: string[];
  updatedBy: string;
}

export interface PushMessage {
  token: string;
  notification: { title: string; body: string };
  data: { taskId: string };
  apns: { payload: { aps: { sound: string; 'thread-id': string } } };
}

const statusLabels: Record<string, string> = {
  todo: 'To Do',
  inProgress: 'In Progress',
  done: 'Done',
};

/** Validates a raw task document; returns undefined for anything malformed. */
export function parseTask(data: unknown): TaskSnapshot | undefined {
  if (typeof data !== 'object' || data === null) return undefined;
  const raw = data as Record<string, unknown>;
  const { title, status, memberIds, updatedBy } = raw;
  if (typeof title !== 'string' || typeof status !== 'string' || typeof updatedBy !== 'string') return undefined;
  if (!Array.isArray(memberIds) || !memberIds.every((id) => typeof id === 'string')) return undefined;
  return { title, status, memberIds, updatedBy };
}

/** Members to notify: everyone on the task except whoever made the change. */
export function recipients(after: TaskSnapshot): string[] {
  return after.memberIds.filter((uid) => uid !== after.updatedBy);
}

/**
 * Builds one FCM message per device token when `status` changed. Returns [] otherwise, so the
 * function never pushes for edits that aren't status changes.
 */
export function buildStatusMessages(
  taskId: string,
  before: TaskSnapshot,
  after: TaskSnapshot,
  updaterName: string,
  tokensByUser: Record<string, string[]>,
): PushMessage[] {
  if (before.status === after.status) return [];
  const status = statusLabels[after.status] ?? after.status;
  return recipients(after).flatMap((uid) =>
    (tokensByUser[uid] ?? []).map((token) => ({
      token,
      notification: { title: `${updaterName} updated ${after.title}`, body: `Status: ${status}` },
      data: { taskId },
      apns: { payload: { aps: { sound: 'default', 'thread-id': taskId } } },
    })),
  );
}

/** FCM error codes that mean the token will never work again and should be removed. */
export function isInvalidTokenError(code: string | undefined): boolean {
  return code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token';
}
