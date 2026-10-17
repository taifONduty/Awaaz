# Private storage and explicit retries — 13 October 2026

## Implemented behavior

Circle creation, invitations and report submissions persist a validated request **before** HTTP. Native records use encrypted storage, scoped to the configured Supabase/API URLs and authenticated account. Each record preserves its UUID, payload and original observation time. UI memory clears immediately on account changes. The same account can recover its saved requests after login; nothing automatically resends.

An acknowledgement removes only its own record. Failed local cleanup retains the UUID and reports that the server received the request. Explicit retry uses that saved UUID/time. Whole read/modify/write transactions are serialized across adapters; the idle queue is reset before returning to callers.

Explicit removal requires an account/context-bound confirmation: deleting a local saved request does not undo a server write, and users must check history before resubmitting. Removal also deletes local deduplication information. Pending payloads remain until acknowledgement or removal, bounded to 32 records/64 KiB per account/backend. Corrupt or oversized journals fail closed and do not invent replacement IDs or send HTTP.

Report receipts accept `pending`, `reviewed`, `rejected` and `withdrawn`. A withdrawn replay cannot restore content or a public event. Explicit retries now check the authenticated receipt endpoint first, resolving received requests without a new POST even after 72 hours. If an old request has no receipt, it stays saved with an explanation; its original time/UUID are not changed. [Current composer and reconciliation contract](LOCATION_REPORT_COMPOSER.md).

Anonymous native preview drafts use encrypted storage, a 20-draft/64-KiB bound and 30-day retention enforced on reading. Empty writes delete the value; queued writes snapshot their input. Obsolete mock plaintext preferences are discarded without importing them. Preview drafts remain separate from account-bound live writes. Web drafts, sessions and requests are memory-only.

## Verification boundaries

The corrected two-phase Android run passed: a real SQL report response was deliberately lost; the installed app was preserved and force-stopped; a new process recovered the encrypted request and retried its original UUID/time, leaving the same two server report IDs. The native storage file contained the journal key without plaintext synthetic description/JSON. Saved-request and post-restart screens were visually inspected. Logs and exact limits are in the development loop.

The complete host suite passed 55 tests before adding a final account-change confirmation case. Tests cover concurrency, adapter recreation, account/backend isolation, corrupt data, restart-safe IDs/time, storage failure before HTTP, acknowledgement-cleanup failure, draft retention/deletion, mock preference removal, withdrawn receipts and English/Bangla retry controls at 200% text. Final device results/counts are in [the development loop](ANDROID_DEVELOPMENT_LOOP.md).

The Android test client can discard a successful real report response. The first phase leaves an encrypted request after a committed write. The host then force-stops Android and starts the same test APK against the **same** disposable fixture server/database. The second phase recovers and retries the original UUID, comparing report IDs before/after to detect duplicates. `/__fixtures/restart` holds only test phase metadata and is absent from production startup.

SOS delivery and background monitoring remain unfinished. The subsequent foreground location composer and receipt reconciliation are documented separately. Fresh hosted Auth/API configuration and cloud OTP remain outside synthetic testing. Platform encryption is not a claim of resistance to a rooted device or an unlocked account.
