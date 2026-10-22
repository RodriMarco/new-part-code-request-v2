@IsTest
private class PKRSandboxBridge_Test {

    private class Mock implements HttpCalloutMock {
        Integer status; String body;
        Mock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    private static Part_Code_Request__c makeRequest(Integer partCodes) {
        Part_Code_Request__c req = new Part_Code_Request__c(Title__c = 'Test request', Approval_Status__c = 'Approved');
        insert req;
        List<Part_Code__c> pcs = new List<Part_Code__c>();
        for (Integer i = 0; i < partCodes; i++) {
            pcs.add(new Part_Code__c(Part_Code_Request__c = req.Id, Product_Name__c = 'Product ' + i,
                                     Product_Code__c = 'PC-' + i, Price_Americas__c = 100 + i, Cost__c = 40));
        }
        insert pcs;
        return req;
    }

    @IsTest
    static void sendSuccessStampsRequest() {
        Part_Code_Request__c req = makeRequest(2);
        Test.setMock(HttpCalloutMock.class, new Mock(201,
            '{"hasErrors":false,"results":[{"referenceId":"req","id":"a2xSANDBOX000001AAA"},{"referenceId":"pc0","id":"a2wSANDBOX000001AAA"},{"referenceId":"pc1","id":"a2wSANDBOX000002AAA"}]}'));
        Test.startTest();
        List<PKRSandboxBridge.Result> results = PKRSandboxBridge.sendInvocable(new List<Id>{ req.Id });
        Test.stopTest();
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, results[0].message);
        System.assertEquals('a2xSANDBOX000001AAA', results[0].sandboxRequestId);
        req = [SELECT Sent_to_Sandbox_Date__c, Sandbox_Sync_Error__c FROM Part_Code_Request__c WHERE Id = :req.Id];
        System.assertNotEquals(null, req.Sent_to_Sandbox_Date__c);
        System.assertEquals(null, req.Sandbox_Sync_Error__c);
    }

    @IsTest
    static void sendFailureWritesError() {
        Part_Code_Request__c req = makeRequest(1);
        Test.setMock(HttpCalloutMock.class, new Mock(400, '[{"message":"bad","errorCode":"INVALID_FIELD"}]'));
        Test.startTest();
        List<PKRSandboxBridge.Result> results = PKRSandboxBridge.sendInvocable(new List<Id>{ req.Id });
        Test.stopTest();
        System.assertEquals(false, results[0].success);
        req = [SELECT Sent_to_Sandbox_Date__c, Sandbox_Sync_Error__c FROM Part_Code_Request__c WHERE Id = :req.Id];
        System.assertEquals(null, req.Sent_to_Sandbox_Date__c);
        System.assert(req.Sandbox_Sync_Error__c.contains('400'));
    }

    @IsTest
    static void sendWithoutPartCodesFails() {
        Part_Code_Request__c req = makeRequest(0);
        Test.startTest();
        List<PKRSandboxBridge.Result> results = PKRSandboxBridge.sendInvocable(new List<Id>{ req.Id });
        Test.stopTest();
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('no Part Codes'));
    }

    @IsTest
    static void payloadCarriesProductionIds() {
        Part_Code_Request__c req = makeRequest(2);
        Map<String, Object> payload = PKRSandboxBridge.buildPayload(PKRSandboxBridge.loadRequest(req.Id));
        List<Object> records = (List<Object>) payload.get('records');
        Map<String, Object> parent = (Map<String, Object>) records[0];
        System.assertEquals(String.valueOf(req.Id), parent.get('Prod_PKR_Id__c'));
        Map<String, Object> rel = (Map<String, Object>) parent.get('Part_Codes__r');
        System.assertEquals(2, ((List<Object>) rel.get('records')).size());
    }

    @IsTest
    static void loaderLinksSandboxProducts() {
        Part_Code_Request__c req = makeRequest(2);
        List<Part_Code__c> pcs = [SELECT Id FROM Part_Code__c WHERE Part_Code_Request__c = :req.Id ORDER BY Name];
        Test.setMock(HttpCalloutMock.class, new Mock(200,
            '{"totalSize":1,"done":true,"records":[{"attributes":{"type":"Product2"},"Id":"01tSANDBOX00001AAA","Source_PCR_Id__c":"' + pcs[0].Id + '"}]}'));
        Test.startTest();
        List<PKRSandboxBuildLoader.Result> results = PKRSandboxBuildLoader.loadInvocable(new List<Id>{ req.Id });
        Test.stopTest();
        System.assertEquals(true, results[0].success, results[0].message);
        System.assertEquals(1, results[0].productsLoaded);
        Part_Code__c linked = [SELECT Sandbox_Product2_Id__c, Sandbox_Product2_Url__c, Build_Status__c FROM Part_Code__c WHERE Id = :pcs[0].Id];
        System.assertEquals('01tSANDBOX00001AAA', linked.Sandbox_Product2_Id__c);
        System.assertEquals('Built in Sandbox', linked.Build_Status__c);
        System.assert(linked.Sandbox_Product2_Url__c.endsWith('01tSANDBOX00001AAA'));
    }

    @IsTest
    static void loaderQueryFailure() {
        Part_Code_Request__c req = makeRequest(1);
        Test.setMock(HttpCalloutMock.class, new Mock(500, 'boom'));
        Test.startTest();
        List<PKRSandboxBuildLoader.Result> results = PKRSandboxBuildLoader.loadInvocable(new List<Id>{ req.Id });
        Test.stopTest();
        System.assertEquals(false, results[0].success);
        System.assertEquals(0, results[0].productsLoaded);
    }
}
