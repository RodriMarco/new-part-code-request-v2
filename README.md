# New Part Code Request

Salesforce DX project that adds a **Part Code Request** object, its child **Part Code** object, and a
fully declarative screen flow (no custom code) to request one or more Part Codes at once.

## What is included

| Component | Purpose |
| --- | --- |
| `Part_Code_Request__c` | Parent object. Auto-number name `PKR-00001`. One custom field: **Approval Status** (Pending / Approved / Rejected, default Pending). |
| `Part_Code__c` | Child object (master-detail to Part Code Request). Auto-number name `PC-00001`. |
| Part Code fields | Product Name, Product Code (Text 255), Product Family and Product Category (restricted picklists mirroring the Product2 Family and Product Category values), Short Description (Text 255), Long Description (Long Text Area), Price (Americas), Price (EMEA), Cost (Currency, 2 decimals). Tracking fields: Product (lookup), Build Status, Build Error, Sandbox Product2 Id / URL, Prod Part Code Id. |
| `New_Part_Code_Request` flow | Screen flow. One screen with a welcome message and a **Repeater** holding the Part Code fields; the user clicks **Add** for each extra Part Code and **Request** to submit. The flow creates the Part Code Request, then all Part Codes, and shows a link to the new request. |
| `New Part Code Request` global action | Global Quick Action (type Flow) that launches the flow from the global "+" menu in the Lightning header. It is added to the Global Publisher Layout (`Global-Global Layout`), which is a copy of the org layout plus this action. |
| `Part_Code_Request_Record_Page` | Lightning record page assigned as org default: highlights panel, Approval Status, and the Part Codes related list. |
| Page layouts | Part Code Request shows only Request Number, Approval Status and Owner plus the Part Codes related list. Part Code shows every field as editable. |
| `Part_Code_Requests` permission set | Requesters: CRUD on both objects, the request fields, the flow and the tab. Build/sandbox tracking fields are read-only. |
| `PKR_Admin` permission set + `PKR_Deploy_Products` custom permission | Admins: everything above plus the three product actions below. The actions are only visible on the record page with this custom permission, and each flow re-checks it. |
| `Send to Sandbox` action | `PKR_Send_To_Sandbox` flow calls `PKRSandboxBridge` (Apex): copies the approved request and its Part Codes to the sandbox through the `PCR_Sandbox` named credential (composite tree REST call). In the sandbox, the record-triggered flow `PKR_Build_Replicated_Part_Code` builds every Part Code that arrives with a `Prod Part Code Id`. |
| `Load Sandbox Build` action | `PKR_Load_Sandbox_Build` flow calls `PKRSandboxBuildLoader` (Apex): queries the sandbox for the products built for the request (`Product2.Source_PCR_Id__c` = production Part Code Id) and writes their Id and URL into each Part Code. |
| `Deploy to Production` action | `PKR_Deploy_To_Production` flow: for every Part Code of the approved request, runs `PKR_Build_Part_Code` in the current org and shows a summary (created / skipped / errors). |
| `PKR_Approval__c` object | Child of Part Code Request ("Approvals" related list). Fields: Sector, Approver (User), Status (Pending / Approved / Rejected), Decision By, Decision Date, Comments, Round, Previous Decisions. Validation rule: only the assigned approver (or a PKR admin) can approve or reject. |
| `PKR_Approver_Definition__mdt` custom metadata | Who approves. One active record per sector with the approver's production username (matched with "starts with", so it also resolves sandbox usernames). Current definitions: Finance (Francesco Mignano), Pre-Sales (Julien Manchoulas), Services (Jason Awerman), Services (Jason Toliopoulos), Sales Americas (Steve Papadakis), Sales EMEA (Alain Polgar), Licensing (Constanza Competiello) and Product Manager (no username: created unassigned, the request creator or a System Administrator picks the approver, who is then notified). Edit in Setup > Custom Metadata Types. |
| `PKR_Create_Approvals` flow | Record-triggered on request creation (skips sandbox replicas): creates one Pending approval per active definition and sends a `PKR Notifications` bell notification to each approver. |
| `PKR_Approval_Stamp_Decision` flow | Before-save on approvals: when Status becomes Approved or Rejected, fills Decision By and Decision Date; when it goes back to Pending, clears them. |
| `PKR_Approval_Gate` flow | After-save on approvals: sets the request Approval Status to Rejected if any approval is rejected, Approved when none is pending, otherwise Pending. |
| `Resend Approvals` action | `PKR_Resend_Approvals` flow (UI) over `PKR_Resend_Rejected_Approvals` (autolaunched): rejected approvals go back to Pending in a new round, the rejection is appended to Previous Decisions, the request returns to Pending and the approvers are notified again. |
| `PKR_Approver` permission set + `PKR_Approve_Any` custom permission | Approvers: read requests and part codes, and approve or reject **any** approval (not only their own). Assigned to the seven approvers plus Sebastian Berdichevsky, Mike Crawford and Rodrigo Marco. Without the custom permission a user can only decide the approvals assigned to them. |
| `PKR_Build_Part_Code` flow | Builds one Part Code: creates the active Product2 (USD, list pricing, Family, Product Category, Short Description, Long Description truncated to 5000 chars, `Source_PCR_Id__c` = Part Code Id), then the pricebook entries and CPQ costs. Idempotent: skips Part Codes that already have a Product and reuses a Product2 with the same source Id. Errors are stored on the Part Code (`Build Status` = Error, `Build Error`). |
| `PKR_Multipricebook_STANDARD_entries_creation`, `PKR_Multipricebook_entries_creation`, `PKR_Cost_entries_creation` | Copies of the v1 `PCR_*` subflows, renamed so v1 can be deleted later. Standard Price Book entries per currency (from Price Americas, or Price EMEA when Americas is blank); "ChyronHego Price Book - USD" entry from Price Americas; "ChyronHego Price Book MULTI-CURRENCY" entries per currency from Price EMEA converted with the org rates; `SBQQ__Cost__c` per currency from Cost. Each pricing/cost input is skipped when blank, and DML failures are reported back through an `ErrorMessage` output. |

