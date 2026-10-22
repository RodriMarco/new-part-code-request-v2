@IsTest
private class PCRSectorGateTest {

    private static Product_Code_Request__c pcrAt(String stage) {
        Product_Code_Request__c p = new Product_Code_Request__c(
            Product_Name__c = 'T', Type__c = 'Product', Category__c = 'Stand-alone',
            Short_Description__c = 'x', Hardware_Software__c = 'HW', Stage__c = stage,
            Price_Americas__c = 100, Same_Pricing_All_Regions__c = true);
        insert p;
        return p;
    }

    @IsTest static void advancesWhenAllR1Approved() {
        Product_Code_Request__c p = pcrAt('Sandbox Approval');
        PCRSectorGenerator.Request r = new PCRSectorGenerator.Request(); r.pcrId = p.Id; r.round = 'R1';
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ r });
        List<PCR_Sector__c> kids = [SELECT Id, Definition__c FROM PCR_Sector__c WHERE PCR__c = :p.Id];
        for (PCR_Sector__c k : kids) {
            // fill owned fields so the Finance/Sales/etc. children are complete
            for (String f : PCRSectorDefinitions.ownedFields(k.Definition__c)) k.put(f, sampleFor(f));
            k.Status__c = 'Approved';
        }
        update kids;

        // Advancing to 'Sandbox Load Pending' fires the pre-existing PCR_Trigger_Sandbox_Replicate
        // flow (Apex action PCRSandboxBridge.replicateInvocable -> @future(callout=true)). Mock the
        // callout so Test.stopTest() can flush that future without a real HTTP call (same pattern as
        // PCRSandboxBridge_Test.MockCreated).
        Test.setMock(HttpCalloutMock.class, new SandboxReplicateMock());

        Test.startTest();
        PCRSectorGate.evaluate(new List<Id>(new Map<Id,PCR_Sector__c>(kids).keySet()));
        Test.stopTest();

        Product_Code_Request__c after = [SELECT Stage__c, Cost__c, Price_Americas__c FROM Product_Code_Request__c WHERE Id = :p.Id];
        System.assertEquals('Sandbox Load Pending', after.Stage__c);
        System.assertNotEquals(null, after.Cost__c, 'Finance owned field written back');
    }

    @IsTest static void changesRequestedSendsToRevisions() {
        Product_Code_Request__c p = pcrAt('Sandbox Approval');
        PCRSectorGenerator.Request r = new PCRSectorGenerator.Request(); r.pcrId = p.Id; r.round = 'R1';
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ r });
        PCR_Sector__c one = [SELECT Id FROM PCR_Sector__c WHERE PCR__c = :p.Id LIMIT 1];
        one.Status__c = 'Changes Requested';
        update one;

        Test.startTest();
        PCRSectorGate.evaluate(new List<Id>{ one.Id });
        Test.stopTest();

        Product_Code_Request__c after = [SELECT Stage__c, Return_Stage__c FROM Product_Code_Request__c WHERE Id = :p.Id];
        System.assertEquals('Revisions Needed', after.Stage__c);
        System.assertEquals('Sandbox Approval', after.Return_Stage__c);
    }

    @IsTest static void doesNotAdvanceWithPendingRemaining() {
        Product_Code_Request__c p = pcrAt('Sandbox Approval');
        PCRSectorGenerator.Request r = new PCRSectorGenerator.Request(); r.pcrId = p.Id; r.round = 'R1';
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ r });
        PCR_Sector__c one = [SELECT Id FROM PCR_Sector__c WHERE PCR__c = :p.Id LIMIT 1];
        one.Status__c = 'Approved';
        update one;

        Test.startTest();
        PCRSectorGate.evaluate(new List<Id>{ one.Id });
        Test.stopTest();

        System.assertEquals('Sandbox Approval',
            [SELECT Stage__c FROM Product_Code_Request__c WHERE Id = :p.Id].Stage__c);
    }

    @IsTest static void advancesWhenAllR2Approved() {
        Product_Code_Request__c p = pcrAt('Testing');
        PCRSectorGenerator.Request r = new PCRSectorGenerator.Request(); r.pcrId = p.Id; r.round = 'R2';
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ r });
        List<PCR_Sector__c> kids = [SELECT Id FROM PCR_Sector__c WHERE PCR__c = :p.Id];
        System.assertEquals(4, kids.size(), 'all four R2 sectors generated');
        for (PCR_Sector__c k : kids) {
            k.Status__c = 'Approved'; // R2 sectors are sign-off-only, no owned fields to fill
        }
        update kids;

        // Moving to 'Production Migration Pending' does not by itself fire any callout: PCR_Prod_Build
        // only triggers when Production_Build_Triggered__c = true (not set here), and
        // PCR_Trigger_Sandbox_Replicate only fires on 'Sandbox Load Pending'. No mock needed.
        Test.startTest();
        PCRSectorGate.evaluate(new List<Id>(new Map<Id,PCR_Sector__c>(kids).keySet()));
        Test.stopTest();

        Product_Code_Request__c after = [SELECT Stage__c FROM Product_Code_Request__c WHERE Id = :p.Id];
        System.assertEquals('Production Migration Pending', after.Stage__c);
    }

    @IsTest static void revisionsResolvedRestoresRoundStage() {
        Product_Code_Request__c p = pcrAt('Sandbox Approval');
        PCRSectorGenerator.Request r = new PCRSectorGenerator.Request(); r.pcrId = p.Id; r.round = 'R1';
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ r });
        PCR_Sector__c one = [SELECT Id FROM PCR_Sector__c WHERE PCR__c = :p.Id LIMIT 1];
        one.Status__c = 'Changes Requested';
        update one;

        PCRSectorGate.evaluate(new List<Id>{ one.Id });

        Product_Code_Request__c mid = [SELECT Stage__c, Return_Stage__c FROM Product_Code_Request__c WHERE Id = :p.Id];
        System.assertEquals('Revisions Needed', mid.Stage__c, 'setup: PCR sent to revisions');
        System.assertEquals('Sandbox Approval', mid.Return_Stage__c, 'setup: return stage recorded');

        // Requester resolves the change and resubmits the child for review.
        one.Status__c = 'Pending';
        update one;

        Test.startTest();
        PCRSectorGate.evaluate(new List<Id>{ one.Id });
        Test.stopTest();

        // Other R1 children are still Pending, so the round can't complete yet -- but the PCR must
        // be restored out of 'Revisions Needed' and back into the round it came from.
        Product_Code_Request__c after = [SELECT Stage__c FROM Product_Code_Request__c WHERE Id = :p.Id];
        System.assertEquals('Sandbox Approval', after.Stage__c);
    }

    @IsTest static void reopenFromDoneStageGoesToRevisions() {
        // R1 fully approved -> advances to Sandbox Load Pending. A sector then flags a problem
        // AFTER the round already advanced -> the PCR must still reopen to Revisions Needed.
        Product_Code_Request__c p = pcrAt('Sandbox Approval');
        PCRSectorGenerator.Request r = new PCRSectorGenerator.Request(); r.pcrId = p.Id; r.round = 'R1';
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ r });
        List<PCR_Sector__c> kids = [SELECT Id, Definition__c FROM PCR_Sector__c WHERE PCR__c = :p.Id];
        for (PCR_Sector__c k : kids) {
            for (String f : PCRSectorDefinitions.ownedFields(k.Definition__c)) k.put(f, sampleFor(f));
            k.Status__c = 'Approved';
        }
        Test.setMock(HttpCalloutMock.class, new SandboxReplicateMock());

        Test.startTest();
        update kids;
        PCRSectorGate.evaluate(new List<Id>(new Map<Id,PCR_Sector__c>(kids).keySet())); // -> Sandbox Load Pending
        System.assertEquals('Sandbox Load Pending',
            [SELECT Stage__c FROM Product_Code_Request__c WHERE Id = :p.Id].Stage__c, 'setup: advanced past R1');

        PCR_Sector__c one = kids[0];
        one.Status__c = 'Changes Requested';
        update one;
        PCRSectorGate.evaluate(new List<Id>{ one.Id }); // reopen from the done stage
        Test.stopTest();

        Product_Code_Request__c after = [SELECT Stage__c, Return_Stage__c FROM Product_Code_Request__c WHERE Id = :p.Id];
        System.assertEquals('Revisions Needed', after.Stage__c, 'reopened after the round advanced');
        System.assertEquals('Sandbox Approval', after.Return_Stage__c, 'returns to the R1 review stage');
    }

    private class SandboxReplicateMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setBody('{"id":"a9xSANDBOXFAKE1","success":true,"errors":[]}');
            return res;
        }
    }

    private static Object sampleFor(String field) {
        if (field == 'Product_Code__c') return 'CODE';
        if (field == 'Product_Family__c') return 'General';
        if (field == 'License_Conversion__c' || field == 'Entitlement_Conversion__c' || field == 'Asset_Conversion__c') {
            return 'One Per Unit';
        }
        return 10; // Cost__c, Price_Americas__c, Price_EMEA__c (Currency)
    }
}