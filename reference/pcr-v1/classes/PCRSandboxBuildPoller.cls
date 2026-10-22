public with sharing class PCRSandboxBuildPoller implements Schedulable {

    // Scheduled entry point. Enqueues a Queueable (callouts aren't allowed directly in Schedulable).
    public void execute(SchedulableContext sc) {
        System.enqueueJob(new PollJob());
    }

    // Manual / on-demand pull (e.g. a "Load from Sandbox" button or flow). Each call does its own callout.
    @InvocableMethod(label='PCR Load Sandbox Build' description='Pulls the built sandbox Product2 and advances the PCR to Testing')
    public static void loadSandboxBuildInvocable(List<Id> prodPcrIds) {
        for (Id pcrId : prodPcrIds) {
            PCRSandboxBridge.loadSandboxBuild(pcrId);
        }
    }

    public class PollJob implements Queueable, Database.AllowsCallouts {
        public void execute(QueueableContext qc) {
            List<Product_Code_Request__c> pending = [
                SELECT Id FROM Product_Code_Request__c
                WHERE Stage__c = 'Sandbox Load Pending'
                LIMIT 50
            ];
            for (Product_Code_Request__c pcr : pending) {
                try {
                    PCRSandboxBridge.loadSandboxBuild(pcr.Id);
                } catch (Exception e) {
                    System.debug('[PCR_POLL] ' + pcr.Id + ': ' + e.getMessage());
                }
            }
        }
    }
}