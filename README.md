# MemePing

MemePing lets anyone get memecoin calls (Solana, Ethereum, Base, …) delivered straight to
their **own Telegram channel**, filtered by the criteria they care about (pair age, market
cap, liquidity, volume, forbidden terms in the name/ticker, and more). No trading, no
sniping — just a reliable bridge between DEX Screener and Telegram, self-served through a
web app.

## 1. Product summary

- **Multi-tenant**: every user configures one or more "notifiers" (a Telegram destination +
  a set of filters). MemePing evaluates every discovered token/pair against every active
  user notifier and forwards a formatted call when it matches.
- **No sniper / no trading**: this project reuses the *discovery* and *notification* halves
  of the existing `bentley` prototype (`components/lib/bentley`), but drops the sniper /
  execution / position-tracking pieces entirely.
- **Multi-chain**: unlike the prototype (Solana-only), MemePing should support any chain
  DEX Screener indexes (Solana, Ethereum, Base, BSC, …), selectable per notifier.
- **Auth**: sign in with a Web3 wallet only for v1 (MetaMask/Ethereum, Phantom/Solana) via
  sign-in-with-wallet (message signing, no password/custody involved). Google/X OAuth are
  deferred — this audience already has a wallet, and wallet-only removes third-party
  developer console approval, secrets, and consent-screen friction for launch.
- **Monetization**: free tier capped at 5 calls/month; paid subscription unlocks unlimited
  (or higher-capped) calls, more notifiers, and shorter polling intervals. v1 has **no
  recurring/pull billing** — a subscription is a flat 30-day USDC payment (sent through the
  already-connected wallet) that the user manually renews when it expires. Stripe/fiat and
  auto-renewal are future work, not v1.

## 2. What we reuse from `bentley`

The `components/lib/bentley` folder is a working single-tenant prototype. Key pieces we
plan to port/generalize:

| Bentley module | Reused as | Notes |
|---|---|---|
| `Bentley.Recorder` | `MemePing.Discovery.Recorder` | Polls DEX Screener "latest token profiles"; must become chain-aware (loop over configured chains, not hardcoded `"solana"`). |
| `Bentley.Updater` | `MemePing.Discovery.Updater` | Refreshes per-token metrics (`marketCap`, `liquidity`, volume, price changes …) on an adaptive schedule based on age/volume. Drop the `SniperPosition` / `Activator` coupling. |
| `Bentley.Notifiers` + `Notifiers.Worker` | `MemePing.Notifications.Notifier` (per-user, DB-backed) | Instead of a static YAML file loaded once, each user's notifier row becomes a supervised worker (Registry + DynamicSupervisor pattern is reused as-is). |
| `Bentley.Notifiers.Criteria` | `MemePing.Notifications.Criteria` | Same min/max range matching engine; extend with a `forbidden_terms` (name/ticker substring/regex) check and multi-chain metric support. |
| `Bentley.Notifiers.Formatter` | `MemePing.Notifications.Formatter` | Message templating for the Telegram call. |
| `Bentley.Telegram.Client` (+ `HTTPClient`) | `MemePing.Telegram.Client` | Behaviour + HTTP impl is already decoupled/mockable — keep as-is. Needs to support sending to a channel/chat that belongs to the *end user*, not a single hardcoded bot config. |
| `Bentley.Schema.Token`, `Bentley.RateLimiter` | Reused close to verbatim | Add a `chain_id` column/index since Token becomes shared across chains. |
| `Bentley.Snipers*`, `SniperPosition`, `SniperTrade`, `Activator` | **Not reused** | Trading/sniper concerns are out of scope for MemePing. |

Net effect: the "discovery" side (Recorder/Updater/Token) stays a **shared, global** pipeline
(one set of GenServers polling DEX Screener for everyone), while the "notification" side
becomes **per-user/per-notifier** and driven by rows in Postgres instead of a YAML file.

## 3. Proposed architecture

