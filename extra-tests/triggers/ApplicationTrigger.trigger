trigger ApplicationTrigger on Application__c (before insert) {
  // to ensure invalid trigger contexts don't unexpectedly throw
  Rollup.runFromTrigger();
}