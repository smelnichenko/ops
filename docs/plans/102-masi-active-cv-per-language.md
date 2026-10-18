# 102 — masi: an active CV per language

## Context

Operator, 2026-10-18 10:35: "each language should have own active cv" — "i.e. we can translate cv and then make it
active". Today a user has ONE active CV version (any language; `uq_cv_version_active` on `user_uuid`). Other languages
exist only as reviewed translations of that one master, which the tuner borrows for postings in their language
(`MasterTranslationService.currentOf`), and a translation can never be activated (`ck_cv_version_translation_inactive`).
Packages and scores are keyed to the one active master.

Decided by the operator (2026-10-18):
1. A posting in a language with **no active CV is skipped**: no package, no score, until a CV in its language is active.
2. A translation can be activated **only after the operator approved it** (reviewed, no parity violation). A CV written
   directly in any language can be activated any time.
3. A posting is scored against **every** active CV of the user (each language version's fit) - only when one of them is
   in the posting's language (rule 1).

## Model

- `cv_version.language` (en | et | ru - the schema's required `language`), written on every save and translation,
  backfilled from the YAML. One active version **per user and language**: `uq_cv_version_active_language` on
  `(user_uuid, language) where active`, replacing `uq_cv_version_active`.
- Activating a version deactivates only the active one **in its language**.
- A translation may be active once reviewed: `ck_cv_version_translation_inactive` becomes "a translation is active
  only with `reviewed_at`"; activation also re-checks parity (the rules may have tightened since the review).
- A posting's language is its analysis's (`requirements_json.language`); a job is not scored or tuned before it is
  analysed (already so for scores; packages follow).
- "Current translation" stops steering the tuner: the active CV in a language is the CV of that language. Approved
  translations stay what they are (versions with `translated_from_id`), only now activatable.

## PRs (each: failing tests first -> reviews (architecture, concurrency, test-quality) -> own revert checks, each compiled
and red -> Sonar pre-check + clean check -> PR -> CI -> merge -> deploy to test -> live check -> plan updated)

1. **masi - activation per language**: changeset 066 (column, backfill, the index swap, the check); `CvVersion.language`
   set on create; `CvMasterService.activate` deactivates its language only, refuses an unreviewed translation or one with
   parity violations; `actives(user)` and `activeIn(user, language)` replace `active(user)` for callers that mean a
   language; `GET /cv` returns every active version (`actives`), keeping `active` as the most recently activated for the
   old site until PR 4 ships.
2. **masi - scores**: `MatchService` and `MatchingLane` score a job against every active CV of the user only when one
   is in the job's language; the AI match likewise. A job skipped is picked up when such a CV is activated (its absence
   of a score is the backlog).
3. **masi - packages**: auto-tuning creates a package for a job from the active CV **in the job's language** (none: no
   package); a requested package uses the language asked, else the posting's, and refuses "no active CV in X"; a package
   is tuned from its own CV version (the translation borrowing goes); regenerating in another language makes the package
   of that language's CV. The dashboard, reports and job views name the active CVs per language.
4. **site**: the CV page shows the active version of each language ("active: en v2 · et v5"), offers Activate on an
   approved translation, and keeps the editor on the version saved (site #36, already in flight).

## Verification

- Tests per rule: two languages active at once; activating one leaves the other; an unreviewed translation refused, a
  reviewed one activated; a Russian posting with no Russian CV gets no score and no package; an Estonian posting scored
  against both active CVs and tuned from the Estonian one; a CV activated later picks up the skipped backlog.
- Live on test: the operator's own CV (test env v2) active in English, its Estonian translation approved and active;
  an Estonian posting's package written from it.
