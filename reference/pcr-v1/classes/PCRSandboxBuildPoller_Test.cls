@isTest
private class PCRSandboxBuildPoller_Test {

    // Sandbox GET returns no product yet -> loadSandboxBuild returns false, no PCR update (no downstream flows).
    private class MockEmptyQuery implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"totalSize":0,"done":true,"records":[]}');
            return res;
        }
    }

    private static Product_Code_Request__c makePcr(String stage, Boolean withPricing) {
        Product_Code_Request__c pcr = new Product_Code_Request__c(
            Product_Name__c = 'Poller Test', Type__c = 'Service', Category__c = 'Service',
            Stage__c = stage, Short_Description__c = 'x', Long_Description__c = 'y'
        );
        if (withPricing) {
            pcr.Price_Americas__c = 100;
            pcr.Price_EMEA__c = 100;
            pcr.Same_Pricing_All_Regions__c = false;
        }
        insert pcr;
        return pcr;
    }

    @isTest static void testLoadSandboxBuild_notReady() {
        Product_Code_Request__c pcr = makePcr('Draft', false);
        Test.setMock(HttpCalloutMock.class, new MockEmptyQuery());
        Test.startTest();
        Boolean found = PCRSandboxBridge.loadSandboxBuild(pcr.Id);
        Test.stopTest();
        System.assertEquals(false, found, 'No sandbox product yet -> returns false');
    }

    @isTest static void testInvocable() {
        Product_Code_Request__c pcr = makePcr('Draft', false);
        Test.setMock(HttpCalloutMock.class, new MockEmptyQuery());
        Test.startTest();
        PCRSandboxBuildPoller.loadSandboxBuildInvocable(new List<Id>{ pcr.Id });
        Test.stopTest();
        System.assert(true, 'invocable is callable');
    }

    @isTest static void testPollerRunsClean() {
        Product_Code_Request__c pcr = makePcr('Sandbox Load Pending', true);
        Test.setMock(HttpCalloutMock.class, new MockEmptyQuery());
        Test.startTest();
        new PCRSandboxBuildPoller().execute(null);
        Test.stopTest();
        Product_Code_Request__c reloaded = [SELECT Stage__c FROM Product_Code_Request__c WHERE Id = :pcr.Id];
        System.assertEquals('Sandbox Load Pending', reloaded.Stage__c, 'No product yet -> PCR stays pending');
    }
}