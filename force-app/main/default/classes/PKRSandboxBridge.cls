/**
 * PKR v2 - replicates a Part Code Request and its Part Codes to the sandbox org
 * through the PCR_Sandbox named credential (REST composite tree API).
 * The sandbox builds the products itself (PKR_Build_Replicated_Part_Code flow);
 * PKRSandboxBuildLoader pulls the resulting Product2 Ids back into production.
 */
public with sharing class PKRSandboxBridge {

    public class BridgeException extends Exception {}

    public static final String SANDBOX_API_VERSION = 'v62.0';
    @TestVisible private static final String NAMED_CREDENTIAL = 'callout:PCR_Sandbox';

    public class Result {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String message;
        @InvocableVariable(label='Sandbox Request Id') public String sandboxRequestId;
    }

    @InvocableMethod(label='PKR Send to Sandbox' description='Copies the Part Code Request and its Part Codes to the sandbox. One request per call from the screen flow.')
    public static List<Result> sendInvocable(List<Id> requestIds) {
        List<Result> results = new List<Result>();
        for (Id requestId : requestIds) {
            Result r = new Result();
            try {
                r.sandboxRequestId = sendToSandbox(requestId);
                r.success = true;
                r.message = 'Request and Part Codes copied to the sandbox.';
            } catch (Exception e) {
                r.success = false;
                r.message = e.getMessage();
            }
            results.add(r);
        }
        return results;
    }

    /** Synchronous: builds the composite tree payload, posts it, stamps the request. Returns the sandbox request Id. */
    public static String sendToSandbox(Id requestId) {
        Part_Code_Request__c req = loadRequest(requestId);
        if (req.Part_Codes__r.isEmpty()) {
            throw new BridgeException('The request has no Part Codes to send.');
        }
        HttpResponse res = post('/services/data/' + SANDBOX_API_VERSION + '/composite/tree/Part_Code_Request__c',
                                JSON.serialize(buildPayload(req)));
        if (res.getStatusCode() == 201) {
            String sandboxId = parseTreeResponse(res.getBody());
            update new Part_Code_Request__c(Id = requestId, Sent_to_Sandbox_Date__c = System.now(), Sandbox_Sync_Error__c = null, Stage__c = 'In Sandbox');
            return sandboxId;
        }
        String err = 'Sandbox POST failed with status ' + res.getStatusCode() + ': ' + res.getBody();
        update new Part_Code_Request__c(Id = requestId, Sandbox_Sync_Error__c = err.left(32768));
        throw new BridgeException(err);
    }

    @TestVisible
    private static Part_Code_Request__c loadRequest(Id requestId) {
        return [
            SELECT Id, Name, Title__c, summary_description__c, Approval_Status__c,
                   (SELECT Id, Product_Name__c, Product_Code__c, Product_Family__c, Product_Category__c,
                           Short_Description__c, Long_Description__c, Price_Americas__c, Price_EMEA__c, Cost__c
                    FROM Part_Codes__r ORDER BY Name)
            FROM Part_Code_Request__c WHERE Id = :requestId LIMIT 1
        ];
    }

    @TestVisible
    private static Map<String, Object> buildPayload(Part_Code_Request__c req) {
        List<Object> children = new List<Object>();
        Integer i = 0;
        for (Part_Code__c pc : req.Part_Codes__r) {
            children.add(new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Part_Code__c', 'referenceId' => 'pc' + (i++) },
                'Prod_Part_Code_Id__c' => String.valueOf(pc.Id),
                'Product_Name__c' => pc.Product_Name__c,
                'Product_Code__c' => pc.Product_Code__c,
                'Product_Family__c' => pc.Product_Family__c,
                'Product_Category__c' => pc.Product_Category__c,
                'Short_Description__c' => pc.Short_Description__c,
                'Long_Description__c' => pc.Long_Description__c,
                'Price_Americas__c' => pc.Price_Americas__c,
                'Price_EMEA__c' => pc.Price_EMEA__c,
                'Cost__c' => pc.Cost__c
            });
        }
        Map<String, Object> parent = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Part_Code_Request__c', 'referenceId' => 'req' },
            'Prod_PKR_Id__c' => String.valueOf(req.Id),
            'Title__c' => req.Title__c,
            'summary_description__c' => req.summary_description__c,
            'Approval_Status__c' => 'Approved',
            'Part_Codes__r' => new Map<String, Object>{ 'records' => children }
        };
        return new Map<String, Object>{ 'records' => new List<Object>{ parent } };
    }

    @TestVisible
    private static String parseTreeResponse(String body) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        for (Object o : (List<Object>) parsed.get('results')) {
            Map<String, Object> r = (Map<String, Object>) o;
            if (r.get('referenceId') == 'req') {
                return (String) r.get('id');
            }
        }
        return null;
    }

    private static HttpResponse post(String path, String jsonBody) {
        HttpRequest reqHttp = new HttpRequest();
        reqHttp.setEndpoint(NAMED_CREDENTIAL + path);
        reqHttp.setMethod('POST');
        reqHttp.setHeader('Content-Type', 'application/json');
        reqHttp.setTimeout(60000);
        reqHttp.setBody(jsonBody);
        return new Http().send(reqHttp);
    }

    /** GET helper shared with PKRSandboxBuildLoader. */
    public static HttpResponse get(String path) {
        HttpRequest reqHttp = new HttpRequest();
        reqHttp.setEndpoint(NAMED_CREDENTIAL + path);
        reqHttp.setMethod('GET');
        reqHttp.setTimeout(60000);
        return new Http().send(reqHttp);
    }
}