- **Stack**: Elixir + Phoenix (LiveView for the UI), Ecto/SQLite3 (consistent with the
  `bentley` prototype's `Repo`; revisit Postgres if/when we need concurrent writers or a
  managed hosted DB), Oban (recommended upgrade over raw `Process.send_after/3` loops for
  the discovery pollers — gives retries, observability, and avoids re-implementing
  scheduling/backoff by hand), Tailwind for styling. Phoenix is a strong fit here: the
  existing prototype is already Elixir/OTP, the domain is naturally concurrent (many
  independent pollers/notifiers), and LiveView removes the need for a separate SPA frontend
  for the dashboard/filter builder. The Phoenix project lives directly at the repo root
  (`mix.exs`, `lib/`, `priv/`, `assets/`, ...); `components/` stays as-is as the
  legacy-prototype reference.
- **App layout** (single Phoenix app to start, can split into an umbrella later if needed):
  - `lib/memeping/discovery/` — Recorder, Updater, DEX Screener client, rate limiter, `Token` schema (shared).
  - `lib/memeping/notifications/` — per-user `Notifier` schema, `Criteria`, `Formatter`, delivery worker/supervisor.
  - `lib/memeping/telegram/` — Telegram client behaviour + HTTP implementation.
  - `lib/memeping/accounts/` — `User`, wallet identities, sessions.
  - `lib/memeping/billing/` — `Subscription`, `Plan`, usage/quota tracking, USDC payment verification (manual 30-day renewal for v1).
  - `lib/memeping_web/` — LiveView UI: dashboard, notifier/filter builder, billing, auth callbacks.

- **Auth (v1, web3-only)**:
  - Wallet sign-in ("Sign-In with Ethereum"/EIP-4361 style, and an equivalent Solana
    message-signing flow for Phantom): client requests a one-time nonce, signs a message
    with MetaMask/Phantom, server verifies the signature (`ex_secp256k1`/`ex_keccak` for
    EVM, `ed25519`/`:crypto` for Solana) and links/creates a `User`.
  - A `User` can have multiple linked wallet identities (EVM address, Solana address).
  - Google OAuth (`ueberauth` + `ueberauth_google`) and X/Twitter are deferred to a later
    phase, not part of v1.

- **Subscriptions (v1)**:
  - USDC only, no recurring/pull billing: the app shows a fixed 30-day price, the user
    approves a USDC transfer through their already-connected wallet, the server confirms
    the on-chain transfer and sets `subscriptions.expires_at = now + 30 days`.
  - Renewal is manual — the user re-triggers payment when their subscription lapses; no
    allowance/`transferFrom` auto-pull and no Stripe integration in v1 (both are future work).
  - Enforcement: a `Plan` defines `max_calls_per_month` (5 for free) and `max_notifiers`;
    usage is tracked per user and checked before delivering a notification, and
    `expires_at` gates the paid tier.

- **Data model (first cut)**:
  - `users`, `wallet_identities` (chain, address)
  - `notifiers` (user_id, telegram_chat_id, chain_id, criteria as embedded schema/JSON, forbidden_terms, enabled, poll_interval)
  - `tokens` (shared, + `chain_id`)
  - `notification_deliveries` (notifier_id, token_address, sent_at) — same dedup role as today
  - `subscriptions` (user_id, plan, expires_at, last_payment_tx), `plans`, `usage_counters`

## 4. Explicit differences vs. the `bentley` prototype

