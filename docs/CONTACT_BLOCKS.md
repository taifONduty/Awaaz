# Private contact blocks

15 October 2026. The backend implements durable, directional block decisions. Flutter includes member/sender block controls and a private blocked-accounts page, alongside invitation revocation, member removal and Circle leave/close actions. No chat, location sharing or contact-delivery service is claimed by this increment. Verification scope is recorded below.

## Contact behavior

- Blocking removes the other member from Circles the blocker owns. In Circles owned by the other account or a third party, the blocker leaves. The blocker cannot remove someone else from a third party's Circle.
- Conflicting invitations are revoked in the same transaction, including invitations that would put the two accounts into the same Circle. Old accepted tokens cannot restore a revoked membership.
- New invitation creation and acceptance refuse a Circle containing anyone blocked in either direction. The response uses ordinary unavailable/not-found errors and does not reveal who blocked whom.
- Unblocking changes only the caller's outgoing decision. It restores no membership or invitation. A fresh explicit invitation and acceptance are still needed, and any other active block remains effective.
- A new block needs a known relationship through an existing/past Circle or invitation. The endpoint is not an account directory. Reading one's own state for an unrelated UUID returns the same unblocked/version-zero shape regardless of profile existence.

## API and retry contract

All endpoints require an online-verified Auth session and an adult profile, matching the existing Circle account boundary. Blocking is available independently of phone verification; phone control remains separately required for reporting.

| Endpoint | Contract |
| --- | --- |
| `GET /v1/me/blocks` | Private active outgoing decisions; `limit=1..50`, default 30; optional returned UUID `after` cursor |
| `GET /v1/me/blocks/:userId` | The caller's current `{userId, blocked, version, changedAt}`; no reverse block status |
| `PUT /v1/me/blocks/:userId` | `{blocked: true|false, expectedVersion: integer}`; returns the current state plus `replayed` |

Clients must read the current version before presenting a new decision. Two identical writes against version N produce one change and one replay at N+1. A delayed old decision cannot override later block/unblock activity: it receives `409 block_changed`. A conflict requires reading current state and a new explicit user decision, not silently substituting a newer version and resending. Versions are bounded integers; exhaustion returns a conflict. Self-targeting is invalid.

After an ambiguous network result, read the target's state before relying on access being revoked. An explicit retry of the same complete versioned intent is safe; no background resend is needed. Flutter clears stale contact/detail views before sending an approved decision, exposes unconfirmed status, and isolates review/replay state by account lifetime. Even signing out and back into the same account invalidates old dialog approval. An unchanged read after a transport failure cannot prove that an in-flight mutation will never commit, so it leaves the notice visible. A newer authoritative decision resolves that notice. The ordinary command journal does not queue block mutations, and no automatic resend occurs.

## Mobile controls

Circle details offer blocking for other members, including the owner when the viewer is a member. The invitation inbox offers blocking for the actual `inviterId`. The profile opens a paginated blocked-accounts list with a localized generic name when the server has no currently authorized name snapshot. Both blocking and unblocking read the current version, then require explicit confirmation explaining the membership consequences.

Uncertain contact mutations hide Circle details/invitations and show a check/retry notice on account and Circle overview screens. The retry sends the same versioned intent. The notice is held in memory for the current account lifetime; after process restart the app reads current server state and never restores or resends an unconfirmed mutation. English/Bangla controls and scrollable confirmations support large text. Viewing the block list fetches only the caller's outgoing blocks and never reveals reverse blocks.

The inbox now includes the intended invitation's `inviterId`, so the client can offer a block action without guessing identity from a name. It still excludes invitation secrets, phone values and block relations. Existing clients ignore this additional field.

## Database boundary

Migration `202610150008_contact_blocks.sql` wraps the previous People RPC and revokes the API role's retained grant on the renamed function. Readiness refuses direct access to the private block table or execution of that legacy/helper path. Public clients, the API login and the evidence worker have no direct block-table access. The security-definer entry point retains a fixed empty search path and binds the authenticated actor in parameterized SQL.

Every application Circle mutation locks all relevant account IDs in sorted UUID order before Circle/invitation rows. Blocking uses the same locks and locks affected Circles in sorted order. Candidate Circles come from the pair's indexed memberships/invitations; the mutation does not scan every Circle in the deployment. This serializes block against invitation acceptance/creation, including third-party invitations, without a global write lock. Privileged database administration must preserve these invariants; this is not protection against a database owner deliberately bypassing application functions.

