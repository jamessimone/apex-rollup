public without sharing class RollupSchedulable implements System.Schedulable {
  private final Rollup roll;

  public RollupSchedulable(Rollup roll) {
    this.roll = roll;
  }

  public void execute(SchedulableContext sc) {
    this.roll.runCalc();
  }
}
