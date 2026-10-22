@IsTest
private class PCRSectorDecisionTest {

    private static PCR_Sector__c financeChild() {
        Product_Code_Request__c p = new Product_Code_Request__c(
            Product_Name__c='T', Type__c='Product', Category__c='Stand-alone',
            Short_Description__c='x', Hardware_Software__c='HW', Stage__c='Draft');
        insert p;
        PCR_Sector__c c = new PCR_Sector__c(PCR__c=p.Id, Sector__c='Finance', Round__c='R1',
            Status__c='Pending', Definition__c='Finance');
        insert c;
        return c;
    }

    private static PCRSectorDecision.Request req(Id id, String decision) {
        PCRSectorDecision.Request r = new PCRSectorDecision.Request();
        r.sectorId = id; r.decision = decision; r.comments = 'note';
        return r;
    }

    @IsTest static void blocksApproveWhenOwnedFieldBlank() {
        PCR_Sector__c c = financeChild(); // Cost__c is blank
        Test.startTest();
        List<PCRSectorDecision.Result> res = PCRSectorDecision.apply(new List<PCRSectorDecision.Request>{ req(c.Id, 'Approved') });
        Test.stopTest();
        System.assertEquals(false, res[0].success);
        System.assertEquals('Pending', [SELECT Status__c FROM PCR_Sector__c WHERE Id = :c.Id].Status__c);
    }

    @IsTest static void approvesWhenOwnedFieldFilled() {
        PCR_Sector__c c = financeChild();
        c.Cost__c = 5; update c;
        Test.startTest();
        List<PCRSectorDecision.Result> res = PCRSectorDecision.apply(new List<PCRSectorDecision.Request>{ req(c.Id, 'Approved') });
        Test.stopTest();
        System.assertEquals(true, res[0].success);
        PCR_Sector__c after = [SELECT Status__c, Approver__c, Decision_Date__c FROM PCR_Sector__c WHERE Id = :c.Id];
        System.assertEquals('Approved', after.Status__c);
        System.assertEquals(UserInfo.getUserId(), after.Approver__c);
        System.assertNotEquals(null, after.Decision_Date__c);
    }

    @IsTest static void requestChangesNeedsNoOwnedFields() {
        PCR_Sector__c c = financeChild();
        Test.startTest();
        List<PCRSectorDecision.Result> res = PCRSectorDecision.apply(new List<PCRSectorDecision.Request>{ req(c.Id, 'Changes Requested') });
        Test.stopTest();
        System.assertEquals(true, res[0].success);
        System.assertEquals('Changes Requested', [SELECT Status__c FROM PCR_Sector__c WHERE Id = :c.Id].Status__c);
    }

    @IsTest static void approvesCommissioningWithBlankOptionalField() {
        // Commissioning owns Asset_Conversion__c, which is OPTIONAL -> a blank value must NOT block approval.
        Product_Code_Request__c p = new Product_Code_Request__c(
            Product_Name__c='T', Type__c='Product', Category__c='Stand-alone',
            Short_Description__c='x', Hardware_Software__c='HW', Stage__c='Draft');
        insert p;
        PCR_Sector__c c = new PCR_Sector__c(PCR__c=p.Id, Sector__c='Commissioning', Round__c='R1',
            Status__c='Pending', Definition__c='Commissioning'); // Asset_Conversion__c left blank
        insert c;
        Test.startTest();
        List<PCRSectorDecision.Result> res = PCRSectorDecision.apply(new List<PCRSectorDecision.Request>{ req(c.Id, 'Approved') });
        Test.stopTest();
        System.assertEquals(true, res[0].success, 'blank optional conversion field must not block approval');
        System.assertEquals('Approved', [SELECT Status__c FROM PCR_Sector__c WHERE Id = :c.Id].Status__c);
    }
}