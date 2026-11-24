## 0.1.3

- `GistChatbotConfig.clientId`: an optional user ID sent when a session is
  created, so sessions with the same ID share the question limit. Leave it unset
  until the backend accepts it; older backends reject it
- The question limit banner follows the per-widget-key limits: it shows the
  limit period ("1일 동안 최대 20번") and counts down to the server's
  `retryAfterSeconds`; longer waits are shown in hours and days
- With an older backend that sends neither, the banner and retry time work as
  before

## 0.1.2

- Research steps from the chat stream: shown live while the answer is being
  prepared, then folded into a one-line summary that expands to list each step
- Sources grouped by kind (documents, Ziggle notices, web) with their own icons
  and screen reader labels; web sources outside the school's official domains
  are marked, and untitled sources show their host name
- Stream handling follows the backend SSE contract: `[DONE]` completes the
  answer, error events fail it, and a stream that ends early keeps the received
  text with an "incomplete" notice; empty keep-alive frames are ignored
- Stopping cancels the underlying request; stopped and incomplete answers get an
  italic notice
- Research steps and sources saved with an answer are restored from history, and
  a failed stream checks history for a saved answer before giving up
- Questions are handled one at a time: a question sent while the previous answer
  is still syncing with history waits for it to finish
- Question length is counted the way the server counts it (4,000 limit); the
  input no longer cuts text off, and the counter turns red and sending is
  disabled when a question is too long
- The session question limit (429 with `limit`) is told apart from temporary
  throttling (429 without `limit`), and the banner shows the server's limit
- A failed or stopped regeneration restores the original answer and is not
  offered again
- Scroll-to-bottom button for reading earlier messages, matching the web widget;
  the list keeps following new content while you are at the bottom
- Fixed: a malformed resource path in the sources no longer leaves the answer
  loading forever
- Fixed: the rate-limit banner closes when the panel is reopened after the retry
  time has passed
- Frequent question about student ID cards now uses the mobile access card wording
- Requires `http` ^1.5.0

## 0.1.1

- Upgrade package_info_plus to ^10.2.1 (also restores WASM compatibility)
- English package documentation; Korean version moved to doc/README.ko.md

## 0.1.0

- Full rewrite to mirror the web widget's (chatbot-fe) design and UX
- New trigger API: the fixed floating button is gone; apps call `GistChatbot.open(context)` from their own widgets
- Frequent questions with separate card labels and full question texts, as on the web
- Staged loading copy with shimmer text and thinking-dots animation
- Stop button while streaming; partial answers are kept
- Answer feedback (GOOD/BAD) with a one-time regeneration on BAD
- Rate-limit (429) banner with a live retry countdown
- Source badges/images open in the external browser (resourceCenterUrl)
- Markdown rendering switched to gpt_markdown
- Widget key validation with clear error messages for setup mistakes
  (invalid key, unregistered app id)
- Service URLs built in: widgetKey is the only required configuration

## 0.0.2

- App-specific API spec: session issuing with clientType=app and appId
  (pageUrl removed); appId resolved via package_info_plus when omitted
- Message history fetching with pagination and resource fetching
- Rate-limit (429) notice; error responses parsed from the message field

## 0.0.1

- Initial release: chat screen widget, message input/list, backend API
  calls (session, chat streaming), session persistence, loading/error
  handling, token injection
