public with sharing class PCRProdCallback {

    public class CallbackException extends Exception {}

    private static final String PROD_API_VERSION = 'v62.0';

    public static void notifyProductCreated(String prodPcrId, Id sandboxProduct2Id, String sandboxUrl) {
        Map<String,Object> body = new Map<String,Object>{
            'Sandbox_Product2_Id__c' => String.valueOf(sandboxProduct2Id),
            'Sandbox_Product2_Url__c' => sandboxUrl,
            'Sandbox_Load_Status__c' => 'Loaded'
        };
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:PCR_Prod/services/data/' + PROD_API_VERSION + '/sobjects/Product_Code_Request__c/' + prodPcrId);
        req.setMethod('PATCH');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CallbackException('PATCH to prod failed status ' + res.getStatusCode() + ' body: ' + res.getBody());
        }
    }

    public class NotifyInput {
        @InvocableVariable(required=true) public String prodPcrId;
        @InvocableVariable(required=true) public Id sandboxProduct2Id;
        @InvocableVariable public String sandboxUrl;
    }

    @InvocableMethod(label='PCR Notify Product Created' description='Calls PCRProdCallback.notifyProductCreated (async via @future)')
    public static void notifyInvocable(List<NotifyInput> inputs) {
        List<String> prodPcrIds = new List<String>();
        List<String> productIds = new List<String>();
        List<String> urls = new List<String>();
        for (NotifyInput inp : inputs) {
            prodPcrIds.add(inp.prodPcrId);
            productIds.add(String.valueOf(inp.sandboxProduct2Id));
            urls.add(inp.sandboxUrl == null ? '' : inp.sandboxUrl);
        }
        notifyAsync(prodPcrIds, productIds, urls);
    }

    @future(callout=true)
    public static void notifyAsync(List<String> prodPcrIds, List<String> productIds, List<String> urls) {
        for (Integer i = 0; i < prodPcrIds.size(); i++) {
            try {
                notifyProductCreated(prodPcrIds[i], productIds[i], urls[i]);
            } catch (CallbackException e) {
                System.debug('[PCR_BRIDGE] notifyAsync error for ' + prodPcrIds[i] + ': ' + e.getMessage());
            }
        }
    }
}