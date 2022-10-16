trigger RollupChildTrigger on RollupChild__c(before insert, after insert, after update, before delete, after undelete) {
  Rollup.runFromTrigger();
}
