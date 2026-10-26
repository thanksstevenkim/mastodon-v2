# Nori Search — Safe Migration Contract

Status: DESIGN / NO-GO
Scope: StatusesIndex and PublicStatusesIndex only.
Production changes: Not authorized.

## Index strategy

- Preserve the existing physical indices.
- Build independent Nori indices.
- Use non-conflicting read aliases.
- Keep AccountsIndex and TagsIndex unchanged.
- Never treat an Elasticsearch alias as automatic dual-write.

## Synchronization

- Keep legacy and Nori generations consistent.
- Cover creation, modification, deletion and reindexing.
- Cover account indexability changes and revocation.
- Cover searchable_by changes caused by interactions.
- Cover vacuum, account deletion and bulk deletion.
- Use idempotent, retryable synchronization.
- Prevent delayed writes from resurrecting deleted records.
- Do not acknowledge a migration update before its
  required durable processing state is recorded.

## Search cutover

- Preserve existing search ACL semantics.
- Enable text.korean queries only when the selected
  read indices provide the corresponding mapping.
- Verify combined public and private searches.
- Reject cutover if either index generation is stale.

## Rollback

- Preserve legacy index contents.
- Keep legacy deletion and permission state current.
- Block direct rollback if consistency is uncertain.
- Verify search ACLs after rollback.

## Validation

- Run integration tests against an isolated Mastodon
  application, PostgreSQL, Redis and Elasticsearch.
- Test successful writes, retries, concurrent updates,
  deletion, permission revocation and worker failures.
- Test cutover and rollback under ongoing writes.
- Fail closed when consistency cannot be established.

## STEP 77 — GO/NO-GO release gates

Assessment: NO-GO
Baseline: Draft PR #12, commit 72a2a6ac82ea8fdb588c511e482917da4bcfe01c.
Assessment date: 2026-10-26.
Scope: StatusesIndex and PublicStatusesIndex only.

This assessment is a design and code review, not a production
readiness certificate. Evidence must be refreshed for the exact
candidate commit, indices and environment before approval.

### Decision rules

- Every mandatory gate must have verified evidence.
- Missing, stale, ambiguous or failed evidence means NO-GO.
- Passing integration tests alone does not authorize cutover.
- `done: true` from a backfill or sweep is not a consistency proof.
- Index UUID equality proves identity, not unchanged contents.
- Neither this document nor a passing CI run authorizes
  changes to production indices, aliases or search routing.
- Rollback must preserve current deletion and permission state.
- Approval requires an explicit operator decision.

### Mandatory gates

| Gate | Requirement                                             | Status  |
| ---- | ------------------------------------------------------- | ------- |
| G01  | Exact candidate passes all required CI checks           | PARTIAL |
| G02  | Physical index targets, mappings and resources verified | OPEN    |
| G03  | Both backfills complete with verified checkpoints       | OPEN    |
| G04  | Durable dual-write, deletion and ACL retry safety       | OPEN    |
| G05  | Concurrent mutation and stale-write safety              | OPEN    |
| G06  | Exhaustive and stable Legacy/Nori consistency audit     | OPEN    |
| G07  | Correct Nori read routing and search ACLs               | OPEN    |
| G08  | Tested cutover and rollback under ongoing writes        | OPEN    |
| G09  | Backup, recovery, monitoring and operator approval      | OPEN    |

A gate remains OPEN until evidence for the current candidate
demonstrates that its requirements have been met.

### G01 — Candidate verification

Required evidence:

- All required workflow jobs complete successfully.
- Nori integration tests pass on the exact candidate SHA.
- Any post-test changes require the relevant checks to run again.

Observed evidence:

- 43 Nori integration examples passed at the baseline commit.
- Ruby lint, formatting, CodeQL and relevant search tests passed.
- Some general Ruby test jobs were still in progress at review.

### G02 — Index identity and resources

Required evidence:

- Both Legacy indices and both Nori indices are concrete,
  independently identified physical indices.
