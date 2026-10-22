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

## Notes

- Product Name and Product Code are required inside the repeater so empty Part Codes are never created.
  Every other field is optional.
- The Repeater component requires Flow API 60.0 or later (Summer '24+).
