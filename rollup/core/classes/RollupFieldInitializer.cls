public virtual class RollupFieldInitializer {
  public final Datetime defaultDateTime = Datetime.newInstanceGmt(1970, 1, 1);
  public final Long maximumLongValue = (Math.pow(2, 63) - 1).longValue();
  public final Long minimumLongValue = this.maximumLongValue * -1;
  public final Integer maximumIntegerValue = 2147483647;
  public final Integer minimumIntegerValue = -2147483647 - 1;

  public static final RollupFieldInitializer Current = new RollupFieldInitializer();

  private RollupFieldInitializer() {
  }

  public Datetime getApexCompliantDatetime(Datetime dt) {
    // one of the worst things about SOQL is that Datetimes retrieved have the millisecond values truncated
    return Datetime.newInstanceGmt(dt.yearGmt(), dt.monthGmt(), dt.dayGmt(), dt.hourGmt(), dt.minuteGmt(), dt.secondGmt());
  }

  public virtual Object getDefaultValue(Schema.SObjectField field) {
    DescribeFieldResult fieldDescribe = field.getDescribe();
    if (fieldDescribe.isDefaultedOnCreate() && fieldDescribe.getDefaultValue() != null) {
      return fieldDescribe.getDefaultValue();
    }
    // not surprisingly, "getDefaultValue" on the DescribeFieldResult returns null for fields without default values
    // this is a shame - all types *should* have default values. Instead, we have the privilege of getting to initialize them
    Object initializedDefault;
    switch on fieldDescribe.getType() {
      when CURRENCY, DOUBLE, LONG, PERCENT {
        initializedDefault = 0.0;
      }
      when INTEGER {
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
      when BOOLEAN {
        initializedDefault = false;
      }
      when else {
        throw new IllegalArgumentException('Field: ' + field + ' of type: ' + fieldDescribe.getType().name() + ' specified invalid for rollup operation');
      }
    }
    return initializedDefault;
  }

  public SObjectField getSObjectFieldByName(Map<String, Schema.SObjectField> fieldNameToField, String desiredField) {
    if (fieldNameToField.containsKey(desiredField)) {
      return fieldNameToField.get(desiredField);
    } else if (fieldNameToField.containsKey(desiredField + 'Id')) {
      // for lookup fields, CMDT field-level definition fields store the field name, which is outrageous
      return fieldNameToField.get(desiredField + 'Id');
    }
    return null;
  }

  public Schema.DescribeSObjectResult getDescribeFromName(String sObjectName) {
    return Schema.describeSObjects(new List<String>{ sObjectName }, SObjectDescribeOptions.DEFERRED)[0];
  }

  public Map<Id, SObject> createSafeMap(List<SObject> records) {
    Map<Id, SObject> idToRecord = new Map<Id, SObject>();
    for (SObject record : records) {
      idToRecord.put(record.Id, record);
    }
    return idToRecord;
  }

  public class PicklistController extends RollupFieldInitializer {
    private final Boolean isPicklist;
    private final Boolean isMultiSelectPicklist;
    private List<String> activeVals;
    private Map<String, Integer> picklistToRank;

    public PicklistController(Schema.DescribeFieldResult fieldDescribe) {
      super();
      Schema.DisplayType fieldType = fieldDescribe?.getType();
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
          Schema.PicklistEntry picklist = picklistVals[index];
          this.doBookkeepingOnPicklist(picklist);
          // all inactive values will use -1 as a sentinel value
          picklistToRank.put(picklist.getValue(), picklist.isActive() ? index : -1);
        }
      }
    }

    private void doBookkeepingOnPicklist(Schema.PicklistEntry picklist) {
      if (picklist.isDefaultValue() && this.activeVals.isEmpty()) {
        this.activeVals.add(picklist.getValue());
      } else if (picklist.isActive()) {
        this.activeVals.add(picklist.getValue());
      }
    }

    public override Object getDefaultValue(Schema.SObjectField field) {
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
      return this.picklistToRank?.containsKey(picklistVal) == true ? this.picklistToRank.get(picklistVal) : this.getSentinelValue(operation);
    }

    public void sort(List<String> picklistValues) {
      picklistValues.sort(new PicklistSorter(this));
    }

    private Boolean isMin(Rollup.Op operation) {
      return operation.name().contains(Rollup.Op.MIN.name());
    }

    private Integer getSentinelValue(Rollup.Op operation) {
      return this.isMin(operation) ? this.maximumIntegerValue : this.minimumIntegerValue;
    }
  }

  public class StringSorter implements System.Comparator<String> {
    public Integer compare(String first, String second) {
      return first.compareTo(second);
    }
  }

  private class PicklistSorter implements System.Comparator<String> {
    private final PicklistController picklistController;
    private final System.Comparator<String> stringSorter = new StringSorter();

    public PicklistSorter(PicklistController picklistController) {
      this.picklistController = picklistController;
    }

    public Integer compare(String firstVal, String secondVal) {
      Integer sortValue = 0;
      Integer firstRank = this.picklistController.getRank(firstVal, Rollup.Op.FIRST);
      Integer secondRank = this.picklistController.getRank(secondVal, Rollup.Op.FIRST);
      if (firstRank == this.picklistController.minimumIntegerValue || secondRank == this.picklistController.minimumIntegerValue) {
        // fall back to standard sorting if sentinel value is returned
        sortValue = this.stringSorter.compare(firstVal, secondVal);
      } else if (firstRank > secondRank) {
        sortValue = 1;
      } else if (firstRank < secondRank) {
        sortValue = -1;
      }
      return sortValue;
    }
  }
}
