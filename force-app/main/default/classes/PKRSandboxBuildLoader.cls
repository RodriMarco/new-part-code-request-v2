/**
 * PKR v2 - pulls the Product2 records built in the sandbox for a Part Code Request
 * and writes their Ids and URLs into the production Part Codes.
 * The sandbox marks each Product2 with Source_PCR_Id__c = production Part Code Id.
 */
public with sharing class PKRSandboxBuildLoader {

    public class LoaderException extends Exception {}

    @TestVisible private static final String SANDBOX_LIGHTNING_BASE = 'https://chyronhego--bizops.sandbox.lightning.force.com/';

    public class Result {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String message;
        @InvocableVariable(label='Products Loaded') public Integer productsLoaded;
    }

    @InvocableMethod(label='PKR Load Sandbox Build' description='Pulls the sandbox Product2 Ids into the Part Codes of the request.')
    public static List<Result> loadInvocable(List<Id> requestIds) {
        List<Result> results = new List<Result>();
        for (Id requestId : requestIds) {
            Result r = new Result();
            try {
                r.productsLoaded = loadSandboxBuilds(requestId);
                r.success = true;
                r.message = r.productsLoaded + ' Part Code(s) linked to their sandbox product.';
            } catch (Exception e) {
                r.success = false;
                r.message = e.getMessage();
                r.productsLoaded = 0;
            }
            results.add(r);
        }
        return results;
    }

    public static Integer loadSandboxBuilds(Id requestId) {
        Map<Id, Part_Code__c> partCodes = new Map<Id, Part_Code__c>(
            [SELECT Id, Sandbox_Product2_Id__c FROM Part_Code__c WHERE Part_Code_Request__c = :requestId]);
        if (partCodes.isEmpty()) {
            throw new LoaderException('The request has no Part Codes.');
        }
        List<String> quotedIds = new List<String>();
        for (Id pcId : partCodes.keySet()) {
            quotedIds.add('\'' + String.valueOf(pcId) + '\'');
        }
        String soql = 'SELECT Id, Source_PCR_Id__c FROM Product2 WHERE Source_PCR_Id__c IN (' + String.join(quotedIds, ',') + ')';
        HttpResponse res = PKRSandboxBridge.get('/services/data/' + PKRSandboxBridge.SANDBOX_API_VERSION + '/query?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'));
        if (res.getStatusCode() != 200) {
            throw new LoaderException('Sandbox query failed with status ' + res.getStatusCode() + ': ' + res.getBody());
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Part_Code__c> updates = new List<Part_Code__c>();
        for (Object o : (List<Object>) parsed.get('records')) {
            Map<String, Object> rec = (Map<String, Object>) o;
            String sourceId = (String) rec.get('Source_PCR_Id__c');
            String productId = (String) rec.get('Id');
            if (sourceId == null || !partCodes.containsKey(sourceId)) {
                continue;
            }
            updates.add(new Part_Code__c(
                Id = sourceId,
                Sandbox_Product2_Id__c = productId,
                Sandbox_Product2_Url__c = SANDBOX_LIGHTNING_BASE + productId,
                Build_Status__c = 'Built in Sandbox'
            ));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
        return updates.size();
    }
}
