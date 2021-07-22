trigger RollupLogEventTrigger on RollupLogEvent__e (after insert) {
  new RollupLogEventHandler().handle(Trigger.new);
}