@isTest
private class PCR_ExtControllerTests {

    private static Product_Code_Request__c makePcr(String suffix) {
        // Category__c='Stand-alone' — the live org's default record type only allows
        // Component/Stand-alone (Category__c='Service' is INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST).
        Product_Code_Request__c pcr = new Product_Code_Request__c(
            Product_Name__c = 'Test PCR ' + suffix,
            Type__c = 'Product',
            Category__c = 'Stand-alone',
            Hardware_Software__c = 'HW',
            Stage__c = 'Draft',
            Short_Description__c = 'Test short description',
            Long_Description__c = 'Test long description'
        );
        insert pcr;
        return pcr;
    }

    @isTest
    static void testSubmit() {
        Product_Code_Request__c pcr = makePcr('Submit');
        // Pricing_Required_Before_Submit validation rule requires pricing once Stage leaves Draft.
        pcr.Price_Americas__c = 100;
        pcr.Same_Pricing_All_Regions__c = true;
        update pcr;

        Test.startTest();
        PCR_ExtController con = new PCR_ExtController(new ApexPages.StandardController(pcr));
        PageReference ref = con.onSubmit();
        Test.stopTest();

        System.assertNotEquals(null, ref, 'onSubmit must return a PageReference');
        System.assert(ref.getUrl().contains(pcr.Id), 'PageReference should redirect to the source record');
        System.assertEquals('Sandbox Approval', [SELECT Stage__c FROM Product_Code_Request__c WHERE Id = :pcr.Id].Stage__c,
            'onSubmit must move Stage to Sandbox Approval');
        System.assertEquals(PCRSectorDefinitions.forRound('R1').size(),
            [SELECT COUNT() FROM PCR_Sector__c WHERE PCR__c = :pcr.Id],
            'onSubmit must create one R1 child per PCR_Sector_Definition__mdt');
    }

    @isTest
    static void testRecall() {
        Product_Code_Request__c pcr = makePcr('Recall');
        // Seed pre-existing R1 children the way onSubmit would have left them.
        PCRSectorGenerator.Request r = new PCRSectorGenerator.Request();
        r.pcrId = pcr.Id; r.round = 'R1';
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ r });

        Test.startTest();
        PCR_ExtController con = new PCR_ExtController(new ApexPages.StandardController(pcr));
        PageReference ref = con.onRecall();
        Test.stopTest();

        System.assertNotEquals(null, ref, 'onRecall must return a PageReference');
        System.assert(ref.getUrl().contains(pcr.Id), 'PageReference should redirect to the source record');
        System.assertEquals(0, [SELECT COUNT() FROM PCR_Sector__c WHERE PCR__c = :pcr.Id],
            'onRecall must delete the R1 children');
        System.assertEquals('Draft', [SELECT Stage__c FROM Product_Code_Request__c WHERE Id = :pcr.Id].Stage__c,
            'onRecall must reset Stage to Draft');
    }

    @isTest
    static void testNullRecordId() {
        Product_Code_Request__c emptyPcr = new Product_Code_Request__c();
        PCR_ExtController con = new PCR_ExtController(new ApexPages.StandardController(emptyPcr));
        PageReference submitRef = con.onSubmit();
        PageReference recallRef = con.onRecall();
        System.assertNotEquals(null, submitRef, 'onSubmit must return a PageReference even with null Id');
        System.assertNotEquals(null, recallRef, 'onRecall must return a PageReference even with null Id');
    }

    private class MockPullHit implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"totalSize":1,"done":true,"records":[{' +
                '"attributes":{"type":"Product_Code_Request__c","url":"/x"},' +
                '"Product_Name__c":"From Sandbox"' +
                '}]}');
            return res;
        }
    }

    @isTest
    static void testMigrate() {
        Product_Code_Request__c pcr = makePcr('Migrate');
        Test.setMock(HttpCalloutMock.class, new MockPullHit());

        Test.startTest();
        PCR_ExtController con = new PCR_ExtController(new ApexPages.StandardController(pcr));
        PageReference ref = con.onMigrate();
        Test.stopTest();

        System.assertNotEquals(null, ref, 'onMigrate must return a PageReference');
        System.assert(ref.getUrl().contains(pcr.Id), 'Should redirect to the source record');
        Product_Code_Request__c reloaded = [SELECT Product_Name__c, Production_Build_Triggered__c FROM Product_Code_Request__c WHERE Id = :pcr.Id];
        System.assertEquals('From Sandbox', reloaded.Product_Name__c);
        System.assertEquals(true, reloaded.Production_Build_Triggered__c);
    }

    @isTest
    static void testApprovalLookupExists() {
        Schema.DescribeFieldResult f = sbaa__Approval__c.Product_Code_Request__c.getDescribe();
        System.assertEquals('Product_Code_Request__c', f.getName(), 'sbaa Approval must have the PCR lookup');
    }

    @isTest
    static void testSubmitForApprovalInvocable() {
        Product_Code_Request__c pcr = makePcr('Invocable');

        Test.startTest();
        PCR_ExtController.submitForApproval(new List<Id>{ pcr.Id });
        Test.stopTest();

        System.assertEquals(PCRSectorDefinitions.forRound('R2').size(),
            [SELECT COUNT() FROM PCR_Sector__c WHERE PCR__c = :pcr.Id AND Round__c = 'R2'],
            'submitForApproval must create one R2 child per PCR_Sector_Definition__mdt');

        // null-safe path
        PCR_ExtController.submitForApproval(null);
        System.assert(true, 'submitForApproval is null-safe');
    }
}