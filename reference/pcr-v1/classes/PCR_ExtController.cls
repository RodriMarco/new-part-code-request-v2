public with sharing class PCR_ExtController {

    private Id recordId;

    public PCR_ExtController(ApexPages.StandardController stdController) {
        this.recordId = stdController.getId();
    }

    public PageReference onSubmit() {
        if (recordId != null) {
            // Stage must change BEFORE generating R1 children so downstream automation sees the correct Stage.
            update new Product_Code_Request__c(Id = recordId, Stage__c = 'Sandbox Approval');
            PCRSectorGenerator.Request r = new PCRSectorGenerator.Request();
            r.pcrId = recordId; r.round = 'R1';
            PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ r });
        }
        return new PageReference('/' + recordId);
    }

    public PageReference onRecall() {
        if (recordId != null) {
            delete [SELECT Id FROM PCR_Sector__c WHERE PCR__c = :recordId AND Round__c = 'R1'];
            update new Product_Code_Request__c(Id = recordId, Stage__c = 'Draft');
        }
        return new PageReference('/' + recordId);
    }

    public PageReference onMigrate() {
        if (recordId != null) {
            PCRSandboxBridge.pullSandboxPcr(recordId);
        }
        return new PageReference('/' + recordId);
    }

    @InvocableMethod(label='PCR Submit For Approval'
        description='Creates the Round-2 sector children (called by the flow on Stage=Testing).')
    public static void submitForApproval(List<Id> pcrIds) {
        if (pcrIds == null) {
            return;
        }
        List<PCRSectorGenerator.Request> reqs = new List<PCRSectorGenerator.Request>();
        for (Id pcrId : pcrIds) {
            PCRSectorGenerator.Request r = new PCRSectorGenerator.Request();
            r.pcrId = pcrId; r.round = 'R2';
            reqs.add(r);
        }
        PCRSectorGenerator.generate(reqs);
    }
}