- Multi-chain instead of Solana-only.
- Filters are user-owned DB rows (CRUD'd through the UI), not a static YAML file.
- Users bring/connect their own Telegram channel (they add our bot to their channel and we
  store the resulting `chat_id`), instead of one operator-owned set of channels.
- Adds a `forbidden_terms` criterion (reject tokens whose name/ticker contains blacklisted
  words).
- No sniping, no trade execution, no wallet custody of user funds — MemePing never holds
  or trades the user's assets.
- Adds authentication, billing, and per-user usage quotas, none of which exist in the prototype.

## 5. Roadmap (step by step)

1. **Repo & specs** — this README, project scaffolding, CI skeleton. *(this step)*
2. **Auth + UI shell** *(current step, branch `auth`)* — Phoenix + LiveView app at the repo
   root, wallet sign-in (MetaMask + Phantom) only, ultra-basic placeholder UI, no real
   data yet. Google/X OAuth deferred.
3. **Notifier/filter management UI** — CRUD for notifiers & criteria, Telegram channel
   linking flow.
4. **Discovery backend** — port Recorder/Updater/Token to be multi-chain, backed by Oban.
5. **Notification delivery** — per-user notifier workers, Criteria/Formatter, Telegram
   delivery, dedup via `notification_deliveries`.
6. **Billing & quotas** — Plans, USDC manual 30-day renewal payment path (v1), free-tier
   call cap enforcement. Stripe/fiat and auto-renewal considered later.
7. **Hardening & deploy** — observability, rate limiting, background job monitoring,
   production deployment.

We'll tackle these incrementally, starting with #2 (UI + auth) once the repo/spec baseline
is in place.

## 6. Telegram delivery and scaling (SQLite era)

MemePing currently supports a single-node deployment backed by SQLite. Every enabled notifier
has its own worker, which evaluates matching tokens once per minute (with up to 10 seconds of
random scheduling jitter). A notifier sends at most **3** unseen token calls per round; remaining
matches are still eligible on the next round and are sorted oldest-first.

All Telegram API requests pass through one in-memory, process-local limiter. It starts at most
**20 requests per second** (a theoretical maximum of 1,200 starts per minute), with the practical
initial operating target set at **300-600 successful sends per minute**. Requests above that rate
wait in the limiter's FIFO mailbox. This is intentionally not a durable job queue: a process
restart drops waiting requests, but their tokens were not recorded as delivered and will be
considered again on a later notifier poll.

Monitor production logs for these entries:

- `[Telegram Rate Limiter] Last minute: released 100 requests, peak queue 74, max wait 3800ms`
  reports requests released to the Telegram client, the largest number of waiting requests, and
  the longest total wait for a slot during that minute. A peak queue of 74 represents about 3.7
  seconds of additional wait at the current 20 requests/second rate.
- `[Telegram Rate Limiter] Request waited 5100ms for a send slot; 42 requests remain queued`
  is emitted when an individual request waits at least 5 seconds.

Queue depth consistently near zero and maximum waits below one second indicate comfortable
capacity. Investigate sustained waits over 5 seconds, a queue that grows from minute to minute,
or consecutive minutes near 1,200 released requests. Move to PostgreSQL plus a durable job queue
(such as Oban), including Telegram `429` retry-after handling, before running multiple app nodes,
requiring durable retry guarantees, or sustaining high-volume delivery backlogs.

## 7. Debugging helpers (`iex -S mix phx.server`)

- `MemePing.Discovery.recap(limit \\ 20)` — prints the most recently touched tokens
  (chain, address, ticker, `active`/`inactivity_reason`, market cap, liquidity, 1h volume,
  last-checked/updated timestamps), most recent first.
- `MemePing.Notifications.recap(name)` — for every notifier whose name contains `name`
  (case-insensitive), prints the tokens currently due to be sent on its next round (with
  metrics) and when that round is scheduled. A token that already has a row in
  `notification_deliveries` for that notifier is permanently excluded here regardless of
  criteria — that's the dedup ledger working as intended, not a criteria mismatch.
- `MemePing.Notifications.force_poll(name)` — runs an immediate delivery pass for every
  matching notifier instead of waiting for its next scheduled round (up to 60s); requires
  the notifier's worker to actually be running (enabled + linked to a Telegram channel).
- `MemePing.Repo.get_by(MemePing.Notifications.NotificationDelivery, token_address: "...")`
  — check whether/when a specific token was already delivered to a notifier (add
  `notifier_id: id` to scope it to one notifier); a non-nil result explains why that token
  no longer shows up in `recap/1` no matter what the criteria are.
