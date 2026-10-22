@IsTest
private class PCRSupersessionSchedulerTest {
    @IsTest static void runsDeactivateDue() {
        Product2 oldP = new Product2(Name='Old', IsActive=true); insert oldP;
        Product2 newP = new Product2(Name='New', IsActive=true); insert newP;
        Product_Code_Request__c p = new Product_Code_Request__c(
            Product_Name__c='T', Type__c='Product', Category__c='Stand-alone',
            Short_Description__c='x', Hardware_Software__c='HW', Stage__c='Live',
            Replaces__c=oldP.Id, Production_Product2_Id__c=newP.Id,
            Activation_Date__c=Date.today(), Old_Product_Deactivated__c=false);
        insert p;
        Test.startTest();
        String cron = '0 0 2 * * ?';
        System.schedule('PCR Supersession Test', cron, new PCRSupersessionScheduler());
        Test.stopTest();
        System.assertEquals(false, [SELECT IsActive FROM Product2 WHERE Id=:oldP.Id].IsActive);
    }
}