@IsTest
private class PCRProductSupersessionTest {

    private static Product2 prod(String name, Boolean active) {
        Product2 p = new Product2(Name = name, IsActive = active);
        insert p; return p;
    }
    private static Product_Code_Request__c pcr(Id oldProd, Id newProd, Date activation) {
        Product_Code_Request__c p = new Product_Code_Request__c(
            Product_Name__c='T', Type__c='Product', Category__c='Stand-alone',
            Short_Description__c='x', Hardware_Software__c='HW', Stage__c='Live',
            Replaces__c = oldProd, Production_Product2_Id__c = newProd, Activation_Date__c = activation);
        insert p; return p;
    }

    @IsTest static void defaultsActivationDateAndReferences() {
        Product2 oldP = prod('Old', true);
        Product2 newP = prod('New', true);
        Product_Code_Request__c p = pcr(oldP.Id, newP.Id, null); // activation blank -> today
        Test.startTest();
        PCRProductSupersession.processAtGoLive(new List<Id>{ p.Id });
        Test.stopTest();
        Product_Code_Request__c after = [SELECT Activation_Date__c, Old_Product_Deactivated__c FROM Product_Code_Request__c WHERE Id = :p.Id];
        System.assertEquals(Date.today(), after.Activation_Date__c, 'blank activation defaulted to today');
        System.assertEquals(true, after.Old_Product_Deactivated__c, 'today -> deactivated now');
        Product2 oldAfter = [SELECT IsActive, Replaced_By__c FROM Product2 WHERE Id = :oldP.Id];
        System.assertEquals(false, oldAfter.IsActive, 'old product deactivated');
        System.assertEquals(newP.Id, oldAfter.Replaced_By__c, 'replaced-by reference set');
    }

    @IsTest static void futureActivationDoesNotDeactivateYet() {
        Product2 oldP = prod('Old', true);
        Product2 newP = prod('New', true);
        Product_Code_Request__c p = pcr(oldP.Id, newP.Id, Date.today().addDays(30));
        Test.startTest();
        PCRProductSupersession.processAtGoLive(new List<Id>{ p.Id });
        Test.stopTest();
        System.assertEquals(true, [SELECT IsActive FROM Product2 WHERE Id = :oldP.Id].IsActive, 'future date -> still active');
        System.assertEquals(false, [SELECT Old_Product_Deactivated__c FROM Product_Code_Request__c WHERE Id = :p.Id].Old_Product_Deactivated__c);
    }

    @IsTest static void noReplacesIsNoOpButDefaultsDate() {
        Product_Code_Request__c p = pcr(null, null, null);
        Test.startTest();
        PCRProductSupersession.processAtGoLive(new List<Id>{ p.Id });
        Test.stopTest();
        System.assertEquals(Date.today(), [SELECT Activation_Date__c FROM Product_Code_Request__c WHERE Id = :p.Id].Activation_Date__c);
    }

    @IsTest static void deactivateDueProcessesArrivedFutureDate() {
        Product2 oldP = prod('Old', true);
        Product2 newP = prod('New', true);
        // simulate a PCR whose future date has now arrived and wasn't deactivated at go-live
        Product_Code_Request__c p = pcr(oldP.Id, newP.Id, Date.today()); // due today
        update new Product_Code_Request__c(Id = p.Id, Old_Product_Deactivated__c = false);
        // ensure old still active
        update new Product2(Id = oldP.Id, IsActive = true);
        Test.startTest();
        PCRProductSupersession.deactivateDue();
        Test.stopTest();
        System.assertEquals(false, [SELECT IsActive FROM Product2 WHERE Id = :oldP.Id].IsActive);
        System.assertEquals(true, [SELECT Old_Product_Deactivated__c FROM Product_Code_Request__c WHERE Id = :p.Id].Old_Product_Deactivated__c);
    }
}