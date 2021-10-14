public without sharing class RollupPurgerSchedulable implements System.Schedulable {
  private final Integer batchSize;

  public RollupPurgerSchedulable() {
    this.batchSize = RollupLogControl.BatchSize;
  }

  public void execute(SchedulableContext sc) {
    Database.executeBatch(new RollupLogBatchPurger(), this.batchSize);
  }
}