- Their names, UUIDs, mappings, aliases and analyzer availability
  match the intended search generation.
- Elasticsearch health, storage headroom and recovery capacity
  are sufficient for migration and rollback.
- AccountsIndex and TagsIndex remain outside migration scope.

### G03 — Complete backfill

Required evidence:

- Public and private backfills cover all relevant sources.
- Checkpoint generations match the intended Nori indices.
- Cursor persistence and recovery behavior are verified.
- Replayed batches cannot skip records or revive revoked data.
- All queued updates accumulated during backfill are reconciled.

Known limit:

- Current checkpoint implementations are test-environment only.
- Redis persistence and a production execution procedure
  have not been established.

### G04 — Durable synchronization and ACLs

Required evidence:

- Every required Legacy and Nori write outcome is checked.
- Failed writes remain retryable and are not acknowledged as
  successfully synchronized.
- Deletes, account revocation, changes in searchable_by and
  interaction-driven permissions propagate to both generations.
- Queue acknowledgement occurs only after required durable work.

Known risk:

- ShadowImporter.import! does not currently reject every
  unsuccessful index_class.import! return value.
- Any such failure must not cause pending indexing work
  to be removed from the durable queue.

### G05 — Concurrent mutation safety

Required evidence:

- Delayed and out-of-order writes cannot resurrect deleted
  statuses or restore revoked search permissions.
- Permission changes during backfill and during a sweep
  cannot produce an unrecognized successful completion.
- A well-defined write barrier, catch-up protocol or
  equivalent stable verification method is proven.

### G06 — Full consistency evidence

Required evidence:

- Both search index kinds are covered.
- PostgreSQL source scopes, Legacy and Nori are exhausted.
- Missing, extra and stale documents are detected.
- Indexed source fields and searchable_by are verified.
- A completed scan cannot silently omit changes made
  behind its advancing cursor.
- All mismatches are resolved before a GO decision.

Known limit:

- The existing sweep has no shared point-in-time snapshot
  across PostgreSQL and Elasticsearch.
- Sweep completion therefore cannot certify live parity.

### G07 — Correct search routing

Required evidence:

- Search readers use the explicitly selected generation.
- text.korean queries are issued only when the selected
  read indices provide that field and analyzer.
- Combined public/private search preserves the \_index-based
  filtering and searchable_by permission semantics.
- Cutover cannot partially select incompatible generations.

Known limit:

- SearchQueryTransformer still directly selects the
  existing index classes and their physical names.
- Nori-specific read cutover is not implemented.

### G08 — Cutover and rollback

Required evidence:

- A production-isolated rehearsal exercises both directions.
- Concurrent writes, deletions and revocations are covered.
- A failed cutover stops safely without losing search ACLs.
- Rollback is refused if Legacy parity cannot be established.
- Recovery does not rely on destructive index replacement.

### G09 — Operational approval

Required evidence:

- Verified restorable backups and documented recovery steps.
- Resource, Redis durability, queue health and failure alerts
  meet the operating plan.
- Named go/no-go and rollback criteria are checked against
  fresh evidence.
- The operator explicitly approves the specific change.

### Remaining work by stage

STEP 78:

- Close the write/retry, concurrent mutation and audit
  completeness gaps required by G03-G06.
- Validate only the safety-critical paths changed.

STEP 79:

- Implement safe generation-aware search routing.
- Rehearse cutover, failed cutover and rollback in isolation.
- Capture G02, G07 and G08 evidence.

STEP 80:

- Refresh all evidence for the final candidate.
- Complete the operating runbook, backup and resource checks.
- Issue an explicit GO or NO-GO decision for G01-G09.

No production cutover, alias repointing or merge is authorized
by completion of an individual stage.

## GO criteria

- All required integration tests pass.
- No known unresolved ACL or resurrection failure.
- Recovery and rollback procedures are validated.
- Production backup and resource checks pass.
- Explicit operator approval is obtained.

Until then: NO-GO.
