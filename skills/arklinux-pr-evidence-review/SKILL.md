---
name: arklinux-pr-evidence-review
description: Review an ARKlinux pull request, current head commit, CI runs, workflow artifacts, logs, and permanent evidence against a narrowly stated milestone. Use when asked whether a PR is complete, ready for review, safe to merge, contaminated, overstated, or missing proof.
compatibility: Requires read access to the GitHub repository, pull request metadata and diff, Actions runs and artifacts, and any referenced evidence files. Write actions require separate explicit authorization.
metadata:
  author: 1TRUE-INC
  version: "1.0.0"
---

# ARKlinux pull-request evidence review

## Purpose

Determine exactly what the current pull request proves. Separate implemented code, successful execution evidence, unsupported claims, and explicit non-scope. Produce a concrete disposition and the smallest next instruction.

## Required inputs

Resolve:

- repository;
- pull-request number;
- current head SHA;
- stated milestone and acceptance criteria;
- required artifacts and evidence files;
- whether the user requested read-only review, a review submission, readiness transition, or merge.

Never treat an earlier head SHA or earlier successful run as proof for the current head.

## Review workflow

1. Fetch current PR metadata and confirm open/closed, draft status, base, head branch, head SHA, mergeability, and scope statement.
2. Inspect all changed filenames and the relevant patches, not only the PR description.
3. Identify destructive operations, permissions changes, external dependencies, mocks, placeholders, success-shaped stubs, and scope expansion.
4. Fetch CI runs associated with the exact current head SHA.
5. Confirm required workflows completed and distinguish success, skipped, neutral, cancelled, timed out, and failure states.
6. Fetch the run artifacts and verify names, sizes, expiration, and required contents.
7. Inspect machine-readable summaries and logs when required by the milestone.
8. Compare every acceptance criterion with direct evidence.
9. Confirm permanent compact evidence exists in Git history when required.
10. Confirm the PR description's limitations match the actual remaining gaps.
11. Identify unresolved review threads, failed checks, missing files, stale evidence, or contradictions.
12. Produce a bounded disposition and exact corrective actions.

## Evidence classifications

Classify each material claim as:

- `VERIFIED`: directly supported for the current head by inspected evidence;
- `SUPPORTED`: strongly supported, but one independent check is unavailable;
- `NOT VERIFIED`: plausible, but evidence is absent or incomplete;
- `CONTRADICTED`: inspected evidence conflicts with the claim;
- `OUT OF SCOPE`: deliberately not attempted in this milestone;
- `STALE`: evidence applies to an earlier commit or run.

Do not collapse these categories into a general statement that a PR “looks good.”

## Readiness gate

A PR may be recommended as ready for review only when:

- the current head has the required passing checks;
- every required artifact exists;
- evidence retention and permanent records satisfy the milestone;
- the claim is no broader than the proof;
- no destructive or security-critical ambiguity remains within scope;
- explicit non-scope is preserved.

Readiness is not approval, and approval is not merge authorization.

## Required output

Provide:

1. Current PR state and exact head SHA.
2. Current CI run IDs and conclusions.
3. Acceptance-criteria table with evidence classification.
4. Scope-drift and safety findings.
5. Missing or stale evidence.
6. One disposition:
   - `READY FOR REVIEW`
   - `REMAIN DRAFT`
   - `REQUEST CHANGES`
   - `BLOCKED — MISSING ACCESS`
   - `BLOCKED — TECHNICAL FAILURE`
7. Exact next instructions suitable for the coding agent.

## Write-action rule

Do not mark ready, approve, request changes, merge, close, retarget, label, or comment unless the user explicitly asks for that specific GitHub mutation. A general request to “review” authorizes read-only inspection only.

## Truth boundary

A merged PR proves that changes entered the base branch. It does not independently prove installation, runtime correctness, hardware compatibility, production readiness, legal compliance, or the truth of historical evidence files. Validate the specific claim against the current commit and direct execution evidence.
