# PCR v1 reference (retrieved from the rpmdev sandbox)

Read-only snapshot of the original **Product Code Request (PCR) v1** implementation, retrieved from
`chyronhego--rpmdev.sandbox.my.salesforce.com` on 2026-10-22. It is kept here so the team can consult
how v1 works while v2 (`force-app/`) is built. Nothing in this folder is deployed: `reference/**` is
listed in `.forceignore` and the folder is not a package directory in `sfdx-project.json`.

## What v1 does (high level)

v1 is a **flat** object: one Product Code Request = one product. The product data (Product Name,
Product Code, Product Family, Short/Long Description, Price (Americas), Price (EMEA), Cost, ...) lives
directly on `Product_Code_Request__c` (49 custom fields). A request moves through `Stage__c`:

Draft -> Sandbox Approval -> Revisions Needed / Sandbox Load Pending -> Testing -> Production Approval
-> Production Migration Pending -> Live (or Cancelled)

Approvals are done per **sector** (`PCR_Sector__c` child records, one per approver group, driven by
`PCR_Sector_Definition__mdt` custom metadata and the `PCR_*_Approvers` public groups) in two rounds
(R1 = sandbox, R2 = production). Once approved, Apex + flows create the `Product2` (and CPQ product
options / pricebook entries) in the sandbox, then replicate to production through
`PCRSandboxBridge` / `PCRProdCallback`.

## Contents

| Folder | What is in it |
| --- | --- |
| `objects/Product_Code_Request__c` | The v1 object, its 49 fields, 4 validation rules, list views, compact layout and buttons. |
| `objects/PCR_Sector__c` | Per-sector approval child object. |
| `objects/PCR_Sector_Definition__mdt` + `customMetadata/` | Sector definitions (which group approves what, in which round). |
| `objects/Product2`, `objects/sbaa__Approval__c` | Fields on other objects that v1 writes to or links from. |
| `flows/` | 25 flows. Entry point is the screen flow `PCR_New_Request` (launched by the `New_Product_Code_Request` quick action). Record-triggered flows on `Product_Code_Request__c`: `PCR_default_values_on_creation`, `PCR_Set_Requester`, `PCR_R1_Submit`, `PCR_R2_Submit`, `PCR_Trigger_Sandbox_Replicate`, `PCR_Supersession`, `PCR_Live_Closeout`. Product creation: `PCR_Create_Product`, `PCR_Autolaunch_Product_Creation`, `PCR_PO_Creation`, `PCR_Cost_entries_creation`, `PCR_Multipricebook_*`. Several `PCR_R1_*` / `PCR_R2_*` flows are Obsolete (superseded by the sector flows). |
| `classes/` | Apex: `PCRSectorGenerator`, `PCRSectorGate`, `PCRSectorDecision`, `PCRProductSupersession`, `PCRSupersessionScheduler`, `PCRSandboxBridge`, `PCRSandboxBuildPoller`, `PCRProdCallback`, `PCR_ExtController`, plus tests. |
| `layouts/`, `flexipages/`, `quickActions/`, `tabs/` | UI for the v1 request and sector records. |
| `permissionsets/` | `PCR_Requester`, `PCR_Approvers`, `PCR_Approval_Access`, `PCR_Operator`, `PCR_Sector_FLS`, `PCR_Integration_API`. |
| `groups/`, `notificationtypes/`, `workflows/`, `lwc/` | Approver groups, the `PCR_Notifications` custom notification, Product2 email alerts, and the UnofficialSF `fsc_*` flow components used by the screens. |

## Why it matters for v2

v2 keeps the same object API name `Product_Code_Request__c` as the parent but moves the product data to
a new child object `Part_Code__c`, so one request can hold many part codes. The v1 automation above is
still active in the sandbox and reacts to records on `Product_Code_Request__c`; see the project README
for how v2 coexists with it.
