public with sharing class PCRSectorGenerator {

    public class Request {
        @InvocableVariable(required=true) public Id pcrId;
        @InvocableVariable(required=true) public String round;
    }

    @InvocableMethod(label='PCR Generate Sector Children'
        description='Creates one PCR_Sector__c per PCR_Sector_Definition__mdt for the round. Idempotent.')
    public static void generate(List<Request> requests) {
        if (requests == null || requests.isEmpty()) return;

        Map<Id, String> roundByPcr = new Map<Id, String>();
        for (Request r : requests) {
            if (r.pcrId != null && String.isNotBlank(r.round)) roundByPcr.put(r.pcrId, r.round);
        }
        if (roundByPcr.isEmpty()) return;

        Set<String> existing = new Set<String>();
        for (PCR_Sector__c c : [SELECT PCR__c, Definition__c FROM PCR_Sector__c WHERE PCR__c IN :roundByPcr.keySet()]) {
            existing.add(c.PCR__c + '|' + c.Definition__c);
        }

        List<PCR_Sector__c> toInsert = new List<PCR_Sector__c>();
        for (Id pcrId : roundByPcr.keySet()) {
            for (PCR_Sector_Definition__mdt d : PCRSectorDefinitions.forRound(roundByPcr.get(pcrId))) {
                if (existing.contains(pcrId + '|' + d.DeveloperName)) continue;
                toInsert.add(new PCR_Sector__c(
                    PCR__c = pcrId,
                    Sector__c = d.Sector__c,
                    Round__c = d.Round__c,
                    Status__c = 'Pending',
                    Approver_Group__c = d.Approver_Group__c,
                    Definition__c = d.DeveloperName
                ));
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }
}