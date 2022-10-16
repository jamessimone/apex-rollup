trigger ApplicationTrigger on Application__c(before insert, after insert, before update, after update, before delete, after undelete) {
  // to ensure invalid trigger contexts don't unexpectedly throw
    Rollup.runFromTrigger();
}
