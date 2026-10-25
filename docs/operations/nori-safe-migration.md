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

## GO criteria

- All required integration tests pass.
- No known unresolved ACL or resurrection failure.
- Recovery and rollback procedures are validated.
- Production backup and resource checks pass.
- Explicit operator approval is obtained.

Until then: NO-GO.
