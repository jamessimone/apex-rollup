public virtual without sharing class RollupMetaPicklists {
  private final Set<String> validValues;

  public static final ShouldRunAs ShouldRunAs = new ShouldRunAs();
  public static final SortOrder SortOrder {
    get {
      if (SortOrder == null) {
        SortOrder = new SortOrder();
      }
      return SortOrder;
    }
    private set;
  }

  public static final NullSortOrder NullSortOrder {
    get {
      if (NullSortOrder == null) {
        NullSortOrder = new NullSortOrder();
      }
      return NullSortOrder;
    }
    private set;
  }

  private RollupMetaPicklists(Schema.SObjectField fieldToken) {
    this.validValues = new Set<String>();

    List<PicklistEntry> picklistValues = fieldToken.getDescribe().getPicklistValues();
    for (PicklistEntry entry : picklistValues) {
      this.validValues.add(entry.getValue());
    }
  }

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

    public String Synchronous {
      get {
        return this.validate('Synchronous Rollup');
      }
    }

    public String Batchable {
      get {
        return this.validate('Batchable');
      }
    }

    public String Queueable {
      get {
        return this.validate('Queueable');
      }
    }
  }

  public class SortOrder extends RollupMetaPicklists {
    public SortOrder() {
      super(RollupOrderBy__mdt.SortOrder__c);
    }

    public String Ascending {
      get {
        return this.validate('Ascending');
      }
    }

    public String Descending {
      get {
        return this.validate('Descending');
      }
    }
  }

  public class NullSortOrder extends RollupMetaPicklists {
    public NullSortOrder() {
      super(RollupOrderBy__mdt.NullSortOrder__c);
    }

    public String NullsFirst {
      get {
        return this.validate('NULLS FIRST');
      }
    }

    public String NullsLast {
      get {
        return this.validate('NULLS LAST');
      }
    }
  }
}
