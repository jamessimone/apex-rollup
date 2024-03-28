public virtual without sharing class RollupMetaPicklists {
  private final Set<String> validValues;

  public static final ShouldRunAs ShouldRunAs = new ShouldRunAs();
  public static final SortOrder SortOrder {
    get {
      SortOrder = SortOrder ?? new SortOrder();
      return SortOrder;
    }
    private set;
  }

  public static final NullSortOrder NullSortOrder {
    get {
      NullSortOrder = NullSortOrder ?? new NullSortOrder();
      return NullSortOrder;
    }
    private set;
  }

  public static RollupRepository.RunAsMode getAccessLevel(Rollup__mdt meta) {
    return meta.SharingMode__c == SharingMode.UserLevel ? RollupRepository.RunAsMode.USER : RollupRepository.RunAsMode.SYSTEM_LEVEL;
  }

  public static final SharingMode SharingMode {
    get {
      SharingMode = SharingMode ?? new SharingMode();
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
        this.Synchronous = this.Synchronous ?? this.validate('Synchronous Rollup');
        return this.Synchronous;
      }
      private set;
    }

    public final String Batchable {
      get {
        this.Batchable = this.Batchable ?? this.validate('Batchable');
        return this.Batchable;
      }
      private set;
    }

    public final String Queueable {
      get {
        this.Queueable = this.Queueable ?? this.validate('Queueable');
        return this.Queueable;
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
        this.Ascending = this.Ascending ?? this.validate('Ascending');
        return this.Ascending;
      }
      private set;
    }

    public final String Descending {
      get {
        this.Descending = this.Descending ?? this.validate('Descending');
        return this.Descending;
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
        this.NullsFirst = this.NullsFirst ?? this.validate('NULLS FIRST');
        return NullsFirst;
      }
      private set;
    }

    public final String NullsLast {
      get {
        this.NullsLast = this.NullsLast ?? this.validate('NULLS LAST');
        return this.NullsLast;
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
        this.SystemLevel = this.SystemLevel ?? this.validate('System');
        return this.SystemLevel;
      }
      private set;
    }

    public final String UserLevel {
      get {
        this.UserLevel = this.UserLevel ?? this.validate('User');
        return this.UserLevel;
      }
      private set;
    }
  }
}