## Deploy

```bash
sf project deploy start --source-dir force-app --target-org <alias>
sf org assign permset --name Part_Code_Requests --target-org <alias>
sf org assign permset --name PKR_Admin --target-org <alias>      # admins only
sf org assign permset --name PKR_Approver --target-org <alias> --on-behalf-of <approver>
```

Deploy the same metadata to the sandbox that receives requests (bizops) so `PKR_Build_Replicated_Part_Code` and the
`PKR_*` subflows exist there. The `PCR_Sandbox` named credential in production must point to that sandbox.

The **New Part Code Request** action appears in the global "+" menu of the Lightning header. Optionally add the
**Part Code Requests** tab to a Lightning app (App Manager) to browse the requests.

## Relationship with PCR v1

The rpmdev sandbox already contains the original implementation (PCR v1): a flat `Product_Code_Request__c`
with 49 fields, 25 `PCR_*` flows, Apex and per-sector approvals. A read-only copy is kept in
[`reference/pcr-v1`](reference/pcr-v1/README.md) for consultation; it is never deployed.

v2 is deployed as a **separate** object, `Part_Code_Request__c` ("Part Code Request", `PKR-` auto-number), with
its own child `Part_Code__c`, so it coexists with v1 without touching it. Once v2 is accepted, v1 can be retired
(objects, flows, Apex, groups and custom metadata listed in the reference README). Some v1 flows, such as
`PCR_Create_Product` and `PCR_Autolaunch_Product_Creation`, may be adapted to create the Product2 records from
Part Codes.

Validate without saving:

```bash
sf project deploy start --source-dir force-app --target-org <alias> --dry-run --ignore-conflicts
```

## Notes

- Product Name and Product Code are required inside the repeater so empty Part Codes are never created.
  Every other field is optional.
- The Repeater component requires Flow API 60.0 or later (Summer '24+).
- Product build order per Part Code: Product2 -> Standard Price Book entries -> ChyronHego pricebook entries -> costs.
  A Part Code whose product already exists is skipped entirely, so re-running Deploy to Production never duplicates
  products or entries (pricing that failed on the first run must be fixed by hand or by clearing the Product lookup
  and deleting the product).
- Component / platform configuration (CPQ product options, hierarchy level, conversions) is intentionally not
  automated in v2; it is done by hand on the product.
