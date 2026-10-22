public with sharing class PCRProductSupersession {

    @TestVisible
    private static Set<String> EXCLUDED_STAGES = new Set<String>{
        'Closed Won','Closed Cancelled','Closed Lost','Won by Sales','Closed Dead'
    };

    @InvocableMethod(label='PCR Product Supersession (go-live)'
        description='At Create Product: default Activation Date, reference + deactivate (if due) the replaced product, email affected opp owners.')
    public static void processAtGoLive(List<Id> pcrIds) {
        if (pcrIds == null || pcrIds.isEmpty()) return;

        List<Product_Code_Request__c> pcrs = [
            SELECT Id, Replaces__c, Replaces__r.Name, Activation_Date__c, Production_Product2_Id__c,
                   Product_Name__c, Old_Product_Deactivated__c
            FROM Product_Code_Request__c WHERE Id IN :pcrIds
        ];

        Map<Id, Product2> oldProdUpdates = new Map<Id, Product2>();
        List<Product_Code_Request__c> pcrUpdates = new List<Product_Code_Request__c>();
        Date today = Date.today();

        for (Product_Code_Request__c p : pcrs) {
            Product_Code_Request__c upd = new Product_Code_Request__c(Id = p.Id);
            Boolean dirty = false;

            Date activation = p.Activation_Date__c;
            if (activation == null) { activation = today; p.Activation_Date__c = today; upd.Activation_Date__c = today; dirty = true; }

            if (p.Replaces__c != null) {
                Product2 op = oldProdUpdates.get(p.Replaces__c);
                if (op == null) { op = new Product2(Id = p.Replaces__c); oldProdUpdates.put(p.Replaces__c, op); }
                if (String.isNotBlank(p.Production_Product2_Id__c)) {
                    op.Replaced_By__c = (Id) p.Production_Product2_Id__c;
                }
                if (activation <= today && !p.Old_Product_Deactivated__c) {
                    op.IsActive = false;
                    upd.Old_Product_Deactivated__c = true; dirty = true;
                }
            }
            if (dirty) pcrUpdates.add(upd);
        }

        if (!oldProdUpdates.isEmpty()) update oldProdUpdates.values();
        if (!pcrUpdates.isEmpty()) update pcrUpdates;

        notifyOwners(pcrs);
    }

    // Daily scheduler entry: deactivate old products whose Activation Date has arrived.
    public static void deactivateDue() {
        List<Product_Code_Request__c> due = [
            SELECT Id, Replaces__c FROM Product_Code_Request__c
            WHERE Replaces__c != null AND Old_Product_Deactivated__c = false
              AND Activation_Date__c <= :Date.today()
        ];
        if (due.isEmpty()) return;
        Map<Id, Product2> prods = new Map<Id, Product2>();
        List<Product_Code_Request__c> pcrUpdates = new List<Product_Code_Request__c>();
        for (Product_Code_Request__c p : due) {
            prods.put(p.Replaces__c, new Product2(Id = p.Replaces__c, IsActive = false));
            pcrUpdates.add(new Product_Code_Request__c(Id = p.Id, Old_Product_Deactivated__c = true));
        }
        update prods.values();
        update pcrUpdates;
    }

    private static void notifyOwners(List<Product_Code_Request__c> pcrs) {
        Set<Id> oldProductIds = new Set<Id>();
        for (Product_Code_Request__c p : pcrs) {
            if (p.Replaces__c != null) oldProductIds.add(p.Replaces__c);
        }
        if (oldProductIds.isEmpty()) return;

        // old product -> owner -> email
        Map<Id, Map<Id, String>> ownerEmailByOldProduct = new Map<Id, Map<Id, String>>();
        // old product -> owner -> list of affected opp names
        Map<Id, Map<Id, List<String>>> oppsByOwnerByOldProduct = new Map<Id, Map<Id, List<String>>>();
        // old product -> set of opp ids already counted (dedupe)
        Map<Id, Set<Id>> seenOppsByOldProduct = new Map<Id, Set<Id>>();

        for (SBQQ__QuoteLine__c ql : [
            SELECT SBQQ__Product__c,
                   SBQQ__Quote__r.SBQQ__Opportunity2__c,
                   SBQQ__Quote__r.SBQQ__Opportunity2__r.OwnerId,
                   SBQQ__Quote__r.SBQQ__Opportunity2__r.Owner.Email,
                   SBQQ__Quote__r.SBQQ__Opportunity2__r.Name
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Product__c IN :oldProductIds
              AND SBQQ__Quote__r.SBQQ__Opportunity2__c != null
              AND SBQQ__Quote__r.SBQQ__Opportunity2__r.StageName NOT IN :EXCLUDED_STAGES
        ]) {
            Id oldProductId = ql.SBQQ__Product__c;
            Id oppId = ql.SBQQ__Quote__r.SBQQ__Opportunity2__c;

            Set<Id> seenOpps = seenOppsByOldProduct.get(oldProductId);
            if (seenOpps == null) { seenOpps = new Set<Id>(); seenOppsByOldProduct.put(oldProductId, seenOpps); }
            if (seenOpps.contains(oppId)) continue;
            seenOpps.add(oppId);

            Id ownerId = ql.SBQQ__Quote__r.SBQQ__Opportunity2__r.OwnerId;
            String email = ql.SBQQ__Quote__r.SBQQ__Opportunity2__r.Owner.Email;
            String oppName = ql.SBQQ__Quote__r.SBQQ__Opportunity2__r.Name;
            if (String.isBlank(email)) continue;

            Map<Id, String> ownerEmail = ownerEmailByOldProduct.get(oldProductId);
            if (ownerEmail == null) { ownerEmail = new Map<Id, String>(); ownerEmailByOldProduct.put(oldProductId, ownerEmail); }
            ownerEmail.put(ownerId, email);

            Map<Id, List<String>> oppsByOwner = oppsByOwnerByOldProduct.get(oldProductId);
            if (oppsByOwner == null) { oppsByOwner = new Map<Id, List<String>>(); oppsByOwnerByOldProduct.put(oldProductId, oppsByOwner); }
            if (!oppsByOwner.containsKey(ownerId)) oppsByOwner.put(ownerId, new List<String>());
            oppsByOwner.get(ownerId).add(oppName);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Product_Code_Request__c p : pcrs) {
            if (p.Replaces__c == null) continue;

            Map<Id, String> ownerEmail = ownerEmailByOldProduct.get(p.Replaces__c);
            Map<Id, List<String>> oppsByOwner = oppsByOwnerByOldProduct.get(p.Replaces__c);
            if (oppsByOwner == null || oppsByOwner.isEmpty()) continue;

            String oldName = p.Replaces__r != null ? p.Replaces__r.Name : 'the previous product';
            String safeOldName = oldName != null ? oldName.escapeHtml4() : oldName;
            String safeNewName = p.Product_Name__c != null ? p.Product_Name__c.escapeHtml4() : p.Product_Name__c;
            for (Id ownerId : oppsByOwner.keySet()) {
                List<String> safeOppNames = new List<String>();
                for (String oppName : oppsByOwner.get(ownerId)) {
                    safeOppNames.add(oppName != null ? oppName.escapeHtml4() : oppName);
                }

                Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
                m.setToAddresses(new List<String>{ ownerEmail.get(ownerId) });
                m.setSubject('Product replaced: ' + oldName + ' -> ' + p.Product_Name__c);
                m.setHtmlBody('<p>The new product <b>' + safeNewName + '</b> replaces <b>' + safeOldName
                    + '</b>, used on your opportunit(y/ies): <b>' + String.join(safeOppNames, ', ')
                    + '</b>.</p><p>It activates on <b>' + String.valueOf(p.Activation_Date__c)
                    + '</b>. Please review and update your quotes.</p>');
                m.setSaveAsActivity(false);
                emails.add(m);
            }
        }
        if (!emails.isEmpty()) Messaging.sendEmail(emails, false);
    }
}