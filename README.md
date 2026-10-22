# New Part Code Request

Salesforce DX project that adds a **Part Code Request** object, its child **Part Code** object, and a
fully declarative screen flow (no custom code) to request one or more Part Codes at once.

## What is included

| Component | Purpose |
| --- | --- |
| `Part_Code_Request__c` | Parent object. Auto-number name `PKR-00001`. One custom field: **Approval Status** (Pending / Approved / Rejected, default Pending). |
| `Part_Code__c` | Child object (master-detail to Part Code Request). Auto-number name `PC-00001`. |
| Part Code fields | Product Name, Product Code, Product Family, Product Category (Text 255), Short Description (Text 255), Long Description (Long Text Area), Price (Americas), Price (EMEA), Cost (Currency, 2 decimals). |
| `New_Part_Code_Request` flow | Screen flow. One screen with a welcome message and a **Repeater** holding the Part Code fields; the user clicks **Add** for each extra Part Code and **Request** to submit. The flow creates the Part Code Request, then all Part Codes, and shows a link to the new request. |
| `New Part Code Request` global action | Global Quick Action (type Flow) that launches the flow from the global "+" menu in the Lightning header. It is added to the Global Publisher Layout (`Global-Global Layout`), which is a copy of the org layout plus this action. |
| `Part_Code_Request_Record_Page` | Lightning record page assigned as org default: highlights panel, Approval Status, and the Part Codes related list. |
| Page layouts | Part Code Request shows only Request Number, Approval Status and Owner plus the Part Codes related list. Part Code shows every field as editable. |
| `Part_Code_Requests` permission set | CRUD on both objects, all custom fields, the flow and the tab. |

## Deploy

```bash
sf project deploy start --source-dir force-app --target-org <alias>
sf org assign permset --name Part_Code_Requests --target-org <alias>
```

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
