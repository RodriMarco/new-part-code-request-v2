@isTest
private class PCRProdCallback_Test {

    private class MockPatchOk implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(204);
            return res;
        }
    }

    private class MockPatchFail implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('[{"errorCode":"INVALID_FIELD","message":"x"}]');
            return res;
        }
    }

    @isTest
    static void notify_success_returnsCleanly() {
        Test.setMock(HttpCalloutMock.class, new MockPatchOk());

        Test.startTest();
        PCRProdCallback.notifyProductCreated('a9xPRODFAKE000001', '01t000000000001', 'https://sandbox/01tSANDBOXFAKE0');
        Test.stopTest();
    }

    @isTest
    static void notify_failure_throwsCallbackException() {
        Test.setMock(HttpCalloutMock.class, new MockPatchFail());

        Boolean threw = false;
        Test.startTest();
        try {
            PCRProdCallback.notifyProductCreated('a9xPRODFAKE000001', '01t000000000001', 'https://sandbox/01tSANDBOXFAKE0');
        } catch (PCRProdCallback.CallbackException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw CallbackException on non-2xx');
    }

    @isTest
    static void notifyInvocable_success_swallowsExceptionsAndReturns() {
        Test.setMock(HttpCalloutMock.class, new MockPatchOk());

        PCRProdCallback.NotifyInput inp = new PCRProdCallback.NotifyInput();
        inp.prodPcrId = 'a9xPRODFAKE000001';
        inp.sandboxProduct2Id = '01t000000000001';
        inp.sandboxUrl = 'https://sandbox/01tSANDBOXFAKE0';

        Test.startTest();
        PCRProdCallback.notifyInvocable(new List<PCRProdCallback.NotifyInput>{ inp });
        Test.stopTest();
    }

    @isTest
    static void notifyInvocable_failure_swallowsException() {
        Test.setMock(HttpCalloutMock.class, new MockPatchFail());

        PCRProdCallback.NotifyInput inp = new PCRProdCallback.NotifyInput();
        inp.prodPcrId = 'a9xPRODFAKE000001';
        inp.sandboxProduct2Id = '01t000000000001';
        inp.sandboxUrl = 'https://sandbox/01tSANDBOXFAKE0';

        Test.startTest();
        PCRProdCallback.notifyInvocable(new List<PCRProdCallback.NotifyInput>{ inp });
        Test.stopTest();
    }
}