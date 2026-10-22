@IsTest
private class PCRSectorGeneratorTest {

    private static Product_Code_Request__c newPcr() {
        Product_Code_Request__c p = new Product_Code_Request__c(
            Product_Name__c = 'Test', Type__c = 'Product', Category__c = 'Stand-alone',
            Short_Description__c = 'x', Hardware_Software__c = 'HW'
        );
        insert p;
        return p;
    }

    private static PCRSectorGenerator.Request req(Id pcrId, String round) {
        PCRSectorGenerator.Request r = new PCRSectorGenerator.Request();
        r.pcrId = pcrId; r.round = round;
        return r;
    }

    @IsTest static void generatesOneChildPerR1Definition() {
        Product_Code_Request__c p = newPcr();
        Integer expected = PCRSectorDefinitions.forRound('R1').size();
        Test.startTest();
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ req(p.Id, 'R1') });
        Test.stopTest();
        List<PCR_Sector__c> kids = [SELECT Id, Status__c, Round__c FROM PCR_Sector__c WHERE PCR__c = :p.Id];
        System.assertEquals(expected, kids.size(), 'one child per R1 definition');
        for (PCR_Sector__c k : kids) {
            System.assertEquals('Pending', k.Status__c);
            System.assertEquals('R1', k.Round__c);
        }
    }

    @IsTest static void isIdempotent() {
        Product_Code_Request__c p = newPcr();
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ req(p.Id, 'R1') });
        Integer after1 = [SELECT COUNT() FROM PCR_Sector__c WHERE PCR__c = :p.Id];
        Test.startTest();
        PCRSectorGenerator.generate(new List<PCRSectorGenerator.Request>{ req(p.Id, 'R1') });
        Test.stopTest();
        Integer after2 = [SELECT COUNT() FROM PCR_Sector__c WHERE PCR__c = :p.Id];
        System.assertEquals(after1, after2, 'second run creates no duplicates');
    }
}