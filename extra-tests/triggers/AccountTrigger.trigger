trigger AccountTrigger on Account(after insert, after update, after delete) {
  // included specifically to test merges
  Rollup.runFromTrigger();
}
