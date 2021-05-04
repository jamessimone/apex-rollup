public without sharing class RollupShouldRunAsPicklist {
  private final Set<String> validValues;

  private RollupShouldRunAsPicklist() {
    this.validValues = new Set<String>();

    List<PicklistEntry> picklistValues = RollupControl__mdt.ShouldRunAs__c.getDescribe().getPicklistValues();
    for (PicklistEntry entry : picklistValues) {
      this.validValues.add(entry.getValue());
    }
  }

  public static final RollupShouldRunAsPicklist Instance = new RollupShouldRunAsPicklist();

  public String SYNCHRONOUS {
    get {
      return this.validate('Synchronous Rollup');
    }
  }

  public String BATCHABLE {
    get {
      return this.validate('Batchable');
    }
  }

  public String QUEUEABLE {
    get {
      return this.validate('Queueable');
    }
  }

  private String validate(String val) {
    if (this.validValues.contains(val) == false) {
      throw new IllegalArgumentException(val + ' not present in valid picklist values: ' + JSON.serialize(this.validValues));
    }
    return val;
  }
}
