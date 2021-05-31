trigger AccountTrigger on Account (after delete) {
  // included specifically to test merges
  Rollup.runFromTrigger();
}