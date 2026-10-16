# Partner Introductions Importer

A .NET Framework 4.8 console application that turns partner referral emails into prospects and policies in the Open GI back office.

It reads the **Partner Introductions** shared mailbox through Microsoft Graph and saves each referral to SQL Server. It then checks the lead against existing prospects and submits new ones to **Open Interchange (InStream)** as household (`HQ`) prospects/policies. Every lead keeps a permanent database record with a full audit trail, whether or not the import succeeds.

---

## How it works

### Phase 1: read emails and save them to the database
1. Gets the last 1 day of email from the mailbox's **Inbox** and **Junk Email** folders.
2. Accepts an email if either:
   - the mailbox is in **Cc** (standard partner referrals), or
   - it is **From `leads@policylink.co.uk`** with the mailbox in **To** (PolicyLink leads).
3. Parses the email body into lead fields. Missing fields get defaults.
4. Inserts one row into `[Phone System].dbo.PartnerLeads` with `Status = 'Pending'`. Each email ID is only saved once.
5. Marks the email as read.

### Phase 2: submit to Open GI
1. Picks up `Pending` leads received more than 15 minutes ago.
2. **Duplicate check:** looks in `[Thamesbank].dbo.ic_Daprospect` for a prospect with the same **Email + Telephone + Postcode**. A match is marked `AlreadyQuoted` and not resubmitted.
3. Builds the `APMIMPORT` XML and submits it to InStream with a SOAP request.
4. Updates the lead to `Success` or `Failed`, with the prospect/policy references, the submitted XML and the raw response.

### Lead statuses
`Pending` → `Success` | `Failed` | `AlreadyQuoted`

---

## Supported email formats

### Standard partners (`Label - value`)
```
Name - Mr John Smith
Date of Birth - 01/01/1980
Address 1 - 1 High Street
Post Code - AB1 2CD
Cover Type - Buildings & Contents
...
```
The source is taken from the subject line: `IRevolution`, `HPS`, `HQ INTERNET` or `QuoteBeater`.

### PolicyLink (`Label:    value`)
```
Product - landlord
Email:    ...
Telephone:    ...
Title:    ...
First Name:    ...
Last Name:    ...
Address1: ... Address4: ...   City: ...   Postcode: ...
Cover Level:    building_only
Property Postcode:    ...
Property Value:    250000
Property Type Flat:    Yes
...
```
| PolicyLink field | How it is used |
|---|---|
| Source | Always `IRevolution` |
| Product | Stored for reference; always submitted as `HQ` |
| Property Postcode | Used as the client, risk and correspondence postcode (proposer postcode is only a fallback) |
| Address3 / Address4 / City | Combined into address line 3 |
| Title / First Name / Last Name | Stored and submitted as-is (multi-word surnames stay intact) |
| Cover Level | `building_only` → Buildings, `contents_only` → Contents, otherwise Buildings & Contents |
| Property Value | Buildings sum insured |
| Property Type flags | Flags set to "Yes" are stored for reference; Housetype uses the standard default |

---

## Open GI field mapping

| XML section | Fields |
|---|---|
| `APMCLIENT/P.CM` | NAME, ADDR1–3, PCODE, TEL, EMAIL, SOURCE, NOTES |
| `APMPOL/P.PY` | PTYPE = `HQ` |
| `HW` | Risk and correspondence address, Buildings / Contents / Specitems (Yes/No), sums insured |
| `H1` | Housetype, Bedrooms, Adults, Children |
| `H3` / `HJ` | Buildings / contents excess and no-claims discount (only included when that cover is selected) |
| `HN` | Proposer title, surname, forenames, date of birth, occupation |

**Constraints**
- **Occupation** must exactly match a value on the approved occupation list. Anything else is sent as `Unspecified`.
- **Housetype** is always sent as `Semi-Detached House`, the only value confirmed by Open GI so far.
- **NOTES** is limited to 60 characters.
- **Not yet mapped:** Property Ownership, Previous Claims and Year of Build. These are only kept in NOTES when they fit.

---

## Setup

### Requirements
- Windows with .NET Framework 4.8
- Visual Studio (or its MSBuild). NuGet packages are restored from `packages.config`.
- Network access to the SQL Server instance and to `openinterchange.co.uk`
- An Azure AD app registration with Graph **Mail.ReadWrite** (application) permission on the mailbox

### 1. Credentials
Credentials are **not** stored in the repository.
1. Copy `PartnerIntroductionsImporter/secrets.sample.config` to `PartnerIntroductionsImporter/secrets.config`.
2. Fill in every value (Graph tenant/client/secret, InStream branch/MARS reference/B-number/licence key, both SQL connection strings).
3. `secrets.config` is git-ignored and is copied next to the exe on build.

### 2. Database
Run the SQL scripts against the `[Phone System]` database:
- `AddPolicyLinkColumns.sql` adds Title, FirstName, LastName, Product, CoverDate, PropertyUse and Source to `dbo.PartnerLeads`. The script is safe to re-run.

### 3. Build
Open `PartnerIntroductionsImporter.slnx` in Visual Studio and build, or run:
```
MSBuild.exe PartnerIntroductionsImporter\PartnerIntroductionsImporter.csproj /p:Configuration=Release
```

---

## Running

| Command | What it does |
|---|---|
| `PartnerIntroductionsImporter.exe` | Normal run: Phase 1, then Phase 2 |
| `PartnerIntroductionsImporter.exe --check-config` | Checks that `secrets.config` has every required setting, then exits. Does not touch the mailbox, database or InStream |
| `PartnerIntroductionsImporter.exe --fix-postcodes` | Maintenance: re-reads the original emails for rows flagged `TEMP-FIX` and corrects their postcode |

Normally run on a schedule, for example every 15 minutes with Windows Task Scheduler.

> A normal run is **live**. Phase 2 submits every eligible `Pending` lead to Open GI.

---

## Logging and audit
- **Log files:** all output is written to `Logs\PartnerIntroductionsImporter_yyyyMMdd.log` next to the exe, one file per day, added to on each run. It includes each email's sender and whether it was accepted or skipped, the parsed PolicyLink fields, any warnings, the submitted XML, and the raw response on failure.
- **Database:** each `PartnerLeads` row keeps `XmlSubmitted`, `RawResponse`, `ErrorMessage`, `Attempts` and `LastAttemptDate`.
- Log files contain customer personal data. They are git-ignored and should be kept secure on the server.

---

## Project structure
```
PartnerIntroductionsImporter.slnx
AddPolicyLinkColumns.sql             # DB migration for PolicyLink support
docs/README.md                       # This document
PartnerIntroductionsImporter/
  Program.cs                         # All application logic
  App.config                         # Runtime config; loads secrets.config
  secrets.sample.config              # Credentials template (copy to secrets.config)
  packages.config                    # NuGet dependencies
```
