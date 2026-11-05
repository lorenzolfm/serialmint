# serialmint design

serialmint is a [Cashu](https://github.com/cashubtc/nuts) mint. Postgres holds all of its state,
and LND moves its Lightning payments.

This doc holds the decisions and the order of the work. A PR that changes a decision also changes
this doc.

## Invariants

Each invariant has a name, so tests and PRs can refer to it. The schema holds each one that a
schema can hold, and the code does not get to break them.

| # | Invariant | What holds it |
|---|---|---|
| I1 | A proof is spent at most once. | Primary key on `Y`. A spent proof cannot change. |
| I2 | A blinded message is signed at most once. | Primary key on `B_`. |
| I3 | An operation balances: inputs = outputs + fee. | `CHECK` on the operation, and a deferred trigger that sums its rows at commit. |
| I4 | A quote never issues more than it was paid. | `CHECK (amount_issued <= amount_paid)`. |
| I5 | An invoice has at most one melt that is pending or paid. | Partial unique index on the payment hash. |
| I6 | Only a terminal `FAILED` from LND releases the proofs of a melt. | The melt machine. See [Melt](#melt). |
| I7 | No handler calls LND, and no transaction spans an external call. | Only workers hold the LND client. `Db` closures get a connection and nothing else. |
| I8 | Private keys reach neither Postgres nor telemetry. | Secret types have no `Debug`, `Display` or `Serialize`. |
| I9 | A unit has at most one active keyset. | Partial unique index on the unit. |

Rows of this table are not deleted when a PR implements them. Each row is a promise, and the
[refusal suite](#refusal-suite) checks the ones that belong to the schema.

## Shape

```text
            HTTP                                      gRPC
 wallet ──────────▶ handlers ──▶ Postgres ◀── workers ──────▶ LND
                       ▲            │            ▲
                       │          NOTIFY         │
                       └───────  listener ───────┘
```

One binary runs all of it, and more than one replica can run. Replicas share only Postgres, so a
handler on one replica can wait for a worker on another.

## Transactions

`Db::read` and `Db::write` take a closure, and they are the only way to get a connection. The
closure gets a `ReadConn` or a `WriteConn`, so a read path cannot write.

- **Every transaction is SERIALIZABLE.** The role also sets `default_transaction_isolation`, so a
  statement outside `Db` gets the same level.
- **A serialization failure retries the closure from the start.** The retry has jitter and stops at
  a time budget. So a closure holds no side effect: no network, no file, no channel send. A
  `NOTIFY` is safe, because Postgres sends it only on commit.
- **The clock is `conn.now()`.** The closure reads it once per attempt, so all rows of a transaction
  have one timestamp. Clippy disallows `OffsetDateTime::now_utc`.
- **The order in a closure is reads, refusals, writes, success.** A refusal returns
  `Ok(Outcome::…)` before the first write. An `Err` means that something failed, and it never
  carries a domain answer.
- **Each statement has a guard.** An update names the state it expects in its `WHERE`, and it fails
  when it does not change exactly the rows it expects.
- **CPU work runs before the transaction.** The handler verifies proofs and signs outputs first, so
  a transaction stays short and a retry does not sign again.
- **Session timeouts bound everything:** statement, lock, idle in transaction, and transaction. PR 7
  sets the numbers.

Two transactions can insert the same key. When each one reads first, Postgres reports the conflict
as a serialization failure, and the retry sees the row and refuses cleanly. The unique index is
the last line. PR 14 has a test that pins this behavior.

## Schema

The schema assumes that the code above it has a bug. It refuses each illegal state that a constraint
can express.

- **Domains for values:** `pos_bigint`, `nonneg_bigint`, `non_empty_text`, `tautology`, `uuidv7`,
  `bytes32`, and a compressed point type (33 bytes, prefix `02` or `03`).
- **Enums for closed sets.** No bare `TEXT` for a set of values.
- **`NOT NULL` unless a state needs the null.** A `CHECK` with one `CASE` arm per state pins which
  columns each state has, and it ends in `ELSE false`.
- **Composite foreign keys pin what a key may point at.** A generated constant column pins a row to
  a kind, and a shared column welds an amount across tables. A pair whose amounts disagree cannot
  exist. This beats a trigger, because it has no window and no code path.
- **Partial unique indexes for "at most one".** See I5 and I9.
- **Single-row tables** have a `tautology` primary key, such as the settle cursor of LND.
- **Append-only by trigger.** Spent proofs and blind signatures refuse each update and delete.
- **Deferred constraint triggers, only for what a key cannot express,** such as the sums of I3.
- **Comments.** Each table has a comment, and so does each column with a non-obvious meaning. It says
  who writes the row and who reads it.
- **Banned in migrations:** `DEFAULT`, `SERIAL`, `IF EXISTS` and `CONCURRENTLY`. An identity key is
  `GENERATED ALWAYS AS IDENTITY`, and the code sets each timestamp.
- **Two roles.** Migrations run as an owner. The server runs as a role with no `DELETE`, `TRUNCATE`
  or DDL on the money tables.

### Refusal suite

Each constraint has a named statement that must be refused, in a table that a test walks:

```rust
const REFUSALS: &[(&str, &str)] = &[
    ("a second spend of one proof", "INSERT INTO proofs ..."),
    ("a quote that issues more than it was paid", "UPDATE mint_quotes ..."),
];
```

Each statement runs against committed fixtures made by production code. A meta-test reads
`pg_constraint` and fails when a constraint has no refusal, so a constraint cannot land untested.

### Review of SQL

A schema PR holds only the migration and its refusals. Code that depends on it waits until the SQL
is approved.

## Queue

The queue is a table. `NOTIFY` only wakes a worker, and it carries no work.

- **Enqueue:** a job row and its `NOTIFY` go in the transaction that made the work necessary. A
  rollback leaves neither, and a commit leaves both.
- **Wake:** a listener holds one connection outside the pool and runs `LISTEN`. It reconnects with
  backoff. This needs a session, so a transaction-mode PgBouncer cannot carry it.
- **Sweep:** a notification can be lost while the listener is down. So after each reconnect, and on
  an interval, a sweep reads the jobs that are due. The sweep alone would still deliver every job,
  only later.
- **Claim:** a worker claims one job by id, with a guarded update that sets a lease. Two workers
  that race on one id conflict, one retries, and it finds the job taken. Rejected: `SKIP LOCKED`,
  because workers that scan one range add conflicts under SSI, and claiming by id needs no scan.
- **Run:** the worker calls LND outside any transaction, then writes the result in one `Db::write`.
- **Lease:** a crashed worker holds its job until the lease ends, then a sweep finds the job. So a
  handler must be safe to run twice. Each handler in [Lightning](#lightning) says why it is.
- **Retry:** a job retries with backoff. It does not drop money work: past a limit, it raises an
  alert and stays in the table.
- **Trace:** the job row holds the `traceparent` of its request, so the span of a worker joins the
  trace of the request that caused it.

A commit that notifies takes a global lock in Postgres, so only Lightning paths notify. A swap has
no reason to.

### Waiting

A handler subscribes to the id of its quote, commits, and waits for a notification with a deadline.
Then it reads the row, which holds the truth. It touches only Postgres. This holds across replicas,
and the same notifications can serve NUT-17 later.

## Lightning

Each step below names what repairs the window between an LND call and the write of its result.

### Mint quote

NUT-23 requires the invoice in the response to `POST /v1/mint/quote/bolt11`, and I7 keeps LND out of
the handler. So the handler waits.

1. The handler writes the quote, with no invoice, and a job. It waits.
2. A worker calls `AddInvoice`, then writes the invoice with a guard on `request IS NULL`.
3. The handler wakes and answers. At its deadline, it refuses, and the wallet never saw that quote.

**Window:** a crash after `AddInvoice` makes a second invoice on the retry. No one saw the first
one, so no one can pay it, and it expires.

### Settlement

A task holds `SubscribeInvoices` from a settle index that Postgres stores. One transaction moves the
quote to paid and moves the cursor.

**Window:** a crash after the event and before the write replays the event on the next subscribe.
The guard on the state makes the replay a no-op.

### Mint

`POST /v1/mint/bolt11` calls no LND. The handler signs first, then one write reads the quote, refuses
what is not mintable, stores the signatures, and raises `amount_issued` with a guard. I2 and I4 hold
it to exactly once.

### Melt quote

The handler parses the invoice locally, and the fee reserve comes from config: a rate and a minimum.
Rejected: `EstimateRouteFee`, because it needs LND on a quote path, and it does not bind the route
that the payment takes.

### Melt

1. The handler verifies the proofs. One write refuses what is unbalanced, spent, pending or expired.
   Then it stores the proofs as pending, moves the quote to pending, and adds a job.
2. A worker calls `TrackPaymentV2`. On `NotFound`, it calls `SendPaymentV2`, with the fee reserve as
   the fee limit. It reads the stream until a terminal status.
3. On `SUCCEEDED`, one write spends the proofs, stores the preimage, signs the change of NUT-08, and
   moves the quote to paid.
4. On `FAILED`, one write releases the proofs and moves the quote back to unpaid.
5. On anything else (a transport error, a timeout, a crash) nothing changes. The lease ends, and the
   next worker starts at step 2.

**Window:** LND holds one payment for each hash, so a second send cannot pay twice. Step 5 can only
delay a melt, and it never loses money. This is why I6 reads as it does.

A sync melt waits as a mint quote does, and it answers `PENDING` at its deadline. A melt of an
invoice of this mint settles in one write, with no LND call (PR 26).

## Keys

The master seed loads once at start, from a secret file. Keyset secrets are derived in memory. The
`keysets` table holds public keys and the derivation index, so a dump of Postgres cannot sign. The
crypto is `secp256k1`, and signing stays in the process for now.

## Telemetry

Traces, metrics and logs leave through OTLP. A failed export never touches a money path.

- **Traces:** an HTTP span holds a span for each transaction, and that holds an event for each
  statement, with its call site. `SET LOCAL application_name` carries the trace id, so a line in the
  Postgres log names its trace.
- **Metrics:** requests by route and status, transaction attempts and serialization failures by
  reason, pool use, queue depth and age, LND latency by call, and ecash issued and redeemed by keyset.
  A label comes from a closed set, so no quote id is a label.
- **Logs:** the `log` crate, bridged to OTLP, with the trace id on each line.
- **Never exported:** secrets of proofs, private keys, preimages before settlement, and macaroons.

A compose file runs a local Grafana stack for all three.

## Tests

| Level | Runs against | Covers |
|---|---|---|
| L1 | Nothing | Spec vectors from the NUTs, proptest, the machines, fuzz targets for each parser |
| L2 | Real Postgres | Queries, refusals, double-spend races, the retry loop, windows through a scripted LND |
| L3 | Real bitcoind, two LND nodes, the real server | The money paths end to end, and a kill at each window |

- **A test commits.** Rollback hides each deferred constraint. Each test gets its own database,
  cloned from a template of the migrations, under real SERIALIZABLE.
- **One runner.** Nix pins Postgres and runs it on tmpfs. A test refuses to start without it.
- **The scripted LND is a gRPC server that speaks the LND protos.** Production's client connects to
  it, so no trait exists only for tests. A script can drop a stream at any message.
- **An expected value is a literal.** A test does not derive it from the code under test.
- **The auditor is the oracle.** The invariant queries of PR 27 run after each L2 and L3 test, and in
  production as metrics.
- **Each PR runs `cargo mutants --in-diff`.** A missed mutant fails CI.

## Repo

One crate until compile times give a reason to split. Nix and crane build every gate, and CI runs
one job for each gate. `flake.lock` and `rust-toolchain.toml` pin all tools. `cargo-deny` bans the
crates of CDK by name, and refuses unknown git sources.

## Order of the work

Each line is one PR. Later PRs may split further.

**Foundation**

1. This design
2. Scaffold: crate, Nix gates, CI, mutants, `cargo-deny`
3. Telemetry: OTLP traces, metrics and logs, and the local stack
4. HTTP skeleton: axum, shutdown, health, trace propagation
5. Test runner: Postgres from Nix, a template per migration hash, a database per test
6. Schema gate: domains, migration lint, `redo` check, refusal suite
7. `Db`: deadpool, diesel-async, typed connections, retry, timeouts, transaction spans

**Protocol, with no IO**

8. NUT-00: hash to curve and blind signing
9. NUT-01 and NUT-02: keys, keysets, ids
10. NUT-12: DLEQ
11. Wire models, parsed at the boundary, with fuzz targets

**Money, with no Lightning**

12. Keysets schema, `/v1/keys`, `/v1/keysets`, `/v1/info`
13. Proofs, signatures and operations schema
14. NUT-03: swap, with race tests
15. NUT-07 and NUT-09: state and restore

**Queue**

16. Jobs table and transactional `NOTIFY`
17. Listener, sweep, claim, lease, workers
18. Handler waits

**Lightning**

19. LND client from vendored protos, the scripted LND, the L3 harness
20. NUT-04 and NUT-23: mint quote
21. Settlement stream and cursor
22. Mint
23. NUT-05 and NUT-23: melt quote
24. Melt: reserve and pay
25. Melt: resolve, windows, NUT-08 change
26. Melt of an invoice of this mint

**Hardening**

27. Auditor, and reconciliation with LND
28. NUT-19, NUT-10, NUT-11, NUT-14, NUT-20, NUT-17
29. Interop with an external wallet, and a load test

## Open

- **A chained ledger.** One row per account that each posting must update gives a balance that the
  schema proves. Under SSI, that row also makes every swap conflict. PR 13 proposes per-operation
  balances with derived totals, and it says what the proposal gives up.
- **Settlement with more than one replica.** Each replica subscribes and the writes are idempotent,
  or one replica holds an advisory lock. PR 21 decides.
- **The exact gRPC codes of LND.** `TrackPaymentV2` answers `NotFound` for an unknown payment, and a
  duplicate `SendPaymentV2` is refused. PR 25 pins each code with an L3 test against the LND version
  in `flake.lock`.
- **The interop wallet.** Nutshell as a black box, so no CDK enters the repo, not even in tests.
- **A signer outside the process.** Not in this plan. The `Signer` type keeps the option cheap.
