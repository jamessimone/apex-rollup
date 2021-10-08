trigger ApplicationLogTrigger on ApplicationLog__c(before insert, after insert, before update, after update, before delete, after undelete) {
  Rollup.runFromTrigger();
}
