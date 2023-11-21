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

  public static RollupRepository.RunAsMode getAccessLevel(Rollup__mdt meta) {
    return meta.SharingMode__c == SharingMode.UserLevel ? RollupRepository.RunAsMode.USER : RollupRepository.RunAsMode.SYSTEM_LEVEL;
  }

  public static final SharingMode SharingMode {
    get {
      if (SharingMode == null) {
        SharingMode = new SharingMode();
      }
      return SharingMode;
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

    public final String Synchronous {
      get {
        if (Synchronous == null) {
          Synchronous = this.validate('Synchronous Rollup');
        }
        return Synchronous;
      }
      private set;
    }

    public final String Batchable {
      get {
        if (Batchable == null) {
          Batchable = this.validate('Batchable');
        }
        return Batchable;
      }
      private set;
    }

    public final String Queueable {
      get {
        if (Queueable == null) {
          Queueable = this.validate('Queueable');
        }
        return Queueable;
      }
      private set;
    }
  }

  public class SortOrder extends RollupMetaPicklists {
    public SortOrder() {
      super(RollupOrderBy__mdt.SortOrder__c);
    }

    public final String Ascending {
      get {
        if (Ascending == null) {
          Ascending = this.validate('Ascending');
        }
        return Ascending;
      }
      private set;
    }

    public final String Descending {
      get {
        if (Descending == null) {
          Descending = this.validate('Descending');
        }
        return Descending;
      }
      private set;
    }
  }

  public class NullSortOrder extends RollupMetaPicklists {
    public NullSortOrder() {
      super(RollupOrderBy__mdt.NullSortOrder__c);
    }

    public final String NullsFirst {
      get {
        if (NullsFirst == null) {
          NullsFirst = this.validate('NULLS FIRST');
        }
        return NullsFirst;
      }
      private set;
    }

    public final String NullsLast {
      get {
        if (NullsLast == null) {
          NullsLast = this.validate('NULLS LAST');
        }
        return NullsLast;
      }
      private set;
    }
  }

  public class SharingMode extends RollupMetaPicklists {
    public SharingMode() {
      super(Rollup__mdt.SharingMode__c);
    }

    public final String SystemLevel {
      get {
        if (SystemLevel == null) {
          SystemLevel = this.validate('System');
        }
        return SystemLevel;
      }
      private set;
    }

    public final String UserLevel {
      get {
        if (UserLevel == null) {
          UserLevel = this.validate('User');
        }
        return UserLevel;
      }
      private set;
    }
  }
}
