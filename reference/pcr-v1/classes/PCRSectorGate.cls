public with sharing class PCRSectorGate {

    private static final Set<String> OWNED_QUERY_FIELDS = new Set<String>{
        'Cost__c','Price_Americas__c','Price_EMEA__c','Product_Code__c',
        'Product_Family__c','License_Conversion__c','Entitlement_Conversion__c','Asset_Conversion__c'
    };

    @InvocableMethod(label='PCR Sector Gate Evaluate'
        description='Writes approved child fields to the parent and transitions the PCR stage.')
    public static void evaluate(List<Id> changedChildIds) {
        if (changedChildIds == null || changedChildIds.isEmpty()) return;

        Set<Id> pcrIds = new Set<Id>();
        for (PCR_Sector__c c : [SELECT PCR__c FROM PCR_Sector__c WHERE Id IN :changedChildIds]) {
            if (c.PCR__c != null) pcrIds.add(c.PCR__c);
        }
        if (pcrIds.isEmpty()) return;

        String childSoql = 'SELECT Id, PCR__c, Round__c, Status__c, Definition__c, '
            + String.join(new List<String>(OWNED_QUERY_FIELDS), ', ')
            + ' FROM PCR_Sector__c WHERE PCR__c IN :pcrIds';
        Map<Id, List<PCR_Sector__c>> childrenByPcr = new Map<Id, List<PCR_Sector__c>>();
        for (PCR_Sector__c c : Database.query(childSoql)) {
            if (!childrenByPcr.containsKey(c.PCR__c)) childrenByPcr.put(c.PCR__c, new List<PCR_Sector__c>());
            childrenByPcr.get(c.PCR__c).add(c);
        }

        Map<Id, Product_Code_Request__c> pcrs = new Map<Id, Product_Code_Request__c>([
            SELECT Id, Stage__c, Return_Stage__c FROM Product_Code_Request__c WHERE Id IN :pcrIds
        ]);

        List<Product_Code_Request__c> updates = new List<Product_Code_Request__c>();

        for (Id pcrId : childrenByPcr.keySet()) {
            Product_Code_Request__c pcr = pcrs.get(pcrId);
            if (pcr == null) continue;
            // Never reopen or re-transition a finished/cancelled request.
            if (pcr.Stage__c == 'Live' || pcr.Stage__c == 'Cancelled') continue;

            // The round "in play" is derived from the current stage OR (when already in
            // Revisions) from the stage we will return to. Both the review stage and the
            // post-round "done" stage map to the same round, so a Changes Requested after
            // the round already advanced still reopens it.
            String activeStage = (pcr.Stage__c == 'Revisions Needed') ? pcr.Return_Stage__c : pcr.Stage__c;
            String round = roundForStage(activeStage);
            if (round == null) continue;

            String review = reviewStage(round);
            String done = doneStage(round);

            Product_Code_Request__c upd = new Product_Code_Request__c(Id = pcrId);
            Boolean dirty = false;
            Integer total = 0, pending = 0, changes = 0;

            for (PCR_Sector__c c : childrenByPcr.get(pcrId)) {
                if (c.Round__c != round) continue;
                total++;
                if (c.Status__c == 'Pending') pending++;
                else if (c.Status__c == 'Changes Requested') changes++;
                else if (c.Status__c == 'Approved') {
                    for (String f : PCRSectorDefinitions.ownedFields(c.Definition__c)) {
                        upd.put(f, c.get(f));
                        dirty = true;
                    }
                }
            }
            if (total == 0) continue;

            if (changes > 0) {
                // A sector flagged a problem -> back to Revisions Needed and re-review the round.
                // (Works even if the round had already advanced past its review stage.)
                if (pcr.Stage__c != 'Revisions Needed') {
                    upd.Stage__c = 'Revisions Needed';
                    upd.Return_Stage__c = review;
                    dirty = true;
                }
            } else if (pending == 0) {
                upd.Stage__c = done;
                dirty = true;
            } else if (pcr.Stage__c == 'Revisions Needed') {
                upd.Stage__c = review; // changes resolved, back into the review round
                dirty = true;
            }

            if (dirty) updates.add(upd);
        }

        if (!updates.isEmpty()) update updates;
    }

    private static String roundForStage(String stage) {
        if (stage == 'Sandbox Approval' || stage == 'Sandbox Load Pending') return 'R1';
        if (stage == 'Testing' || stage == 'Production Migration Pending') return 'R2';
        return null;
    }
    private static String reviewStage(String round) { return round == 'R1' ? 'Sandbox Approval' : 'Testing'; }
    private static String doneStage(String round)   { return round == 'R1' ? 'Sandbox Load Pending' : 'Production Migration Pending'; }
}