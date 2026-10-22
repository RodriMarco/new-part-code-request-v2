public with sharing class PCRSupersessionScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        PCRProductSupersession.deactivateDue();
    }
}