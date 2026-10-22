public with sharing class PCRSandboxBridge {

    public class BridgeException extends Exception {}

    @TestVisible
    private static final String SANDBOX_API_VERSION = 'v62.0';
    @TestVisible
    private static final Set<String> FIELDS_TO_REPLICATE = new Set<String>{
        'Product_Name__c','Product_Code__c','Type__c','Hardware_Software__c','Category__c',
        'Replaces__c','Platform__c','Short_Description__c','Long_Description__c',
        'Price_Americas__c','Price_EMEA__c','Same_Pricing_All_Regions__c',
        'Cost__c','Product_Family__c','Fulfillment_Team__c',
        // Requester__c (User lookup) intentionally NOT replicated: prod User Ids do not resolve
        // in the Bizops sandbox, causing INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY on the POST.
        'Stage__c','CurrencyIsoCode'
    };

    public static String replicatePcrToSandbox(Id pcrId) {
        Product_Code_Request__c pcr = loadPcr(pcrId);
        Map<String,Object> payload = buildPayload(pcr, pcrId);
        HttpResponse res = postToSandbox('/services/data/' + SANDBOX_API_VERSION + '/sobjects/Product_Code_Request__c', JSON.serialize(payload));
        if (res.getStatusCode() == 201) {
            String sandboxId = parseCreateResponse(res.getBody());
            clearSyncError(pcrId);
            return sandboxId;
        }
        String err = 'POST failed status ' + res.getStatusCode() + ' body: ' + res.getBody();
        writeSyncError(pcrId, err);
        throw new BridgeException(err);
    }

    @InvocableMethod(label='PCR Replicate to Sandbox' description='Calls PCRSandboxBridge.replicatePcrToSandbox (async via @future)')
    public static void replicateInvocable(List<Id> pcrIds) {
        Set<Id> uniqueIds = new Set<Id>(pcrIds);
        replicateAsync(new List<Id>(uniqueIds));
    }

    @future(callout=true)
    public static void replicateAsync(List<Id> pcrIds) {
        for (Id pcrId : pcrIds) {
            try {
                replicatePcrToSandbox(pcrId);
            } catch (BridgeException e) {
                System.debug('[PCR_BRIDGE] replicateAsync error for ' + pcrId + ': ' + e.getMessage());
            }
        }
    }

    public static void pullSandboxPcr(Id pcrId) {
        String soql = 'SELECT+Product_Name__c,Product_Code__c,Type__c,Hardware_Software__c,Category__c,' +
                      'Replaces__c,Platform__c,Short_Description__c,Long_Description__c,' +
                      'Price_Americas__c,Price_EMEA__c,Same_Pricing_All_Regions__c+' +
                      'FROM+Product_Code_Request__c+WHERE+PROD_PCR_Id__c=%27' + String.valueOf(pcrId) + '%27';
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:PCR_Sandbox/services/data/' + SANDBOX_API_VERSION + '/query?q=' + soql);
        req.setMethod('GET');
        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            String err = 'GET failed status ' + res.getStatusCode() + ' body: ' + res.getBody();
            writeMigrateError(pcrId, err);
            throw new BridgeException(err);
        }
        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> records = (List<Object>) parsed.get('records');
        if (records == null || records.isEmpty()) {
            String err = 'Sandbox PCR replica not found for PROD_PCR_Id__c=' + pcrId;
            writeMigrateError(pcrId, err);
            throw new BridgeException(err);
        }
        Map<String,Object> sandboxRec = (Map<String,Object>) records[0];
        applySandboxValuesAndTrigger(pcrId, sandboxRec);
        clearMigrateError(pcrId);
    }

    private static void applySandboxValuesAndTrigger(Id pcrId, Map<String,Object> sandboxRec) {
        Product_Code_Request__c upd = new Product_Code_Request__c(Id = pcrId);
        for (String fld : FIELDS_TO_REPLICATE) {
            if (fld == 'Stage__c' || fld == 'Requester__c' || fld == 'CurrencyIsoCode') continue;
            if (sandboxRec.containsKey(fld)) {
                upd.put(fld, sandboxRec.get(fld));
            }
        }
        upd.Production_Build_Triggered__c = true;
        update upd;
    }

    private static void writeMigrateError(Id pcrId, String msg) {
        update new Product_Code_Request__c(Id = pcrId, Last_Migrate_Error__c = msg.left(32768));
    }

    private static void clearMigrateError(Id pcrId) {
        update new Product_Code_Request__c(Id = pcrId, Last_Migrate_Error__c = null);
    }

    private static Product_Code_Request__c loadPcr(Id pcrId) {
        return [
            SELECT Id, Product_Name__c, Product_Code__c, Type__c, Hardware_Software__c, Category__c,
                   Replaces__c, Platform__c, Short_Description__c, Long_Description__c,
                   Price_Americas__c, Price_EMEA__c, Same_Pricing_All_Regions__c,
                   Cost__c, Product_Family__c, Fulfillment_Team__c,
                   Requester__c, Stage__c, CurrencyIsoCode
            FROM Product_Code_Request__c WHERE Id = :pcrId LIMIT 1
        ];
    }

    private static Map<String,Object> buildPayload(Product_Code_Request__c pcr, Id pcrId) {
        Map<String,Object> body = new Map<String,Object>();
        for (String fld : FIELDS_TO_REPLICATE) {
            body.put(fld, pcr.get(fld));
        }
        body.put('PROD_PCR_Id__c', String.valueOf(pcrId));
        return body;
    }

    private static HttpResponse postToSandbox(String path, String jsonBody) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:PCR_Sandbox' + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonBody);
        return new Http().send(req);
    }

    private static String parseCreateResponse(String body) {
        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(body);
        return (String) parsed.get('id');
    }

    private static void writeSyncError(Id pcrId, String msg) {
        update new Product_Code_Request__c(Id = pcrId, Sandbox_Sync_Error__c = msg.left(32768));
    }

    private static void clearSyncError(Id pcrId) {
        update new Product_Code_Request__c(Id = pcrId, Sandbox_Sync_Error__c = null);
    }

    @TestVisible
    private static final String SANDBOX_LIGHTNING_BASE = 'https://chyronhego--bizops.sandbox.lightning.force.com/';

    // Option A: prod PULLS the built Product2 from sandbox (avoids the cross-org callout loop that
    // blocks a sandbox->prod push). Returns true if the product was found and the PCR advanced.
    public static Boolean loadSandboxBuild(Id prodPcrId) {
        String soql = 'SELECT+Id+FROM+Product2+WHERE+Source_PCR_Id__c=%27' + String.valueOf(prodPcrId) + '%27+LIMIT+1';
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:PCR_Sandbox/services/data/' + SANDBOX_API_VERSION + '/query?q=' + soql);
        req.setMethod('GET');
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            return false;
        }
        Map<String,Object> parsed = (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> records = (List<Object>) parsed.get('records');
        if (records == null || records.isEmpty()) {
            return false;
        }
        Map<String,Object> productRec = (Map<String,Object>) records[0];
        String productId = (String) productRec.get('Id');
        update new Product_Code_Request__c(
            Id = prodPcrId,
            Sandbox_Product2_Id__c = productId,
            Sandbox_Product2_Url__c = SANDBOX_LIGHTNING_BASE + productId,
            Sandbox_Load_Status__c = 'Loaded',
            Stage__c = 'Testing'
        );
        return true;
    }
}