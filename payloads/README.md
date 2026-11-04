# Simulator push payloads

Test push handling without FCM (or before the Blaze plan is enabled):

1. Run the app in a simulator and open a task; copy its id (or create one and read it from the
   debugger), then replace `REPLACE_WITH_TASK_ID` in the payload.
2. Send it:

   ```bash
   xcrun simctl push booted com.brainxtech.taskmanager payloads/task-status-updated.apns
   ```

3. In the foreground the banner appears (via `willPresent`); tapping it opens that task.

For real FCM delivery, use the Firebase console's "Send test message" with the device's FCM token
(logged under the `notifications` category) and add a custom data key `taskId`.
