public with sharing class PCRSectorDecision {

    public class Request {
        @InvocableVariable(required=true) public Id sectorId;
        @InvocableVariable(required=true) public String decision; // 'Approved' | 'Changes Requested'
        @InvocableVariable public String comments;
    }
    public class Result {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String errorMessage;
    }

    private static final Set<String> OWNED_QUERY_FIELDS = new Set<String>{
        'Cost__c','Price_Americas__c','Price_EMEA__c','Product_Code__c',
        'Product_Family__c','License_Conversion__c','Entitlement_Conversion__c','Asset_Conversion__c'
    };

    // Owned fields that are OPTIONAL to approve: they still write back to the parent when
    // filled, but a blank value does NOT block the sector's approval. The conversion
    // picklists (Commissioning's Asset, Licensing's License/Entitlement) are optional.
    private static final Set<String> OPTIONAL_OWNED_FIELDS = new Set<String>{
        'Asset_Conversion__c','License_Conversion__c','Entitlement_Conversion__c'
    };

    @InvocableMethod(label='PCR Sector Decision'
        description='Applies Approve / Request Changes; enforces owned fields before Approved.')
    public static List<Result> apply(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) return results;

        Set<Id> ids = new Set<Id>();
        for (Request r : requests) ids.add(r.sectorId);

        String soql = 'SELECT Id, Definition__c, ' + String.join(new List<String>(OWNED_QUERY_FIELDS), ', ')
            + ' FROM PCR_Sector__c WHERE Id IN :ids';
        Map<Id, PCR_Sector__c> byId = new Map<Id, PCR_Sector__c>((List<PCR_Sector__c>) Database.query(soql));

        List<PCR_Sector__c> toUpdate = new List<PCR_Sector__c>();
        for (Request r : requests) {
            Result res = new Result(); res.success = true;
            PCR_Sector__c child = byId.get(r.sectorId);
            if (child == null) { res.success = false; res.errorMessage = 'Sector record not found'; results.add(res); continue; }

            if (r.decision == 'Approved') {
                List<String> missing = new List<String>();
                for (String f : PCRSectorDefinitions.ownedFields(child.Definition__c)) {
                    if (OPTIONAL_OWNED_FIELDS.contains(f)) continue; // optional -> never blocks approval
                    if (child.get(f) == null) missing.add(f);
                }
                if (!missing.isEmpty()) {
                    res.success = false;
                    res.errorMessage = 'Complete these fields before approving: ' + String.join(missing, ', ');
                    results.add(res);
                    continue;
                }
            }

            child.Status__c = r.decision;
            child.Approver__c = UserInfo.getUserId();
            child.Decision_Date__c = System.now();
            if (String.isNotBlank(r.comments)) child.Comments__c = r.comments;
            toUpdate.add(child);
            results.add(res);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
        return results;
    }
}