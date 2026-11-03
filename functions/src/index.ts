import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { buildStatusMessages, isInvalidTokenError, parseTask, recipients } from './message';

initializeApp();

/** Pushes to every other member when a task's status changes; prunes dead FCM tokens. */
export const onTaskStatusChanged = onDocumentUpdated('tasks/{taskId}', async (event) => {
  const before = parseTask(event.data?.before.data());
  const after = parseTask(event.data?.after.data());
  if (!before || !after || before.status === after.status) return;

  const db = getFirestore();
  const updater = await db.doc(`users/${after.updatedBy}`).get();
  const updaterName = (updater.get('displayName') as string | undefined) || 'Someone';

  const tokensByUser: Record<string, string[]> = {};
  await Promise.all(recipients(after).map(async (uid) => {
    const devices = await db.doc(`userTokens/${uid}`).get();
    const stored = devices.get('fcmTokens');
    tokensByUser[uid] = Array.isArray(stored) ? stored.filter((t): t is string => typeof t === 'string') : [];
  }));

  const messages = buildStatusMessages(event.params.taskId, before, after, updaterName, tokensByUser);
  if (messages.length === 0) return;

  const response = await getMessaging().sendEach(messages);
  const cleanups: Promise<unknown>[] = [];
  response.responses.forEach((result, index) => {
    if (result.success || !isInvalidTokenError(result.error?.code)) return;
    const token = messages[index].token;
    const owner = Object.keys(tokensByUser).find((uid) => tokensByUser[uid].includes(token));
    if (owner) {
      cleanups.push(db.doc(`userTokens/${owner}`).update({ fcmTokens: FieldValue.arrayRemove(token) }));
    }
  });
  await Promise.all(cleanups);
  logger.info(`Sent ${response.successCount}/${messages.length} pushes for task ${event.params.taskId}`);
});