The private row stores only the current decision, monotonic version, last change time and an optional display-name snapshot while blocked. The name is captured only when currently visible through shared active membership or an incoming live invitation; authorization and name selection use one SQL snapshot. Former contacts have a null label, displayed by the client as a localized generic blocked account. Snapshots do not reveal later profile-name changes. Unblocking erases the label and retains a minimal UUID/version tombstone to reject stale requests. Auth/profile deletion cascades the row. No location, phone, report narrative or decision history is added. Production retention/account-deletion operations remain part of the wider release work.

Limits: 1,000 active outgoing blocks, 200 changed decisions per account/UTC day, plus existing account/IP HTTP limits. Identical/no-op replays do not consume the durable decision quota. Lists return at most 50 entries and never include tombstones or another account's decisions. New changes during pagination require a normal refresh for a complete current view.

## Verification

All 25 API checks and 24 real PostgreSQL/PostGIS test nodes pass after the migration. TypeScript and formatting checks pass, and OpenAPI is regenerated. Three new database scenarios verify owned/third-party disconnection, old-token refusal, non-restoring unblock, stale decisions, private pagination, frozen labels, deletion cascade, denied direct/legacy access, readiness refusal for an accidental legacy grant, and actual concurrent block-versus-join/invite operations. The concurrency checks hold a real account advisory lock and observe a database waiter before releasing it; they do not infer concurrency from an arbitrary sleep. One new HTTP case covers actor binding, response allowlists, bounded pagination and strict input types.

The final migration was applied to a fresh disposable fixture database. A real HTTP probe verified duplicate convergence, membership revocation, stale rejection, non-restoring unblock, refusal of an old token and hidden former-contact names through versions 0–4. This probe used only synthetic local accounts and cleaned up its temporary Circle and block decision. Hosted Supabase Auth/pooler/RLS validation, production load/abuse review and future sharing/delivery authorization remain unfinished.

All 34 focused Flutter account API/view-model/widget checks pass, and full Flutter analysis is clean. These cover lost-acknowledgement read reconciliation without a duplicate mutation, old approval invalidation across logout/login, an unchanged read leaving contacts hidden, explicit retry and English/Bangla controls at 320 pixels with 200% text. A real widget review caught and fixed notification during route construction: the block-list load now starts after the first frame, while checking page/account ownership.

### Android cycle and installed artifact

The dedicated Android cycle passed on the isolated API-36 emulator in 67 seconds after test startup. It used real HTTP/PostgreSQL with synthetic local accounts, not an in-memory account repository. It verified that opening confirmation sends no block; a committed block followed by a deliberately dropped acknowledgement produces one mutation and reconciles through a read; the other member loses Circle access; unblocking restores neither membership nor the old accepted token; and blocking an incoming invitation's actual sender revokes that invitation. English/Bangla dialogs, populated lists and the empty state were exercised. The cycle cleaned up its block decision and temporary Circles.

The test APK built in 331.9 seconds: 109,970,488 bytes, SHA-256 `2dd9bffba66876124ff1ec033496e410bfbf9546712921822a058f286e9d2f31`. Its binary Android manifest was inspected and excludes the Maps key. Reproduce on a fresh disposable fixture API with:

```powershell
./scripts/build-android.ps1 -Integration -IntegrationTarget integration_test/contact_blocks_test.dart -UseMirrors -StopBuildDaemon
# Boot the isolated emulator and start the disposable Android fixture API.
./scripts/test-contact-blocks.ps1
```

The regular Maps-enabled preview was rebuilt in 244.2 seconds and restored after the cycle: `.local/awaaz-android-preview.apk`, 108,488,472 bytes, SHA-256 `81c8b4ab22d82935e1324bae70ca0b7a58a58e5244b4f9e557960c7df3954011`. The installed base APK's hash matches. Its manifest contains the configured SDK key, and fresh visual review confirms real Dhaka tiles on Explore. No native trip-monitor service was active. This increment did not rerun geographic monitor/route-replacement scenarios; their earlier build-specific evidence remains separate.

Screenshots: [English confirmation](ui-redesign/contact-block-confirm-en.png), [Bangla confirmation](ui-redesign/contact-block-confirm-bn.png), [Bangla blocked list](ui-redesign/contact-block-list-bn.png), [Bangla empty state](ui-redesign/contact-block-empty-bn.png), [restored Maps preview](ui-redesign/contact-block-final-preview.png). The English list capture is retained as a transition frame rather than evidence of settled app-bar chrome.

The emulator booted to its launcher, then showed a System UI ANR before the fixture app launched. The preflight refused to start under that dialog. Its observed Wait action cleared the dialog and the subsequent test passed in Awaaz process 3122. This does not resolve the documented startup/host-pressure limitation. No hosted Auth, physical-device/OEM background behavior, production load or emergency delivery is verified by this cycle. The new block views have not yet been synchronized to Figma.
