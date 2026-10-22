@isTest
private class PCRSandboxBridge_Test {

    private static Product_Code_Request__c makePcr() {
        Product_Code_Request__c pcr = new Product_Code_Request__c(
            Product_Name__c = 'Bridge Test',
            Type__c = 'Service',
            Category__c = 'Service',
            Stage__c = 'Sandbox Load Pending',
            Short_Description__c = 'short',
            Long_Description__c = 'long',
            Same_Pricing_All_Regions__c = true,
            Price_Americas__c = 100
        );
        insert pcr;
        return pcr;
    }

    private class MockCreated implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setBody('{"id":"a9xSANDBOXFAKE1","success":true,"errors":[]}');
            return res;
        }
    }

    @isTest
    static void replicate_success_returnsSandboxId() {
        Product_Code_Request__c pcr = makePcr();
        Test.setMock(HttpCalloutMock.class, new MockCreated());

        Test.startTest();
        String sandboxId = PCRSandboxBridge.replicatePcrToSandbox(pcr.Id);
        Test.stopTest();

        System.assertEquals('a9xSANDBOXFAKE1', sandboxId, 'Should return parsed sandbox Id');
        Product_Code_Request__c reloaded = [SELECT Sandbox_Sync_Error__c FROM Product_Code_Request__c WHERE Id = :pcr.Id];
        System.assertEquals(null, reloaded.Sandbox_Sync_Error__c, 'Success should clear sync error');
    }

    private class MockCapture implements HttpCalloutMock {
        public String capturedBody;
        public HttpResponse respond(HttpRequest req) {
            capturedBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setBody('{"id":"a9xSANDBOXFAKE1","success":true,"errors":[]}');
            return res;
        }
    }

    @isTest
    static void replicate_payload_excludesUserLookup() {
        // Requester__c is a User lookup. Prod User Ids do not resolve in the Bizops sandbox
        // (the user may not exist or be inactive there), so including it in the cross-org POST
        // causes INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY. The payload must omit it.
        Product_Code_Request__c pcr = makePcr();
        pcr.Requester__c = UserInfo.getUserId();
        update pcr;
        MockCapture mock = new MockCapture();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        PCRSandboxBridge.replicatePcrToSandbox(pcr.Id);
        Test.stopTest();

        System.assertNotEquals(null, mock.capturedBody, 'Callout should have fired and captured a body');
        System.assert(
            !mock.capturedBody.contains('Requester__c'),
            'Replication payload must NOT include the User lookup Requester__c (User Ids do not resolve cross-org). Body: ' + mock.capturedBody
        );
    }

    private class MockServerError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"internal"}');
            return res;
        }
    }

    @isTest
    static void replicate_serverError_writesErrorAndThrows() {
        Product_Code_Request__c pcr = makePcr();
        Test.setMock(HttpCalloutMock.class, new MockServerError());

        Boolean threw = false;
        Test.startTest();
        try {
            PCRSandboxBridge.replicatePcrToSandbox(pcr.Id);
        } catch (PCRSandboxBridge.BridgeException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw BridgeException on 500');
        Product_Code_Request__c reloaded = [SELECT Sandbox_Sync_Error__c FROM Product_Code_Request__c WHERE Id = :pcr.Id];
        System.assert(reloaded.Sandbox_Sync_Error__c != null && reloaded.Sandbox_Sync_Error__c.contains('500'),
            'Sandbox_Sync_Error__c should contain status 500');
    }

    private class MockQueryHit implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"totalSize":1,"done":true,"records":[{' +
                '"attributes":{"type":"Product_Code_Request__c","url":"/x"},' +
                '"Product_Name__c":"UPDATED NAME",' +
                '"Product_Code__c":"UPDATED-CODE",' +
                '"Short_Description__c":"Updated short",' +
                '"Long_Description__c":"Updated long",' +
                '"Price_Americas__c":999' +
                '}]}');
            return res;
        }
    }

    @isTest
    static void pull_success_overwritesFieldsAndSetsTrigger() {
        Product_Code_Request__c pcr = makePcr();
        Test.setMock(HttpCalloutMock.class, new MockQueryHit());

        Test.startTest();
        PCRSandboxBridge.pullSandboxPcr(pcr.Id);
        Test.stopTest();

        Product_Code_Request__c reloaded = [
            SELECT Product_Name__c, Product_Code__c, Short_Description__c, Price_Americas__c, Production_Build_Triggered__c, Last_Migrate_Error__c
            FROM Product_Code_Request__c WHERE Id = :pcr.Id
        ];
        System.assertEquals('UPDATED NAME', reloaded.Product_Name__c);
        System.assertEquals('UPDATED-CODE', reloaded.Product_Code__c);
        System.assertEquals('Updated short', reloaded.Short_Description__c);
        System.assertEquals(999, reloaded.Price_Americas__c);
        System.assertEquals(true, reloaded.Production_Build_Triggered__c);
        System.assertEquals(null, reloaded.Last_Migrate_Error__c);
    }

    private class MockQueryEmpty implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"totalSize":0,"done":true,"records":[]}');
            return res;
        }
    }

    @isTest
    static void pull_notFound_writesErrorAndThrows() {
        Product_Code_Request__c pcr = makePcr();
        Test.setMock(HttpCalloutMock.class, new MockQueryEmpty());

        Boolean threw = false;
        Test.startTest();
        try {
            PCRSandboxBridge.pullSandboxPcr(pcr.Id);
        } catch (PCRSandboxBridge.BridgeException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when sandbox replica missing');
        Product_Code_Request__c reloaded = [SELECT Last_Migrate_Error__c FROM Product_Code_Request__c WHERE Id = :pcr.Id];
        System.assert(reloaded.Last_Migrate_Error__c != null && reloaded.Last_Migrate_Error__c.contains('not found'),
            'Error should contain "not found"');
    }
}