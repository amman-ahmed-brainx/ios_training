# Five-minute demo

1. **Launch (0:00).** Splash, then login. Show inline validation (bad email, empty password), then
   forgot-password (neutral "if an account exists…" message).
2. **Sign up / log in (0:40).** Create an account; relaunch to show the session is restored.
3. **Tasks (1:10).** Create a task with a due date (permission pre-prompt appears in the list), edit
   it, search, filter by status/overdue, sort by priority, swipe to complete and to delete.
4. **Offline (2:00).** Airplane mode → banner shows "Offline"; create and edit tasks; pending count in
   Settings. Turn the network back on → banner shows the changes syncing, then "All changes synced".
5. **Collaboration and push (2:40).** Share the task with a second account (second device); change
   the status there → push "<name> updated <task>" arrives; tap it → the task opens. Show that the
   collaborator can't edit the title or delete.
6. **Attachments (3:20).** Add a photo (compressed), a small PDF (foreground progress) and a large
   video (background upload); background the app and come back; preview with QuickLook; delete.
7. **Background (4:00).** Explain BG tasks (LLDB command in `App/BackgroundSync.swift`) and the
   background upload relaunch path.
8. **Polish (4:30).** Dark mode, Dynamic Type AX5, VoiceOver on a row (actions rotor), German
   language; Settings: reminder lead time, Sync Now, export/import JSON, sign out (cache wiped).
