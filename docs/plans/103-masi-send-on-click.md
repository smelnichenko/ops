# Plan 103 — masi: send an application on the operator's click

**Status:** planned 2026-10-19. Build after plan 099 3d (masi #122): one masi PR at a time.

## Decision

On 2026-10-19 the operator was offered three choices: send on my click, send automatically, or keep it manual. They chose
**Send on my click**.

Until now masi never sent anything. A package went NEW → PREPARED → REVIEWED, the operator applied somewhere by hand,
and then recorded APPLIED. Now a REVIEWED package gets a **Send** action. One press sends one mail, to the contact the
job's own posting names, and the package becomes APPLIED.

Nothing leaves without a press:
- no schedule;
- no bulk send;
- no automatic retry.

This keeps the standing rule against unattended mail (feedback 2026-09-21, the weekly digest).

## What exists

- **SMTP:** Resend (`smtp.resend.com`), from the verified domain `noreply@pmon.dev`. masi already mails the digest
  through it when asked: `masi.mail.*`, the chart's `masiService.mail`.
- **Test** has a mail sink, `masi.mail.deliver-all-to`. Every mail goes there and none to a real address. The sender
  and the sink must never be a state inbox (`Normalizer.stateMail`).
- **Recipients:** a posting's named contact is a `contact` with `email` and `do_not_contact`, tied to a `person` by
  `person_company` (role POSTED_FOR, evidence LISTING, `evidence_ref` = the listing's id).
- **Coverage in production (2026-10-19):** 165 of 426 open jobs have such a contact with an e-mail on one of their own
  postings. The rest give only an apply link or form. masi reads `applyUrl` from the boards but does not keep it: it
  is used only to detect an ATS.
- **The package** holds the tuned CV PDF and the cover letter, in the posting's language (plan 102).

## The mail

| Field | Value |
|---|---|
| From | `Sergei Melnichenko <apply@pmon.dev>` — a pmon.dev address, because Resend can sign only that domain (a gmail.com sender fails DMARC) |
| Reply-To | the operator's own address (`sergei.melnichenko@gmail.com`), so a recruiter's answer reaches them |
| Bcc | the same address: the operator keeps a copy of exactly what was sent |
| To | one contact: the one named on this job's own posting, with an e-mail, not `do_not_contact`, not a state inbox; the operator picks when there are several (default: the newest posting's) |
| Subject | the posting's title + the operator's name, in the package's language |
| Body | the package's cover letter, as reviewed, plain text |
| Attachment | the package's CV PDF (the file the operator reviewed, byte for byte) |

The From address, Reply-To and Bcc come from configuration, not code: `masi.apply.from`, `masi.apply.reply-to`,
`masi.apply.bcc`. Send is off until they are set.

## Rules

1. **Send only a REVIEWED package of an OPEN job.** Anything else gets 409 and nothing leaves.
2. **Preview first.** `GET /packages/{id}/send-preview` returns the exact To, Subject, Body and attachment name and
   size. The site shows it in a confirm dialog. `POST /packages/{id}/send` carries the preview's hash, and a package
   changed since the preview gets 409. So the click is a review of the exact mail.
3. **Once per package, on any number of pods.** A `package_send` row, unique on `package_id`, is claimed before the
   SMTP call in its own transaction (claimed → SENT | FAILED). A double click or a second pod is refused by the
   unique key.
4. **A failure says so and leaves the package REVIEWED.** The row becomes FAILED with the SMTP reason. A new press
   retries (the FAILED row is re-claimed). There is no automatic retry.
5. **After SENT:**
   - the package becomes APPLIED;
   - the activity log says "applied by e-mail to <contact> (<company>)";
   - the person gets a TALKED_TO tie with evidence OPERATOR;
   - the Message-ID is kept on the row.
6. **Non-production:** the sink takes every send, as it does the digest. The preview says "test: goes to <sink>".
7. **Never to a state inbox** (`eesti.ee`), never to a `do_not_contact` contact, never to an address the posting
   did not publish.
8. **No send without the switch:** `masi.apply.enabled` (default false). Production switches it on in infra
   values once PR 1 and PR 2 have passed test.

## PRs

1. **masi — Send.**
   - Changeset: `package_send` (`package_id` unique, `contact_id`, `to_address`, status, error, `message_id`,
     `sent_at`, `claimed_by`).
   - `job_listing.apply_url`, kept from now on: the site shows it as "apply at …" where no e-mail is published.
   - `ApplyMailer`, the preview and send endpoints, `masi.apply.*` properties.
   - Tests:
     - the mail's every field (GreenMail);
     - 409s: not REVIEWED, job closed, a stale preview;
     - one send on two pods (TwoInstancesTest);
     - a failure, then a retry;
     - the sink in test;
     - refusal of a state inbox and of `do_not_contact`;
     - APPLIED and the activity log after SENT.
   - Revert checks for each rule.
2. **site — the Send button.**
   - Shown on a REVIEWED package with a sendable contact.
   - The confirm dialog shows the exact mail. After sending, the package shows "sent to … at …".
   - Where there is no e-mail: "apply at <apply url>".
   - Vitest tests, measured in the rendered page.
3. **platform + infra.**
   - Chart: `masiService.apply.*` env.
   - Test: on, to the sink.
   - Production: on, with From `apply@pmon.dev`, once 1 and 2 pass on test with one real send to the sink.

## Verification

- **On test:** send one REVIEWED package. The sink receives exactly the previewed mail with its CV attached. A
  second press gets 409. The package is APPLIED.
- **In production:** the operator presses Send on one package they chose. Their Bcc copy arrives. The `package_send`
  row is SENT with a Message-ID.

## Open (decided here unless the operator says otherwise)

- From is `apply@pmon.dev` (Resend's verified domain), not the operator's gmail. A reply still reaches gmail
  through Reply-To.
- The letter goes as the body and the CV as the attachment. There is no separate letter PDF.
