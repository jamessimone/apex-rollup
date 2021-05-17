public virtual without sharing class RollupMetaPicklists {
  private final Set<String> validValues;

  private RollupMetaPicklists(Schema.SObjectField fieldToken) {
    this.validValues = new Set<String>();

    List<PicklistEntry> picklistValues = fieldToken.getDescribe().getPicklistValues();
    for (PicklistEntry entry : picklistValues) {
      this.validValues.add(entry.getValue());
    }
  }

  public static final ShouldRunAs ShouldRunAs = new ShouldRunAs();

  protected String validate(String val) {
    if (this.validValues.contains(val) == false) {
      throw new IllegalArgumentException(val + ' not present in valid picklist values: ' + JSON.serialize(this.validValues));
    }
    return val;
  }

  public class ShouldRunAs extends RollupMetaPicklists {
    public ShouldRunAs() {
      super(RollupControl__mdt.ShouldRunAs__c);
    }

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
  }
}
