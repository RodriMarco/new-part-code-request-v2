# New Part Code Request

Salesforce DX project that adds a **Product Code Request** object, its child **Part Code** object, and a
fully declarative screen flow (no custom code) to request one or more Part Codes at once.

## What is included

| Component | Purpose |
| --- | --- |
| `Product_Code_Request__c` | Parent object. Auto-number name `PCR-00001`. One custom field: **Approval Status** (Pending / Approved / Rejected, default Pending). |
| `Part_Code__c` | Child object (master-detail to Product Code Request). Auto-number name `PC-00001`. |
| Part Code fields | Product Name, Product Code, Product Family, Product Category (Text 255), Short Description (Text 255), Long Description (Long Text Area), Price (Americas), Price (EMEA), Cost (Currency, 2 decimals). |
| `New_Part_Code_Request` flow | Screen flow. One screen with a welcome message and a **Repeater** holding the Part Code fields; the user clicks **Add** for each extra Part Code and **Request** to submit. The flow creates the Product Code Request, then all Part Codes, and shows a link to the new request. |
| `New Part Code Request` list button | List-view button on Product Code Requests that launches the flow (`/flow/New_Part_Code_Request`). |
| `Product_Code_Request_Record_Page` | Lightning record page assigned as org default: highlights panel, Approval Status, and the Part Codes related list. |
| Page layouts | Product Code Request shows only Request Number, Approval Status and Owner plus the Part Codes related list. Part Code shows every field as editable. |
| `Part_Code_Requests` permission set | CRUD on both objects, all custom fields, the flow and the tab. |

## Deploy

```bash
sf project deploy start --source-dir force-app --target-org <alias>
sf org assign permset --name Part_Code_Requests --target-org <alias>
```

Then add the **Product Code Requests** tab to the Lightning app of your choice (App Manager) and open it.
The **New Part Code Request** button appears on the list view.

## Relationship with PCR v1

The rpmdev sandbox already contains the original implementation (PCR v1): a flat `Product_Code_Request__c`
with 49 fields, 25 `PCR_*` flows, Apex and per-sector approvals. A read-only copy is kept in
[`reference/pcr-v1`](reference/pcr-v1/README.md) for consultation; it is never deployed.

v2 reuses the `Product_Code_Request__c` API name as the parent and adds the `Part_Code__c` child. Deploying
v2 on top of v1 therefore *merges* into the existing object (it adds `Approval_Status__c`, the list button,
the child object, and replaces the page layout and the record page). v1's record-triggered flows stay active
and will fire on records created by the v2 flow until they are retired.

Validate without saving:

```bash
sf project deploy start --source-dir force-app --target-org <alias> --dry-run --ignore-conflicts
```

## Notes

- Product Name and Product Code are required inside the repeater so empty Part Codes are never created.
  Every other field is optional.
- The Repeater component requires Flow API 60.0 or later (Summer '24+).
