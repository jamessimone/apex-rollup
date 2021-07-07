public virtual class RollupFieldInitializer {
  private RollupFieldInitializer() {
  }

  public static final RollupFieldInitializer Current = new RollupFieldInitializer();

  public final Datetime defaultDateTime = Datetime.newInstanceGmt(1970, 1, 1);
  public final Long maximumLongValue = (Math.pow(2, 63) - 1).longValue();
  public final Long minimumLongValue = this.maximumLongValue * -1;
  public final Integer maximumIntegerValue = 2147483647;
  public final Integer minimumIntegerValue = this.maximumIntegerValue * -1;

  public Datetime getApexCompliantDatetime(Datetime dt) {
    // one of the worst things about SOQL is that Datetimes retrieved have the millisecond values truncated
    return Datetime.newInstanceGmt(dt.yearGmt(), dt.monthGmt(), dt.dayGmt(), dt.hourGmt(), dt.minuteGmt(), dt.secondGmt());
  }

  public virtual Object getDefaultValue(SObjectField field) {
    DescribeFieldResult fieldDescribe = field.getDescribe();
    if (fieldDescribe.isDefaultedOnCreate() && fieldDescribe.getDefaultValue() != null) {
      return fieldDescribe.getDefaultValue();
    }
    // not surprisingly, "getDefaultValue" on the DescribeFieldResult returns null for fields without default values
    // this is a shame - all types *should* have default values. Instead, we have the privilege of getting to initialize them
    Object initializedDefault;
    switch on fieldDescribe.getType() {
      when CURRENCY, DOUBLE, INTEGER, LONG, PERCENT {
        initializedDefault = 0;
      }
      when DATETIME {
        initializedDefault = this.defaultDateTime;
      }
      when DATE {
        initializedDefault = this.defaultDateTime.dateGmt();
      }
      when TIME {
        initializedDefault = this.defaultDateTime.timeGmt();
      }
      when STRING, ID, TEXTAREA, URL, PHONE, EMAIL, REFERENCE, COMBOBOX {
        initializedDefault = '';
      }
      when PICKLIST, MULTIPICKLIST {
        initializedDefault = new PicklistController(fieldDescribe).getDefaultValue(field);
      }
      when else {
        throw new IllegalArgumentException('Field: ' + field + ' of type: ' + fieldDescribe.getType().name() + ' specified invalid for rollup operation');
      }
    }
    return initializedDefault;
  }

  public class PicklistController extends RollupFieldInitializer {
    private final Boolean isPicklist;
    private final Boolean isMultiSelectPicklist;
    private List<String> activeVals;
    private Map<String, Integer> picklistToRank;

    public PicklistController(DescribeFieldResult fieldDescribe) {
      super();
      DisplayType fieldType = fieldDescribe.getType();
      this.isPicklist = fieldType == DisplayType.MULTIPICKLIST || fieldType == DisplayType.PICKLIST;
      this.isMultiSelectPicklist = fieldType == DisplayType.MULTIPICKLIST;

      if (this.isPicklist) {
        this.picklistToRank = new Map<String, Integer>();
        this.activeVals = new List<String>();

        /**
         * not obvious (or even documented) but getPicklistValues ALWAYS returns
         * the picklist values in order of their appearance in the UI, which is also
         * their alleged "rank" - for example, MAX/MIN on picklists is done by which order they appear
         * in the list, instead of by the actual text values
         * */
        List<Schema.PicklistEntry> picklistVals = fieldDescribe.getPicklistValues();

        for (Integer index = 0; index < picklistVals.size(); index++) {
          PicklistEntry picklist = picklistVals[index];
          this.doBookkeepingOnPicklist(picklist);
          // all inactive values will use -1 as a sentinel value
          picklistToRank.put(picklist.getValue(), picklist.isActive() ? index : -1);
        }
      }
    }

    private void doBookkeepingOnPicklist(PicklistEntry picklist) {
      if (picklist.isDefaultValue() && this.activeVals.isEmpty()) {
        this.activeVals.add(picklist.getValue());
      } else if (picklist.isActive()) {
        this.activeVals.add(picklist.getValue());
      }
    }

    public override Object getDefaultValue(SObjectField field) {
      return this.isPicklist == false ? super.getDefaultValue(field) : this.activeVals[0];
    }

    public Boolean isPicklist() {
      return this.isPicklist;
    }

    public Boolean isMultiSelectPicklist() {
      return this.isMultiSelectPicklist;
    }

    public Boolean isTrueFor(String picklistVal, String comparisonValue, Rollup.Op operation) {
      if (this.isPicklist == false) {
        return false;
      }
      Boolean isMin = this.isMin(operation);
      if (String.isNotBlank(comparisonValue) && this.picklistToRank.containsKey(picklistVal) == false) {
        return isMin ? picklistVal < comparisonValue : picklistVal > comparisonValue;
      }
      Integer rank = this.getRank(picklistVal, operation);
      Integer comparisonRank = this.getRank(comparisonValue, operation);
      return isMin ? rank < comparisonRank : rank > comparisonRank;
    }

    public Integer getRank(String picklistVal, Rollup.Op operation) {
      return this.picklistToRank.containsKey(picklistVal) ? this.picklistToRank.get(picklistVal) : this.getSentinelValue(operation);
    }

    private Boolean isMin(Rollup.Op operation) {
      return operation.name().contains(Rollup.Op.MIN.name());
    }

    private Integer getSentinelValue(Rollup.Op operation) {
      return this.isMin(operation) ? this.maximumIntegerValue : this.minimumIntegerValue;
    }
  }
}
