# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Workflow rule

Development is driven by the user's requirements document. Make code changes only when the user asks for them. Explaining the code and answering questions about it is fine at any time.

## What this is

Partner Introductions Importer: a .NET Framework 4.8 console app for Thamesbank Insurance. It reads partner referral emails from a shared mailbox, saves each lead to SQL Server, and imports it into the Open GI back office (Open Interchange / InStream) as a household prospect and policy.

- Solution: `PartnerIntroductionsImporter.slnx` → `PartnerIntroductionsImporter/PartnerIntroductionsImporter.csproj` (old-style csproj, NuGet via `packages.config`, packages in `packages/`)
- All logic is in one file: `PartnerIntroductionsImporter/Program.cs` (including the `LeadDetails` / `StagedLead` models at the bottom)
- Key libraries: Microsoft.Graph 6.5.0, Azure.Identity 1.21.0, Microsoft.Data.SqlClient / System.Data.SqlClient
- Build/run in Visual Studio or with `msbuild`. This is not an SDK-style project, so `dotnet run` (mentioned in a code comment) may not work. On this machine use the VS MSBuild (`C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe`). The SSMS copy that `vswhere -latest` finds can't build C#.
- There are no tests and no git repository yet. Back up `Program.cs` before making changes.
- Parsers can be tested offline by loading `bin\Debug\PartnerIntroductionsImporter.exe` in PowerShell and calling the private static methods (`ParsePolicyLinkLead`, `ParseLeadFromEmail`, `BuildApmImportXml`) by reflection. This needs no database or mailbox access.

## How it runs

`Main` (no arguments) runs two phases in order:

1. **`StageIncomingEmails`**: gets messages from the last `EMAIL_LOOKBACK_DAYS` (1 day) in **Inbox and JunkEmail** through Graph (app-only `ClientSecretCredential`). It only keeps emails where the mailbox is in **Cc**, parses the body with `ParseLeadFromEmail`, and inserts a row into `[Phone System].dbo.PartnerLeads` with `Status='Pending'`. It deduplicates on `EmailId` and then marks the email as read (a failure to mark read is only a warning).
2. **`ProcessPendingLeads`**: selects `Pending` rows received more than 15 minutes ago. For each one:
   - Runs a duplicate check against `[Thamesbank].dbo.ic_Daprospect` matching on **Email AND Tel AND Postcode** (the comment above `FindExistingProspect` wrongly says "Name"). A match sets `Status='AlreadyQuoted'` and the existing Refno, and the lead is not sent.
   - Otherwise it calls `BuildApmImportXml` → `SubmitToInStream` (SOAP `inStreamMessage`) → `ParseInStreamResponse` → `UpdateLeadResult`, which stores Success/Failed, `EpaProspectRef` / `EpaPolicyRef`, and the raw request and response for audit.

`--fix-postcodes` argument: maintenance mode (`FixStalePostcodes`). It re-reads the original email for rows with `PostCode = 'TEMP-FIX'` and re-runs `GetPostCode`.

`UpdateProspectSources` (the old "Phase 3") is no longer called. The source is now sent in the XML as `<SOURCE>`, worked out from the email subject using `KnownSources`. The method is kept only for manual catch-up on old records.

## PolicyLink leads

- **Picked up when** the email is From `leads@policylink.co.uk` (`POLICYLINK_SENDER`) and the mailbox is in **To** (`IsPolicyLinkEmail`). All other partners still need the mailbox in Cc.
- They use a `Label:    value` format and are parsed by `ParsePolicyLinkLead` / `GetColonFieldValue`, which match labels at the start of a line.
- Source is always `IRevolution` (`POLICYLINK_SOURCE`). Product is still sent as `HQ`, whatever the `Product` line says.
- **Postcode:** `Property Postcode` is used for both PCODE and the risk/correspondence postcode. The proposer's postcode is only a fallback and is never stored separately.
- **Address:** Address3, Address4 and City are combined into Address3.
- **Cover:** `Cover Level` maps to Buildings / Contents / Buildings & Contents.
- **Property Value** → buildings sum insured. The "Property Type X: Yes" flags are stored in PropertyType, but Housetype is still the fixed default.
- **Name:** Title / FirstName / LastName are stored separately and sent as-is (no `SplitName`), so multi-word surnames stay intact.
- New columns are added by `AddPolicyLinkColumns.sql`: Title, FirstName, LastName, Product, CoverDate, PropertyUse, Source. `Source` is now filled at staging time for every lead. Phase 2 falls back to matching the subject line for older rows.

## Logging

All console output is also written to `Logs\PartnerIntroductionsImporter_yyyyMMdd.log` next to the exe (`TeeWriter`, appended per day). Phase 2 logs the submitted XML, and the raw response on failure. The database also keeps `XmlSubmitted` / `RawResponse` for each lead.

## Email parsing

- `PreprocessEmailBody` converts HTML to plain text with line breaks.
- `GetFieldValue(body, "Label")` finds `Label -` or `Label-` and takes the rest of that line.
- `GetPostCode` also handles `Post CodeBT12 4LW` (no separator) with a UK postcode regex.
- Missing fields fall back to the `DEFAULT_*` constants at the top of `Program`.

## Open GI XML mapping (confirmed by live testing; see header comment in Program.cs)

| Section | Fields |
|---|---|
| `APMCLIENT/P.CM` | NAME, ADDR1-3, PCODE, TEL, EMAIL, SOURCE, NOTES (REFNO omitted, created by the back office) |
| `APMPOL/P.PY` | PTYPE = `HQ` (household) |
| `HW` | risk and correspondence address, Buildings/Contents/Specitems Yes/No, sums insured |
| `H1` | Housetype, Bedrooms, Adults, Children |
| `H3` / `HJ` | buildings / contents excess and no-claims discount (only included when that cover is selected) |
| `HN` | proposer title/surname/forenames/DOB, Occtype1 |

Important constraints:
- **Occtype1** must exactly match a value in `ValidOccupations`. Anything else is changed to `"Unspecified"`. Values like "Employed" and "Self-Employed" are rejected by Open GI.
- **Housetype** is always `"Semi-Detached House"` (`NormalizeHousetype`). It is the only value confirmed to be accepted. Don't widen this without confirmation from Open GI.
- **NOTES** is limited to 60 characters. Unmapped fields (ownership, previous claims, year built, possessions) are only added when they fit.
- Not yet mapped: Property Ownership, Previous Claims, Year of Build.

## PartnerLeads statuses

`Pending` → `Success` | `Failed` | `AlreadyQuoted` (`Success-SourceSet` comes from the old Phase 3). The `Attempts` and `LastAttemptDate` columns are updated on each processing attempt.

## Conventions

- Plain `static` methods on `Program`, `async`/`await`, raw parameterised `SqlCommand` (no ORM), and `Console.WriteLine` for logging.
- `Truncate` values to their column lengths before inserting into the database.
- Each step catches its own errors so that one bad lead or email doesn't stop the whole run.

## Security note

All credentials (Graph tenant/client/secret, InStream branch/MARS ref/B-number/licence key, both SQL connection strings) are in **`PartnerIntroductionsImporter/secrets.config`**. That file is **git-ignored** and must never be committed or copied into docs, logs or external tools.
- `App.config` merges it in with `<appSettings file="secrets.config" />`. The csproj copies it next to the exe on build, if it exists.
- `secrets.sample.config` is the committed template with blank values. When adding a new credential, add it to both files and to `RequiredSettings` in `Program.cs`.
- The code reads settings through `Setting(key)`. `Run` refuses to start if any required setting is missing. `PartnerIntroductionsImporter.exe --check-config` checks the config and exits without touching the mailbox, database or InStream.
- `*.bak*` backups, `Logs/` (which contain customer personal data), `bin/`, `obj/`, `.vs/` and `packages/` are also git-ignored.
